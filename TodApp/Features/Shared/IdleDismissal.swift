import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The big player closes by itself when nobody touches it for a while (the
/// redesign brief, "Vier weitere Punkte", 26. September): the song goes on in
/// the mini player, and the screen underneath comes back.
enum IdleDismissal {
    /// Seconds without a touch. The brief names 10 to 30 and suggests 15 to 20.
    static let after: TimeInterval = 20

    /// `isHeld` while someone is in the middle of something the sheet must not
    /// swallow: the keyboard up, a comment half written.
    static func isDue(lastActivity: Date, now: Date, isHeld: Bool) -> Bool {
        !isHeld && now.timeIntervalSince(lastActivity) >= after
    }
}

extension View {
    /// Closes the sheet this view sits in after `IdleDismissal.after` seconds
    /// without a touch. Any touch counts -- a tap, a scroll, a scrub along the
    /// waveform -- and none of them is taken from what it lands on.
    ///
    /// `held` keeps it open, for as long as it is true. With VoiceOver on it
    /// never closes: a screen that goes away on a timer is one a VoiceOver
    /// user may not have finished hearing.
    func closesWhenIdle(held: Bool = false) -> some View {
        modifier(IdleDismiss(isHeld: held))
    }
}

private struct IdleDismiss: ViewModifier {
    let isHeld: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverOn
    /// A plain box, not state: a finger moving across the waveform writes to
    /// it many times a second, and that must not redraw the sheet.
    @State private var activity = Activity()

    func body(content: Content) -> some View {
        content
            .background {
                TouchWatcher { [activity] in activity.touched() }
                    .accessibilityHidden(true)
            }
            .onChange(of: isHeld, initial: true) { _, held in
                activity.isHeld = held
                activity.touched()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                activity.isKeyboardUp = true
                activity.touched()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                activity.isKeyboardUp = false
                activity.touched()
            }
            .task(id: isVoiceOverOn) {
                guard !isVoiceOverOn else { return }
                activity.touched()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    if IdleDismissal.isDue(
                        lastActivity: activity.last, now: Date(),
                        isHeld: activity.isHeld || activity.isKeyboardUp
                    ) {
                        // The sheet's own slide down is the animation.
                        dismiss()
                        return
                    }
                }
            }
    }
}

@MainActor
private final class Activity {
    var last = Date()
    var isHeld = false
    var isKeyboardUp = false

    func touched() { last = Date() }
}

/// Hears every touch in the window without taking part: its recognizer never
/// recognizes, cancels nothing and delays nothing, so buttons, scrolling and
/// the waveform's drag work as before.
private struct TouchWatcher: UIViewRepresentable {
    let onTouch: @MainActor () -> Void

    func makeUIView(context: Context) -> WatchingView {
        let view = WatchingView()
        view.isUserInteractionEnabled = false
        view.recognizer.onTouch = onTouch
        return view
    }

    func updateUIView(_ view: WatchingView, context: Context) {
        view.recognizer.onTouch = onTouch
    }

    static func dismantleUIView(_ view: WatchingView, coordinator: ()) {
        view.recognizer.view?.removeGestureRecognizer(view.recognizer)
    }
}

/// Puts the recognizer on the window it lands in: a sheet has no single view
/// that every touch in it passes through, the window does.
private final class WatchingView: UIView {
    let recognizer = PassiveTouchRecognizer.make()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        recognizer.view?.removeGestureRecognizer(recognizer)
        window?.addGestureRecognizer(recognizer)
    }
}

private final class PassiveTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onTouch: (@MainActor () -> Void)?

    static func make() -> PassiveTouchRecognizer {
        let recognizer = PassiveTouchRecognizer(target: nil, action: nil)
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = recognizer
        return recognizer
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onTouch?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        onTouch?()
    }

    // Failing at the end resets it for the next touch; it never recognizes.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .failed
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
