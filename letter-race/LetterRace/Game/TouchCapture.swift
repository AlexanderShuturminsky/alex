import SwiftUI
import UIKit

struct TouchCapture: UIViewRepresentable {
    var enabled: Bool
    var onBegin: (CGPoint) -> Void
    var onMove: (CGPoint) -> Void
    var onEnd: (CGPoint) -> Void
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
    }

    final class TouchView: UIView {
        var enabled = true
        var onBegin: (CGPoint) -> Void = { _ in }
        var onMove: (CGPoint) -> Void = { _ in }
        var onEnd: (CGPoint) -> Void = { _ in }
        var onCancel: () -> Void = {}

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard enabled, let touch = touches.first else { return }
            onBegin(touch.location(in: self))
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard enabled, let touch = touches.first else { return }
            let samples = event?.coalescedTouches(for: touch) ?? [touch]
            for sample in samples {
                onMove(sample.location(in: self))
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard enabled, let touch = touches.first else { return }
            onEnd(touch.location(in: self))
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            onCancel()
        }
    }
}
