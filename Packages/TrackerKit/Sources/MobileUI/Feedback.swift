#if os(iOS) && FEEDBACK
import FeedbackKit
import SwiftUI

/// In-app feedback, in Debug builds only (the package's `FEEDBACK` condition): a shake, a
/// screenshot, Help › Send Feedback… on an iPad with a keyboard, and Settings › Feedback. The
/// report goes to the owner's private inbox, j23n/feedback, where it's triaged before an issue
/// is filed here (README.md, "Feedback").
@MainActor
enum Feedback {
    static let center = FeedbackCenter(configuration: FeedbackConfiguration(
        inbox: GitHubRepository(owner: "j23n", name: "feedback"),
        app: "makeitrain"
    ))
}
#endif
