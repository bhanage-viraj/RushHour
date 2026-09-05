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
                        Text("Last updated: September 5, 2026")
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
        Rush Hour is designed to work on your device. We do not require an account, and we do not operate a backend server that receives your focus-session data, Screen Time selections, camera recordings, or exported wraps. The App does not use advertising or third-party analytics SDKs.
        """),
        Section(title: "2. Information Processed on Your Device", body: """
        To provide its features, Rush Hour processes information locally, including:

        Apps, websites, and categories you choose through Apple's Family Activity Picker

        Focus schedules, session duration, distraction records, titles, descriptions, and activity snapshots you choose to add

        Camera frames recorded after you start a timelapse session, plus the videos and wrap images produced from them

        App preferences and session-recovery information

        Rush Hour does not transmit this information to us. We do not collect your contacts, location, health information, financial information, advertising identifiers, or browsing history.
        """),
        Section(title: "3. Screen Time and Family Controls", body: """
        Rush Hour uses Apple's Family Controls, Managed Settings, Device Activity, and App & Website Usage APIs to let you select distractions, apply shield screens, manage focus breaks, and show restriction status.

        Apple represents your selections using on-device tokens. When Apple grants the required permission and data access is available, Rush Hour may use Apple's on-device app metadata, such as a selected app's localized display name, to label distraction records in the App. Selection tokens, resolved names, schedules, and activity information remain on your device and are not sent to us.
        """),
        Section(title: "4. Camera, Photos, and Sharing", body: """
        Rush Hour accesses the camera only after you grant permission and uses it to record a timelapse during a focus session. The App does not record microphone audio. Camera frames and generated video are processed on your device.

        When you choose Save to Photos, Rush Hour asks iOS for Photos permission and saves the selected video or image to your photo library. When you delete a session whose saved Photos item is linked to that session, the App may ask iOS to delete that specific item. Copies saved in Photos remain there until you or the App delete them.

        When you choose a share destination, iOS or the selected third-party app receives the media you chose to share. Rush Hour does not automatically upload media. The receiving service handles shared media under its own privacy policy.
        """),
        Section(title: "5. Data Stored Locally", body: """
        Rush Hour stores preferences, Family Controls tokens, schedules, session history, distraction records, titles, descriptions, and snapshots in local app or App Group storage. Session source videos and generated wraps are stored in the App's Application Support directory and are marked as excluded from iCloud backup. Other local app data may be included in a device backup according to your iOS backup settings.
        """),
        Section(title: "6. Third-Party Services", body: """
        Rush Hour does not integrate third-party advertising, analytics, crash-reporting, or backend/cloud SDKs. User-initiated sharing is handled by iOS and the destination selected by the user. Those services receive only the content the user chooses to share and are governed by their own privacy policies.

        If this changes in a future update (for example, if analytics or a backend service is added), this Privacy Policy will be updated accordingly before that update is released, and the App Store Privacy Nutrition Label will be revised to match.
        """),
        Section(title: "7. Apple Frameworks", body: """
        Rush Hour relies on Apple frameworks including Family Controls, Managed Settings, Device Activity, App & Website Usage, AVFoundation, Photos, SwiftData, and WidgetKit. Apple's handling of information through its operating system and services is governed by Apple's Privacy Policy.
        """),
        Section(title: "8. Children's Privacy", body: """
        Rush Hour does not knowingly collect personal information from children. The App processes its focus, Screen Time, and recording data on-device rather than transmitting it to us. If a child sends personal information directly to our support email, contact us and we will delete it.
        """),
        Section(title: "9. Data Retention and Deletion", body: """
        We do not retain your app data on a server. You can delete individual sessions inside Rush Hour. Uninstalling the App removes its local container according to standard iOS behavior. Media previously saved to Photos or sent through another app is outside Rush Hour's container and is not removed merely by uninstalling Rush Hour.
        """),
        Section(title: "10. Your Rights", body: """
        Rush Hour does not maintain a server-side account or database containing your app data. You control the information stored in the App and can remove it by deleting sessions or uninstalling the App. For privacy questions or information sent directly to our support email, contact rushhourada@gmail.com.
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
