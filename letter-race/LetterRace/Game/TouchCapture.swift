import SwiftUI
import UIKit

struct TouchCapture: UIViewRepresentable {
    var enabled: Bool
    var onBegin: (CGPoint, TimeInterval) -> Void
    var onMove: (CGPoint, TimeInterval) -> Void
    var onEnd: (CGPoint, TimeInterval) -> Void
    var onCancel: () -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        return view
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.enabled = enabled
        uiView.onBegin = onBegin
        uiView.onMove = onMove
        uiView.onEnd = onEnd
        uiView.onCancel = onCancel
        uiView.lockPopGesture()
    }

    static func dismantleUIView(_ uiView: TouchView, coordinator: ()) {
        uiView.unlockPopGesture()
    }

    final class TouchView: UIView {
        var enabled = true
        var onBegin: (CGPoint, TimeInterval) -> Void = { _, _ in }
        var onMove: (CGPoint, TimeInterval) -> Void = { _, _ in }
        var onEnd: (CGPoint, TimeInterval) -> Void = { _, _ in }
        var onCancel: () -> Void = {}

        private let popBlocker = PopBlocker()
        private var lockedPopGestures: [LockedPopGesture] = []

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                unlockPopGesture()
            } else {
                lockPopGesture()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if window != nil {
                lockPopGesture()
            }
        }

        /// The race is a drawing surface. iOS 26 pops a screen from a horizontal
        /// drag anywhere in the content, which steals the left-to-right crossbar.
        func lockPopGesture() {
            guard let navigation = enclosingNavigationController() else { return }
            let known = Set(lockedPopGestures.map { ObjectIdentifier($0.gesture) })
            for gesture in popGestures(in: navigation) where !known.contains(ObjectIdentifier(gesture)) {
                lockedPopGestures.append(LockedPopGesture(gesture: gesture, delegate: gesture.delegate))
                gesture.delegate = popBlocker
            }
            for entry in lockedPopGestures {
                entry.gesture.isEnabled = false
            }
        }

        func unlockPopGesture() {
            for entry in lockedPopGestures {
                entry.gesture.delegate = entry.delegate
                entry.gesture.isEnabled = true
            }
            lockedPopGestures.removeAll()
        }

        private func enclosingNavigationController() -> UINavigationController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController {
                    return controller.navigationController
                }
                responder = current.next
            }
            return nil
        }

        /// Both the edge swipe and, on iOS 26, the content-area swipe.
        /// Looked up by name so this still compiles against an older SDK.
        private func popGestures(in navigation: UINavigationController) -> [UIGestureRecognizer] {
            let names = ["interactivePopGestureRecognizer", "interactiveContentPopGestureRecognizer"]
            var found: [UIGestureRecognizer] = []
            for name in names {
                let selector = NSSelectorFromString(name)
                guard navigation.responds(to: selector),
                      let gesture = navigation.perform(selector)?.takeUnretainedValue() as? UIGestureRecognizer
                else { continue }
                found.append(gesture)
            }
            var seen = Set<ObjectIdentifier>()
            return found.filter { seen.insert(ObjectIdentifier($0)).inserted }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard enabled, let touch = touches.first else { return }
            onBegin(touch.location(in: self), touch.timestamp)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard enabled, let touch = touches.first else { return }
            let samples = event?.coalescedTouches(for: touch) ?? [touch]
            for sample in samples {
                onMove(sample.location(in: self), sample.timestamp)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard enabled, let touch = touches.first else { return }
            onEnd(touch.location(in: self), touch.timestamp)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            onCancel()
        }
    }
}

private struct LockedPopGesture {
    let gesture: UIGestureRecognizer
    weak var delegate: UIGestureRecognizerDelegate?
}

private final class PopBlocker: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}
