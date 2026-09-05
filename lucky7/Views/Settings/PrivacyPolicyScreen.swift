import SwiftUI

struct PrivacyPolicyScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("Privacy Policy")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Last updated: September 3, 2026")
                            .font(.subheadline)

                        Text(PrivacyPolicyContent.introduction)
                    }

                    ForEach(PrivacyPolicyContent.sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Text(section.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.body)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(.white)
        .background {
            ZStack {
                Color("CanvasBlue")
                Image("PatternBackground")
                    .resizable()
                    .scaledToFill()
                    .accessibilityDecorative()
            }
            .ignoresSafeArea()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private enum PrivacyPolicyContent {
    struct Section {
        let title: String
        let body: String
    }

    static let introduction = """
    This Privacy Policy describes how Rush Hour ("the App," "we," "us," or "our") handles information when you use our iOS application. Rush Hour is a focus and screen-time management app that uses Apple's Screen Time (Family Controls) framework to help you limit or block distracting apps and categories.

    If you have questions about this policy, contact us at: rushhourada@gmail.com

    Website: https://rush-hour-rho.vercel.app
    """

    static let sections: [Section] = [
        Section(title: "1. Summary", body: """
        Rush Hour is designed to work primarily on your device, using Apple's built-in Screen Time APIs (Family Controls, Managed Settings, and Device Activity). We do not require an account, and we do not operate a backend server that stores your personal data. Your app-selection choices, usage schedules, and screen-time activity are processed locally by Apple's frameworks and are not transmitted to us.
        """),
        Section(title: "2. Information We Do Not Collect", body: """
        We do not collect, and Rush Hour does not transmit off your device:

        Your name, email address, or other contact information

        The specific list of apps or app categories you choose to restrict or block, or your usage schedules (this selection is handled by Apple's Family Activity Picker and stored using Apple's encrypted, on-device tokens, which are opaque even to us as developers)

        Your actual screen time, app usage statistics, or activity reports

        Photos, contacts, location, health, or financial data

        Any data via a jailbreak or device-integrity check beyond a local yes/no determination used to protect the app's core functionality (see Section 4)
        """),
        Section(title: "3. How the Screen Time / Family Controls Feature Works", body: """
        Rush Hour uses Apple's Family Controls, Managed Settings, and Device Activity frameworks to let you:

        Select apps, websites, or categories you want to restrict (via Apple's system picker - Rush Hour never sees which specific apps you selected, only anonymized tokens provided by Apple)

        Apply a "shield" screen (via a Shield Action / Shield Configuration extension) when you try to open a restricted app

        Display a widget summarizing your restriction status

        All of this processing happens on-device, within Apple's sandboxed frameworks. Apple's system, not Rush Hour or its developer, enforces the privacy boundary that keeps your specific app selections opaque to the app itself. We do not have access to, and do not collect, which individual apps you have chosen to restrict.
        """),
        Section(title: "4. Jailbreak / Device Integrity Detection", body: """
        Rush Hour includes a jailbreak-detection component (RushHourJailBreakMonitor) that checks for signs of device tampering (jailbreaking) that could allow restrictions to be bypassed. This check:

        Runs locally on your device

        Produces only a local pass/fail result used to enforce app functionality (for example, warning you or disabling bypass routes)

        Does not collect or transmit any device-identifying information to us
        """),
        Section(title: "5. Data Stored Locally", body: """
        Preferences such as your restriction schedules, streaks, or app settings may be stored locally on your device (for example, using UserDefaults, a local database, or Apple's Managed Settings Store) so the app functions correctly and your widget stays up to date. This data stays on your device and in your iCloud backup (if you have iCloud device backups enabled) - we do not have a server that receives it.
        """),
        Section(title: "6. Third-Party Services", body: """
        Rush Hour does not integrate any third-party analytics, advertising, crash-reporting, or backend/cloud services. We do not share your data with any third party, because Rush Hour does not collect data to share. All functionality is provided using Apple's own system frameworks (Family Controls, Screen Time, Device Activity, WidgetKit), which are governed by Apple's own privacy practices (see Section 7).

        If this changes in a future update (for example, if analytics or a backend service is added), this Privacy Policy will be updated accordingly before that update is released, and the App Store Privacy Nutrition Label will be revised to match.
        """),
        Section(title: "7. Apple Frameworks", body: """
        Rush Hour relies on Apple's Family Controls, Screen Time, Device Activity, and WidgetKit APIs. Apple's own data handling for these frameworks is governed by Apple's Privacy Policy, not this document. We are not responsible for, and do not have visibility into, Apple's internal handling of Screen Time data.
        """),
        Section(title: "8. Children's Privacy", body: """
        Rush Hour does not knowingly collect personal information from children. Because the app processes Screen Time data entirely on-device without transmitting it to us, no personal data is collected from users of any age. If you believe a child has provided us with personal information (for example, via a support email), contact us at the address above and we will delete it.
        """),
        Section(title: "9. Data Retention and Deletion", body: """
        Since we do not collect or store your data on any server, there is no remote data for us to retain or delete. Uninstalling the app removes all locally stored app data from your device (subject to standard iOS behavior and any iCloud backups you control).
        """),
        Section(title: "10. Your Rights", body: """
        Because Rush Hour does not collect personal data on our servers, most data-subject rights (access, correction, deletion, portability) are automatically satisfied - your data lives only on your device, under your control. If you have questions or requests regarding this policy, contact us at rushhourada@gmail.com.
        """),
        Section(title: "11. Changes to This Policy", body: """
        We may update this Privacy Policy from time to time. Changes will be posted on this page with a revised "Last updated" date. Continued use of the app after changes constitutes acceptance of the updated policy.
        """),
        Section(title: "12. Contact Us", body: """
        If you have questions about this Privacy Policy or Rush Hour's data practices, contact:

        Rush Hour
        Email: rushhourada@gmail.com
        Website: https://rush-hour-rho.vercel.app
        """)
    ]
}

#Preview {
    NavigationStack {
        PrivacyPolicyScreen()
    }
}
