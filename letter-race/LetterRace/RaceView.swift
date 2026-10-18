import SwiftUI

struct RaceView: View {
    @State private var model: RaceModel
    @State private var motionStart: Date?

    private static let motionDuration = 1.7

    init(glyph: Glyph) {
        _model = State(initialValue: RaceModel(glyph: glyph))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: motionStart == nil)) { timeline in
            let motion = motionProgress(at: timeline.date)
            VStack(spacing: 0) {
                status
                TrackView(
                    model: model,
                    motion: motion,
                    onBegin: { model.press(at: $0) },
                    onMove: { model.move(to: $0) },
                    onEnd: { model.release(at: $0) },
                    onCancel: { model.cancel() }
                )
                footer
            }
            .onChange(of: motion) { _, newValue in
                completeMotionIfNeeded(newValue)
            }
        }
        .background(TrackPalette.paper.ignoresSafeArea())
        .navigationTitle(model.glyph.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.phase) { _, phase in
            if phase == .driving || phase == .replaying {
                motionStart = .now
            }
        }
        .onChange(of: model.replayIndex) { _, _ in
            if model.phase == .replaying {
                motionStart = .now
            }
        }
    }

    private var status: some View {
        HStack {
            Text(RaceCopy.progress(car: displayedCar, total: strokeCount))
            Spacer()
            if model.phase != .replaying && model.phase != .success {
                Text(RaceCopy.walls(hits: min(model.wallHits, RaceModel.maxWallHits), limit: RaceModel.maxWallHits))
            }
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(TrackPalette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .failed:
            messageCard(RaceCopy.failed, tint: TrackPalette.fail) {
                Button("Try again") { model.tryAgain() }
                    .buttonStyle(RaceButtonStyle())
            }
        case .success:
            messageCard(RaceCopy.success(model.glyph.symbol), tint: TrackPalette.success) {
                Button("Race again") { model.reset() }
                    .buttonStyle(RaceButtonStyle())
            }
        case .replaying:
            footerText(RaceCopy.replay(model.glyph.symbol))
        case .driving:
            footerText(RaceCopy.driving)
        case .tracing:
            footerText(RaceCopy.tracing)
        case .awaiting:
            footerText(RaceCopy.hint(car: model.activeStroke?.id ?? 1))
        }
    }

    private func messageCard<Actions: View>(_ text: String, tint: Color, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 12) {
            Text(text)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(TrackPalette.ink)
                .multilineTextAlignment(.center)
            actions()
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(tint)
    }

    private func footerText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(TrackPalette.waiting)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.horizontal, 20)
    }

    private var strokeCount: Int { model.track?.strokes.count ?? 0 }

    private var displayedCar: Int {
        if model.phase == .replaying {
            return model.track?.strokes[safe: model.replayIndex]?.id ?? 1
        }
        return model.activeStroke?.id ?? 1
    }

    private func motionProgress(at date: Date) -> Double {
        guard let motionStart else { return 0 }
        return min(1, date.timeIntervalSince(motionStart) / Self.motionDuration)
    }

    private func completeMotionIfNeeded(_ motion: Double) {
        guard motion >= 1, motionStart != nil else { return }
        motionStart = nil
        model.motionFinished()
    }
}

private struct RaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(TrackPalette.ink, in: Capsule())
            .foregroundStyle(TrackPalette.paper)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
