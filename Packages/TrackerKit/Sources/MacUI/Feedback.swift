#if os(macOS) && FEEDBACK
import FeedbackKit
import SwiftUI

/// In-app feedback, in Debug builds only (the package's `FEEDBACK` condition): Help › Send
/// Feedback… in the main window, Feedback… in the menu bar popover, and Settings › Feedback.
/// The report goes to the owner's private inbox, j23n/feedback, where it's triaged before an
/// issue is filed here (README.md, "Feedback").
@MainActor
enum Feedback {
    static let center = FeedbackCenter(configuration: FeedbackConfiguration(
        inbox: GitHubRepository(owner: "j23n", name: "feedback"),
        app: "makeitrain"
    ))
}
#endif
