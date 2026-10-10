#if os(iOS) && FEEDBACK
import FeedbackKit
import SwiftUI

/// In-app feedback, in Debug builds only (the package's `FEEDBACK` condition): a shake, a
/// screenshot, Help › Send Feedback… on an iPad with a keyboard, and Settings › Feedback. The
/// report goes to the owner's private inbox, j23n/feedback, where it's triaged before an issue
/// is filed here (README.md, "Feedback").
///
/// The screenshot carries nothing of the person's: with FeedbackKit's `.allContent` redaction,
/// SwiftUI draws placeholders for every text and image for the capture (`feedbackRedaction` on
/// each window's root view), and the titles and text fields UIKit draws are painted over, so
/// projects, clients, notes, times and amounts are all hidden; the layout stays.
@MainActor
enum Feedback {
    static let center = FeedbackCenter(configuration: FeedbackConfiguration(
        inbox: GitHubRepository(owner: "j23n", name: "feedback"),
        app: "makeitrain",
        redaction: .allContent
    ))
}
#endif
