//
//  MonitorScreen.swift
//  lucky7
//

import SwiftUI
import SwiftData

struct MonitorScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.startTime, order: .reverse) private var sessions: [Session]
    @Query private var periodWraps: [PeriodWrap]
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var weeklyNotReady = false

    /// Sessions grouped by calendar month (newest first), each month split into real
    /// 7-day weeks. A week that straddles a month boundary is kept whole and filed
    /// under the month most of its sessions fall in, so there's no stray fragment week.
    private var monthGroups: [MonthGroup] {
        let calendar = Calendar.current
        let now = Date()
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start

        // 1. Group sessions into real 7-day calendar weeks.
        let byWeekStart = Dictionary(grouping: sessions) { session -> Date in
            calendar.dateInterval(of: .weekOfYear, for: session.startTime)?.start ?? session.startTime
        }

        // 2. For each week, choose the month most of its sessions land in (ties -> later month).
        let pendingWeeks = byWeekStart.map { (weekStart, weekSessions) -> (weekStart: Date, monthStart: Date, sessions: [Session], total: TimeInterval, isCurrent: Bool) in
            let sorted = weekSessions.sorted { $0.startTime > $1.startTime }
            let total = sorted.reduce(0) { $0 + $1.actualDuration }
            let byMonth = Dictionary(grouping: sorted) { session in
                calendar.date(from: calendar.dateComponents([.year, .month], from: session.startTime)) ?? session.startTime
            }
            let monthStart = byMonth.max {
                $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key < $1.key
            }?.key ?? weekStart
            return (weekStart, monthStart, sorted, total, weekStart == currentWeekStart)
        }

        // 3. Bucket weeks by month; number them oldest-first, display newest-first.
        let byMonth = Dictionary(grouping: pendingWeeks) { $0.monthStart }

        return byMonth.keys.sorted(by: >).map { monthStart in
            let weeksAsc = (byMonth[monthStart] ?? []).sorted { $0.weekStart < $1.weekStart }
            let weeks: [WeekGroup] = weeksAsc.enumerated()
                .map { index, week in
                    WeekGroup(
                        id: week.weekStart,
                        number: index + 1,
                        sessions: week.sessions,
                        totalDuration: week.total,
                        isCurrent: week.isCurrent
                    )
                }
                .sorted { $0.id > $1.id }
            let monthTotal = weeksAsc.reduce(0) { $0 + $1.total }
            return MonthGroup(
                id: monthStart,
                weeks: weeks,
                totalDuration: monthTotal,
                isCurrentMonth: monthStart == currentMonthStart
            )
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                if monthGroups.isEmpty {
                    emptyState
                } else {
                    feed
                }
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
            .overlay {
                if weeklyNotReady {
                    WrapNotReadyModal(
                        title: "Not ready yet",
                        message: "Your weekly analytics isn't ready yet. Please wait until the end of the week.",
                        onDismiss: { weeklyNotReady = false }
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSearch) {
                SessionSearchView()
            }
        }
        .task {
            // Keep recaps fresh when viewing history (no-op when nothing's due).
            await WrapRollupService.rollUpIfNeeded(context: modelContext)
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsScreen()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 19))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens app settings")

            Spacer()

            Text("My Sessions")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Search sessions")
            .accessibilityHint("Search by title or date")
            .accessibilityInputLabels(["search", "find session"])
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(monthGroups) { month in
                    MonthHeader(title: month.title)

                    // The monthly rewind only appears once its recap has actually been
                    // generated (so the current, in-progress month shows no button).
                    if periodWraps.contains(where: { $0.kind == "monthly" && $0.periodKey == month.periodKey }) {
                        NavigationLink {
                            WrappedVideoScreen(
                                kind: .monthly(
                                    periodKey: month.periodKey,
                                    periodEnd: month.periodEnd,
                                    title: "\(month.rewindName) Rewind",
                                    periodLabel: month.title,
                                    duration: month.totalDuration
                                ),
                                videoFrames: month.snapshotFrames
                            )
                        } label: {
                            RewindRow(
                                title: "\(month.rewindName) Rewind",
                                duration: TimeFormatter.shortDuration(month.totalDuration)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(month.weeks) { week in
                        WeekCard(week: week, onBlocked: { weeklyNotReady = true })
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "play.tv")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.7))
                .accessibilityDecorative()
            Text("No sessions yet")
                .font(.custom("Special Gothic Expanded One", size: 23))
                .foregroundColor(.white)
            Text("Complete a Rush Hour session to save your \ntimelapses and reviews here.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Grouping models

struct MonthGroup: Identifiable {
    let id: Date            // first day of the month
    let weeks: [WeekGroup]
    let totalDuration: TimeInterval
    let isCurrentMonth: Bool

    /// "JUNE 2026"
    var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: id).uppercased()
    }

    /// "June" — used for the rewind label.
    var rewindName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: id)
    }

    var periodKey: String { WrapStorage.monthKey(for: id) }
    var periodEnd: Date { Calendar.current.dateInterval(of: .month, for: id)?.end ?? id }

    /// Decoded snapshots from every session in the month, used as wrap preview frames.
    var snapshotFrames: [UIImage] {
        weeks.flatMap { $0.snapshotFrames }
    }
}

struct WeekGroup: Identifiable {
    let id: Date            // start of the week
    let number: Int         // sequential position within its month (1 = earliest)
    let sessions: [Session]
    let totalDuration: TimeInterval
    let isCurrent: Bool     // contains today — starts expanded

    var title: String { "Week \(number)" }

    /// Decoded snapshots from every session this week, used as wrap preview frames.
    var snapshotFrames: [UIImage] {
        sessions.flatMap { $0.snapshotImages }.compactMap { UIImage(data: $0) }
    }
}

// MARK: - Week card (collapsible)

struct WeekCard: View {
    let week: WeekGroup
    /// Called instead of navigating when the week hasn't ended yet.
    var onBlocked: () -> Void = {}
    @State private var userExpanded: Bool

    init(week: WeekGroup, onBlocked: @escaping () -> Void = {}) {
        self.week = week
        self.onBlocked = onBlocked
        // Current week starts expanded; past weeks start collapsed.
        _userExpanded = State(initialValue: week.isCurrent)
    }

    /// Current week starts expanded, but the user can collapse it.
    private var isExpanded: Bool {
        userExpanded
    }

    /// The "Week N" pill label.
    private var weekPill: some View {
        HStack(spacing: 6) {
            Text(week.title)
                .font(.system(size: 14, weight: .heavy))
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.black))
        .accessibilityLabel("\(week.title) analytics")
        .accessibilityHint("Opens weekly focus statistics")
        .accessibilityInputLabels(["week \(week.number)", "analytics", "week analytics"])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // The "Week N" pill opens the weekly analytics — but only once the week has
                // ended. During the in-progress week it shows a "not ready" popup instead.
                if week.isCurrent {
                    Button(action: onBlocked) { weekPill }
                        .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        WeeklyAnalyticScreen(weekStart: week.id)
                    } label: { weekPill }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Duration + chevron toggles expand/collapse.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        userExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(TimeFormatter.shortDuration(week.totalDuration))
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundColor(.black)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse \(week.title)" : "Expand \(week.title)")
                .accessibilityValue(TimeFormatter.longDuration(week.totalDuration))
                .accessibilityHint("Shows or hides sessions in this week")
            }
            .padding(16)

            if isExpanded {
                ForEach(week.sessions) { session in
                    rowDivider

                    NavigationLink {
                        // No live capture frames here; SessionAnalytics pulls a
                        // poster frame from the saved wrapped video instead of
                        // showing an activity snapshot.
                        SessionAnalytics(sessionId: session.id)
                    } label: {
                        SessionRow(session: session, showsCard: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens session analytics and video")
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.black, lineWidth: 2)
                )
        )
    }

    /// Hairline separator between the header and each session row.
    private var rowDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

// MARK: - Subcomponents

struct MonthHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.custom("Special Gothic Expanded One", size: 24))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

