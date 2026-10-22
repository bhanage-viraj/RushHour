//
//  WeeklyAnalyticScreen.swift
//  lucky7
//
//  Created by Ida Bagus Putu Ryan Paramasatya Putra on 02/06/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import FamilyControls
import ManagedSettings

struct WeeklyAnalyticScreen: View {
    /// First day of the week initially shown (passed in from the history screen).
    var weekStart: Date = Date()
    /// Month owning the initial history segment. When a calendar week crosses a
    /// month boundary, analytics must not pull records from the adjacent month.
    var segmentMonthStart: Date? = nil

    @Environment(\.dismiss) private var dismiss

    /// Whole store; the displayed week is filtered out of these so the chevrons
    /// can move between weeks without pushing a new screen.
    @Query private var allSessions: [Session]
    @Query private var allDistractions: [Distraction]

    /// A date inside the selected month-clipped week; nil uses the History selection.
    @State private var selectedSegmentDate: Date?

    private let calendar = Calendar.current

    /// First day of the week currently being shown.
    private var currentWeekStart: Date {
        let date = selectedSegmentDate ?? weekStart
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// The month associated with the displayed segment. The initial value comes
    /// directly from History because a cross-month week has two valid month sides.
    private var currentSegmentMonthStart: Date {
        if selectedSegmentDate == nil, let segmentMonthStart { return segmentMonthStart }
        let date = selectedSegmentDate ?? weekStart
        return calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    /// Calendar-week interval clipped to its owning month.
    private var currentSegmentInterval: DateInterval? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: currentWeekStart),
              let month = calendar.dateInterval(of: .month, for: currentSegmentMonthStart) else {
            return nil
        }
        let start = max(week.start, month.start)
        let end = min(week.end, month.end)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    private var weekPeriodKey: String { WrapStorage.weekKey(for: currentWeekStart, calendar: calendar) }
    private var weekPeriodEnd: Date {
        calendar.dateInterval(of: .weekOfYear, for: currentWeekStart)?.end ?? currentWeekStart
    }

    /// Sessions inside the displayed week segment. The month-clipped interval keeps
    /// September records out of an October segment (and vice versa).
    private var sessions: [Session] {
        guard let interval = currentSegmentInterval else { return [] }
        return allSessions.filter { $0.startTime >= interval.start && $0.startTime < interval.end }
    }

    /// The recap remains a whole-calendar-week video, even when analytics shows a fragment.
    private var recapSessions: [Session] {
        allSessions.filter { $0.startTime >= currentWeekStart && $0.startTime < weekPeriodEnd }
    }

    private var recapDuration: TimeInterval {
        recapSessions.reduce(0) { $0 + $1.focusDuration() }
    }

    private var recapRangeLabel: String {
        WrapStorage.weekLabel(start: currentWeekStart, end: weekPeriodEnd, calendar: calendar)
    }

    private var videoFrames: [UIImage] {
        recapSessions.flatMap { $0.snapshotImages }.compactMap { UIImage(data: $0) }
    }

    /// Current month-clipped segment, including the second side of a cross-month week.
    private var thisSegmentStart: Date {
        let now = Date()
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return max(week, month)
    }

    private var earliestSegmentStart: Date? {
        guard let earliest = allSessions.map(\.startTime).min(),
              let week = calendar.dateInterval(of: .weekOfYear, for: earliest),
              let month = calendar.dateInterval(of: .month, for: earliest) else { return nil }
        return max(week.start, month.start)
    }

    private var isAtCurrentWeek: Bool {
        (currentSegmentInterval?.start ?? currentWeekStart) >= thisSegmentStart
    }

    private var canGoBack: Bool {
        guard let earliest = earliestSegmentStart else { return false }
        return (currentSegmentInterval?.start ?? currentWeekStart) > earliest
    }

    private func changeWeek(by direction: Int) {
        guard let interval = currentSegmentInterval else { return }
        let candidate = direction < 0
            ? calendar.date(byAdding: .day, value: -1, to: interval.start)
            : interval.end
        guard let candidate, candidate <= thisSegmentStart else { return }
        if let earliest = earliestSegmentStart, candidate < earliest { return }
        withAnimation(.easeInOut(duration: 0.2)) { selectedSegmentDate = candidate }
    }

    private var displayFrame: [UIImage] {
        guard !videoFrames.isEmpty else { return [] }

        if videoFrames.count <= 3 {
            return videoFrames
        }

        let firstFrame = videoFrames.first!
        let middleFrame = videoFrames[videoFrames.count / 2]
        let lastFrame = videoFrames.last!

        return [firstFrame, middleFrame, lastFrame]
    }

    // MARK: - Weekly aggregation

    private var sessionIDs: Set<UUID> { Set(sessions.map(\.id)) }

    private var weekDistractions: [Distraction] {
        allDistractions.filter { sessionIDs.contains($0.sessionId) }
    }

    private var sessionsByID: [UUID: Session] {
        Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    private func distractedDuration(_ distraction: Distraction) -> TimeInterval {
        guard let session = sessionsByID[distraction.sessionId] else { return 0 }
        return distraction.duration(overlapping: session)
    }

    private var weekTotalDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.actualDuration }
    }

