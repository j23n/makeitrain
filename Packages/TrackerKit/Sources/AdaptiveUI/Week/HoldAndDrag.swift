#if os(iOS)
import SwiftUI
import UIKit

/// Empty space on a touch screen's hour grid, where touching and holding,
/// then dragging, draws a new entry. It says where the finger touched down
/// and where it is now, in its own points, from the hold until the finger
/// lifts. A swipe still scrolls: the hold has to come first.
public struct HoldAndDrag: UIViewRepresentable {
    /// How long a touch is held before drawing starts.
    public static let holdDuration: TimeInterval = 0.35

    let onChange: (_ start: CGPoint, _ location: CGPoint) -> Void
    let onEnd: () -> Void

    public init(onChange: @escaping (_ start: CGPoint, _ location: CGPoint) -> Void, onEnd: @escaping () -> Void) {
        self.onChange = onChange
        self.onEnd = onEnd
    }

    public func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        press.minimumPressDuration = Self.holdDuration
        view.addGestureRecognizer(press)
        return view
    }

    public func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    public final class Coordinator: NSObject {
        var parent: HoldAndDrag
        private var start = CGPoint.zero
        private let feedback = UIImpactFeedbackGenerator(style: .medium)

        init(parent: HoldAndDrag) {
            self.parent = parent
        }

        @objc func pressed(_ press: UILongPressGestureRecognizer) {
            let location = press.location(in: press.view)
            switch press.state {
            case .began:
                start = location
                feedback.impactOccurred()
                parent.onChange(start, location)
            case .changed:
                parent.onChange(start, location)
            case .ended, .cancelled, .failed:
                parent.onEnd()
            default:
                break
            }
        }
    }
}
#endif