struct SessionRow: View {
    let session: Session
    /// When false the row is rendered bare (no white card / shadow) so it can sit
    /// inside the Week card with divider lines. Search keeps the standalone card.
    var showsCard: Bool = true
    /// Poster frame extracted from the saved wrapped video (a real session frame,
    /// not a user-uploaded activity snapshot).
    @State private var posterFrame: UIImage?

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: session.startTime).uppercased()
    }

    private var dayText: String {
        String(Calendar.current.component(.day, from: session.startTime))
    }

    private var titleText: String {
        session.title.isEmpty ? "Untitled Session" : session.title
    }

    /// Extracts a poster frame from the saved wrapped video. Raw clips are export
    /// sources only, so sessions without a final wrap keep the placeholder.
    private func loadPosterFrame() async {
        guard posterFrame == nil, let url = posterSourceURL else { return }
        let frame = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = SessionRecordingViewModel.extractPreviewFrames(from: url, count: 1).first
                continuation.resume(returning: image)
            }
        }
        posterFrame = frame
    }

    private var posterSourceURL: URL? {
        WrapStorage.resolveVideoURL(session.wrappedVideoPath)
    }

    private var posterTaskKey: String {
        session.wrappedVideoPath ?? ""
    }

    var body: some View {
        HStack(spacing: 16) {
            // Date column
            VStack(spacing: 2) {
                Text(monthText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                Text(dayText)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.gray)
            }
            .frame(width: 40)

            // Thumbnail: a real frame from the session video, otherwise a placeholder.
            Group {
                if let posterFrame {
                    Image(uiImage: posterFrame)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.crop.rectangle.fill")
                                .foregroundColor(.gray)
                        )
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .task(id: posterTaskKey) {
                posterFrame = nil
                await loadPosterFrame()
            }

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.black)
                    .lineLimit(2)
                Text(TimeFormatter.longDuration(session.actualDuration))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.black.opacity(0.7))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titleText), \(monthText) \(dayText)")
        .accessibilityValue(TimeFormatter.longDuration(session.actualDuration))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if showsCard {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                // Neo-brutalist solid shadow
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black)
                        .offset(y: 4)
                )
        }
    }
}

