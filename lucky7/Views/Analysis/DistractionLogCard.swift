//
//  DistractionLogCard.swift
//  lucky7
//

import SwiftUI
import FamilyControls
import ManagedSettings

/// "YOUR DISTRACTIONS" card on Session Analytics: one row per break taken during the
/// session, showing the app, the reason typed on the break form, and how long it lasted.
/// Sessions without breaks get a short congratulation instead.
struct DistractionLogCard: View {
    let distractions: [Distraction]
    let session: Session?

    var body: some View {
        PatternBorderedCard(edges: [.bottom], cornerRadius: 30) {
            VStack(spacing: 0) {
                Text("YOUR DISTRACTIONS")
                    .font(.custom("Special Gothic Expanded One", size: 12))
                    .foregroundColor(.black)
                    .padding(.bottom, 14)
                    .accessibilityAddTraits(.isHeader)

                if distractions.isEmpty {
                    Text("No distractions in the session, good job.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(distractions.enumerated()), id: \.element.id) { index, distraction in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.black.opacity(0.12))
                                .frame(height: 1)
                                .padding(.leading, 44)
                        }
                        row(for: distraction)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 34) // clearance above the bottom checkerboard strip
        }
    }

    private func row(for distraction: Distraction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            appIcon(for: distraction)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    appName(for: distraction)
                        .font(.custom("Special Gothic Expanded One", size: 13))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(durationText(for: distraction))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.black)
                }

                Text(reasonText(for: distraction))
                    .font(.system(size: 13))
                    .foregroundColor(Color(UIColor.darkGray))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - App identity

    /// Real app icon from the Screen Time token, with a neutral fallback for
    /// category-level breaks that have no per-app token.
    @ViewBuilder
    private func appIcon(for distraction: Distraction) -> some View {
        if let token = token(for: distraction) {
            Label(token)
                .labelStyle(.iconOnly)
                .font(.system(size: 26))
                .frame(width: 32, height: 32)
        } else {
            Image(systemName: "questionmark.app.dashed")
                .font(.system(size: 26))
                .foregroundColor(.gray)
                .frame(width: 32, height: 32)
        }
    }

    /// Real app name from the token, falling back to the stored display name.
    @ViewBuilder
    private func appName(for distraction: Distraction) -> some View {
        if let token = token(for: distraction) {
            Label(token).labelStyle(.titleOnly)
        } else {
            Text(resolvedName(distraction))
        }
    }

    private func token(for distraction: Distraction) -> ApplicationToken? {
        guard let data = distraction.tokenData else { return nil }
        return try? JSONDecoder().decode(ApplicationToken.self, from: data)
    }

    private func resolvedName(_ distraction: Distraction) -> String {
        if let name = distraction.appDisplayName, !name.isEmpty { return name }
        return distraction.appOpened.isEmpty ? "App" : distraction.appOpened
    }

    // MARK: - Text

    private func reasonText(for distraction: Distraction) -> String {
        let reason = distraction.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? "No reason given" : reason
    }

    /// "15 min", "1 hour", "1 hour 10 min" — clamped to the session like the
    /// Distracted Duration stat, so the rows add up to it.
    private func durationText(for distraction: Distraction) -> String {
        let seconds = session.map { distraction.duration(overlapping: $0) } ?? distraction.distractionDuration
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        let hourText = "\(hours) hour\(hours == 1 ? "" : "s")"
        return rest == 0 ? hourText : "\(hourText) \(rest) min"
    }
}