    private var totalDistracted: TimeInterval {
        weekDistractions.reduce(0) { $0 + distractedDuration($1) }
    }

    private var totalFocus: TimeInterval {
        focusDuration(for: sessions)
    }

    private func focusDuration(for selectedSessions: [Session]) -> TimeInterval {
        let bySession = Dictionary(grouping: weekDistractions, by: \.sessionId)
        return selectedSessions.reduce(0) { total, session in
            let distracted = bySession[session.id, default: []].reduce(0) {
                $0 + $1.duration(overlapping: session)
            }
            return total + session.focusDuration(distractedDuration: distracted)
        }
    }

    private var avgSessionLength: TimeInterval {
        sessions.isEmpty ? 0 : weekTotalDuration / Double(sessions.count)
    }

    private var avgDistractedLength: TimeInterval {
        weekDistractions.isEmpty ? 0 : totalDistracted / Double(weekDistractions.count)
    }

    private var totalSessionTimeText: String {
        TimeFormatter.shortDuration(weekTotalDuration)
    }

    private var weekRangeLabel: String {
        let start = currentSegmentInterval?.start ?? currentWeekStart
        let exclusiveEnd = currentSegmentInterval?.end
            ?? calendar.date(byAdding: .day, value: 7, to: start)
            ?? start
        let end = calendar.date(byAdding: .day, value: -1, to: exclusiveEnd) ?? start
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(formatted(start, "d")) - \(formatted(end, "d MMMM yyyy"))"
        } else if calendar.isDate(start, equalTo: end, toGranularity: .year) {
            return "\(formatted(start, "d MMM")) - \(formatted(end, "d MMM yyyy"))"
        } else {
            return "\(formatted(start, "d MMM yyyy")) - \(formatted(end, "d MMM yyyy"))"
        }
    }

    private var sessionStats: [[String: String]] {
        [
            ["title1": "Focus Duration",
             "value1": TimeFormatter.shortDuration(totalFocus),
             "title2": "Distracted Duration",
             "value2": TimeFormatter.shortDuration(totalDistracted)],
            ["title1": "Avg Session",
             "value1": minutesText(avgSessionLength),
             "title2": "Avg Distracted",
             "value2": minutesText(avgDistractedLength)],
            ["title1": "Session Completed",
             "value1": "\(sessions.count) times",
             "title2": "Distracted Frequency",
             "value2": "\(weekDistractions.count) times"],
        ]
    }

    /// Per-day focus / distracted split for the seven days of the week.
    private var dayStats: [DayStat] {
        guard let interval = currentSegmentInterval else { return [] }
        let dayCount = max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0)
        return (0..<dayCount).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: interval.start) ?? interval.start
            let daySessions = sessions.filter { calendar.isDate($0.startTime, inSameDayAs: day) }
            let dayIDs = Set(daySessions.map(\.id))
            let distracted = weekDistractions
                .filter { dayIDs.contains($0.sessionId) }
                .reduce(0) { $0 + distractedDuration($1) }
            let focus = focusDuration(for: daySessions)
            return DayStat(
                date: day,
                focusMinutes: focus / 60,
                distractedMinutes: distracted / 60,
                hasSessions: !daySessions.isEmpty
            )
        }
    }

    private var weekdayBars: [BarChartData] {
        dayStats.map {
            BarChartData(label: formatted($0.date, "EEEEE"),
                         primary: $0.focusMinutes,
                         secondary: $0.distractedMinutes)
        }
    }

    /// Scales the chart axis to the busiest day, in 30-minute steps (min 2h).
    private var chartConfig: BarChartConfig {
        var config = BarChartConfig()
        let maxMinutes = dayStats.map { $0.focusMinutes + $0.distractedMinutes }.max() ?? 0
        let step = max(30, Int(ceil(maxMinutes / 4 / 30)) * 30)
        let top = step * 4
        config.maxValue = Double(top)
        config.gridLines = [top, top - step, top - 2 * step, top - 3 * step, 0]
        return config
    }

    private var mostFocusedDayText: String {
        guard let best = dayStats.filter({ $0.hasSessions })
            .max(by: { $0.focusMinutes < $1.focusMinutes }) else { return "—" }
        return formatted(best.date, "EEEE")
    }

    private var leastFocusedDayText: String {
        guard let worst = dayStats.filter({ $0.hasSessions })
            .min(by: { $0.focusMinutes < $1.focusMinutes }) else { return "—" }
        return formatted(worst.date, "EEEE")
    }

    /// The three apps that ate the most time this week, aggregated by their
    /// Screen Time token so the real icon/name can be shown via `Label(token)`.
    /// Category-level distractions (no per-app token) fall back to their name.
    private var topDistractingApps: [DistractingApp] {
        var byToken: [ApplicationToken: (name: String, duration: TimeInterval)] = [:]
        var byName: [String: TimeInterval] = [:]

        for distraction in weekDistractions {
            let duration = distractedDuration(distraction)
            guard duration > 0 else { continue }
            if let token = decodeToken(distraction.tokenData) {
                var entry = byToken[token] ?? (resolvedName(distraction), 0)
                entry.duration += duration
                if entry.name == "Blocked App" { entry.name = resolvedName(distraction) }
                byToken[token] = entry
            } else {
                byName[resolvedName(distraction), default: 0] += duration
            }
        }

        let tokenApps = byToken.map { key, value in
            DistractingApp(id: "token-\(key.hashValue)", token: key, name: value.name, duration: value.duration)
        }
        let categoryApps = byName.map { name, duration in
            DistractingApp(id: "name-\(name)", token: nil, name: name, duration: duration)
        }

        return (tokenApps + categoryApps)
            .sorted { $0.duration > $1.duration }
            .prefix(3)
            .map { $0 }
    }

    private func decodeToken(_ data: Data?) -> ApplicationToken? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(ApplicationToken.self, from: data)
    }

    private func resolvedName(_ distraction: Distraction) -> String {
        distraction.resolvedAppName ?? "Blocked App"
    }

    /// Real app icon from the Screen Time token, with a neutral fallback for
    /// category-level distractions that have no per-app token.
    @ViewBuilder
    private func appIcon(for app: DistractingApp) -> some View {
        if let token = app.token {
            Label(token)
                .labelStyle(.iconOnly)
                .font(.system(size: 30))
                .frame(width: 36, height: 36)
        } else {
            Image(systemName: "questionmark.app.dashed")
                .font(.system(size: 30))
                .foregroundColor(.gray)
                .frame(width: 36, height: 36)
        }
    }

    // MARK: - Formatting helpers

    private func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func minutesText(_ seconds: TimeInterval) -> String {
        String(format: "%.1f minutes", seconds / 60)
    }

    // MARK: - Header

    private var weekPickerBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")
            .accessibilityInputLabels(["back", "go back"])

            HStack(spacing: 0) {
                Button { changeWeek(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.35)
                .accessibilityLabel("Previous week")
                .accessibilityInputLabels(["previous week"])

                Text(weekRangeLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Button { changeWeek(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .disabled(isAtCurrentWeek)
                .opacity(isAtCurrentWeek ? 0.35 : 1)
                .accessibilityLabel("Next week")
                .accessibilityInputLabels(["next week", "forward"])
            }
            .foregroundColor(.white)
            .padding(4)
            .background(Capsule().fill(Color.black))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Week selector")
            .accessibilityValue(weekRangeLabel)
        }
    }

    /// Horizontal swipe to page between weeks (swipe left = next, right = previous).
    /// Runs simultaneously with the vertical scroll and only fires on a clearly
    /// horizontal drag, so it doesn't fight scrolling or taps.
    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy), abs(dx) > 60 else { return }
                changeWeek(by: dx < 0 ? 1 : -1)
            }
    }

    var body: some View {
                VStack(spacing: 0) {
                    weekPickerBar
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                    ScrollView(showsIndicators: false) {
                        VStack{
                        Color.clear
                            .frame(height: 24)
                        
                        VStack{
                            Text("Total Session Time")
                                .font(.custom("Special Gothic Expanded One", size: 14))
                            Text(totalSessionTimeText)
                                .font(.custom("Special Gothic Expanded One", size: 50))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        .foregroundStyle(.white)
                        
                        Color.clear
                            .frame(height: 24)
                        
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.white)
                                .overlay(alignment: .top) {
                                    Image("BlackWhitePattern")
                                        .resizable()
                                        .frame(height: 12)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.black, lineWidth: 1))
                                .padding(.top, 12)
                                .frame(height: 280)
                            
                            VStack{
                                Spacer()
                                
                                VStack{
                                    ForEach(Array(sessionStats.enumerated()), id: \.offset) { index, stat in
                                        HStack{
                                            VStack(alignment: .center){
                                                Text(stat["title1"] ?? "")
                                                    .font(.system(size: 10))
                                                Text(stat["value1"] ?? "")
                                                    .font(.custom("Special Gothic Expanded One", size: index < 1 ? 28 : 16))
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.65)
                                            }
                                            .frame(maxWidth: .infinity)
                                            
                                            VStack(alignment: .center){
                                                Text(stat["title2"] ?? "")
                                                    .font(.system(size: 10))
                                                Text(stat["value2"] ?? "")
                                                    .font(.custom("Special Gothic Expanded One", size: index < 1 ? 28 : 16))
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.65)
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                        .padding(.bottom, 12)
                                    }
                                }
                            }
                            .padding()
                            
                            NavigationLink(destination: WrappedVideoScreen(
                                kind: .weekly(
                                    periodKey: weekPeriodKey,
                                    periodEnd: weekPeriodEnd,
                                    title: "Full-week Rewind",
                                    periodLabel: recapRangeLabel,
                                    duration: recapDuration
                                ),
                                videoFrames: videoFrames
                            )) {
                                ZStack{
                                    SnapshotsView(images: displayFrame)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .offset(y: -76)
                                    
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 16, weight: .black))
                                        .foregroundColor(.white)
                                        .zIndex(1)
                                        .frame(width: 48, height: 48)
                                        .background(Circle().fill(Color.black))
                                        .overlay(alignment: .bottom) {
                                            Text("Full-week recap")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.black)
                                                .fixedSize()
                                                .offset(y: 18)
                                        }
                                        .offset(y: -32)
                                }
                            }
                            .accessibilityLabel("Play full-week recap")
                            .accessibilityHint(recapRangeLabel)
                        }
                        
                        PatternBorderedCard(edges: [], cornerRadius: 24) {
                            VStack(spacing: 0) {
                                Text("WHAT YOUR WEEK LOOKS LIKE?")
                                    .font(.custom("Special Gothic Expanded One", size: 14))
                                    .foregroundColor(.black)
                                    .padding(.top, 20)

                                BarChartView(data: weekdayBars, config: chartConfig)
                                    .frame(height: 300)
                                    .padding(24)
                            }
                        }
                        .padding(.top, 12)
                        
                        HStack{
                            ZStack{
                                Color.white
                                    .cornerRadius(24)
                                    .shadow(color: .black, radius: 0, x: 0, y: 0)
                                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.black, lineWidth: 1))
                                    .padding(.top, 12)
                                    .frame(height: 78)
                                
                                VStack(){
                                    Text("MOST FOCUSED DAY")
                                        .font(.system(size: 10))

                                    Text(mostFocusedDayText)
                                        .font(.custom("Special Gothic Expanded One", size: 15))
                                        .padding(.top, 1)
                                }
                                .offset(y: 8)
                            }
                            
                            ZStack{
                                Color.white
                                    .cornerRadius(24)
                                    .shadow(color: .black, radius: 0, x: 0, y: 0)
                                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.black, lineWidth: 1))
                                    .padding(.top, 12)
                                    .frame(height: 78)
                                
                                VStack(){
                                    Text("LEAST FOCUSED DAY")
                                        .font(.system(size: 10))

                                    Text(leastFocusedDayText)
                                        .font(.custom("Special Gothic Expanded One", size: 15))
                                        .padding(.top, 1)
                                }
                                .offset(y: 8)
                            }
                        }
                        
                        PatternBorderedCard(edges: [.bottom], cornerRadius: 24) {
                            VStack(spacing: 0) {
                                Text("MOST DISTRACTING APPS")
                                    .font(.custom("Special Gothic Expanded One", size: 14))
                                    .foregroundColor(.black)
                                    .padding(.top, 20)

                                VStack(spacing: 0) {
                                    if topDistractingApps.isEmpty {
                                        Text("No distractions this week 🎉")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 32)
                                    } else {
                                        ForEach(Array(topDistractingApps.enumerated()), id: \.element.id) { index, app in
                                            HStack {
                                                HStack(spacing: 16) {
                                                    Text("\(index + 1)")
                                                        .font(.custom("Special Gothic Expanded One", size: 15))

                                                    appIcon(for: app)

                                                    Text(app.name)
                                                        .font(.custom("Special Gothic Expanded One", size: 15))
                                                        .foregroundColor(.black)
                                                        .lineLimit(1)
                                                }
                                                Spacer()
                                                Text(TimeFormatter.shortDuration(app.duration))
                                            }
                                            .padding()

                                            if index < topDistractingApps.count - 1 {
                                                Divider()
                                            }
                                        }
                                    }
                                }
                                .padding()
                                .padding(.bottom, 12)
                            }
                        }
                        .padding(.top, 12)
                    }
                    .foregroundStyle(.black)
                }
                .padding(.horizontal, 24)
                .simultaneousGesture(weekSwipeGesture)
                }
            .background {
                Color("CanvasBlue")
                    .overlay {
                        Image("PatternBackground")
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .hidesFloatingTabBar()
    }
}

// MARK: - Models

/// One distracting app aggregated for the week.
private struct DistractingApp: Identifiable {
    let id: String
    let token: ApplicationToken?
    let name: String
    let duration: TimeInterval
}

// MARK: - Per-day model

private struct DayStat {
    let date: Date
    let focusMinutes: Double
    let distractedMinutes: Double
    let hasSessions: Bool
}

#Preview {
    let calendar = Calendar.current
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()

    let container = try! ModelContainer(
        for: Session.self, Distraction.self, PeriodWrap.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    // Seed two weeks so the chevrons have somewhere to navigate.
    for offset in 0..<11 {
        let start = calendar.date(byAdding: .day, value: -offset, to: weekStart) ?? weekStart
        container.mainContext.insert(
            Session(
                userId: UUID(),
                duration: 3600,
                startTime: start,
                endTime: start.addingTimeInterval(TimeInterval(3600 + offset * 600)),
                title: "Session \(offset + 1)"
            )
        )
    }

    return NavigationStack {
        WeeklyAnalyticScreen(weekStart: weekStart)
    }
    .modelContainer(container)
}