struct RewindRow: View {
    var title: String
    var duration: String

    var body: some View {
        HStack(spacing: 16) {
            // Play Icon
            Image(systemName: "play.circle")
                .font(.system(size: 32, weight: .heavy))
                .foregroundColor(.white)
                .padding(4)
//                .background(Circle().fill(Color.white))
//                .overlay(Circle().stroke(Color.black, lineWidth: 2))

            // Title with outline effect (stacked shadows mimic a hard black stroke)
            Text(title)
                .font(.custom("Special Gothic Expanded One", size: 20))
                .foregroundColor(.white)

            Spacer()

            Text(duration)
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color.red, Color.yellow, Color.green],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(duration)")
        .accessibilityHint("Plays the monthly session rewind video")
    }
}

// MARK: - Preview

@MainActor
func sampleMonitorContainer() -> ModelContainer {
    let container = try! ModelContainer(
        for: Session.self, PeriodWrap.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let calendar = Calendar.current
    let now = Date()

    let samples: [(daysAgo: Int, duration: TimeInterval, title: String)] = [
        (0,  3 * 3600 + 20 * 60, "Morning Session Rush!"),
        (1,  3 * 3600 + 20 * 60, "Morning Session Rush!"),
        (2,  3 * 3600 + 20 * 60, "Morning Session Rush!"),
        (9,  2 * 3600 + 10 * 60, "Last Week Grind"),
        (35, 2 * 3600 + 45 * 60, "Late Night Grind"),
        (40, 50 * 60,            "Quick Focus"),
    ]

    for sample in samples {
        let start = calendar.date(byAdding: .day, value: -sample.daysAgo, to: now) ?? now
        context.insert(
            Session(
                userId: UUID(),
                duration: sample.duration,
                startTime: start,
                endTime: start.addingTimeInterval(sample.duration),
                title: sample.title
            )
        )
    }
    try? context.save()

    return container
}

#Preview {
    MonitorScreen()
        .modelContainer(sampleMonitorContainer())
}
