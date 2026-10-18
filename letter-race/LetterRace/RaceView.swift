import SwiftUI

struct RaceView: View {
    @State private var model: RaceModel
    @State private var motionStart: Date?
    @State private var almostToken = 0

    private static let motionDuration = 1.7

    init(glyph: Glyph) {
        _model = State(initialValue: RaceModel(glyph: glyph))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: motionStart == nil)) { timeline in
            let motion = motionProgress(at: timeline.date)
            VStack(spacing: 0) {
                StarMeter(
                    filled: starCount,
                    emphasized: model.phase == .almost || model.phase == .success,
                    tint: model.phase == .almost ? TrackPalette.active : TrackPalette.gold
                )
                .padding(.top, 10)
                .padding(.bottom, 4)

                TrackView(
                    model: model,
                    motion: motion,
                    onBegin: { model.press(at: $0) },
                    onMove: { model.move(to: $0) },
                    onEnd: { model.release(at: $0) },
                    onCancel: { model.cancel() }
                )

                if model.phase == .success {
                    Button {
                        model.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(TrackPalette.ink)
                            .frame(width: 64, height: 64)
                            .background(TrackPalette.success, in: Circle())
                    }
                    .padding(.bottom, 16)
                    .accessibilityLabel("Race again")
                } else {
                    Color.clear.frame(height: 24)
                }
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
            if phase == .almost {
                almostToken += 1
                let token = almostToken
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    guard token == almostToken, model.phase == .almost else { return }
                    model.dismissAlmost()
                }
            }
        }
        .onChange(of: model.replayIndex) { _, _ in
            if model.phase == .replaying {
                motionStart = .now
            }
        }
    }

    private var starCount: Int {
        switch model.phase {
        case .almost, .driving:
            return model.shownStars
        default:
            return model.earnedStars.min() ?? 0
        }
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

private struct StarMeter: View {
    var filled: Int
    var emphasized: Bool
    var tint: Color
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < filled ? "star.fill" : "star")
                    .font(.system(size: emphasized ? 36 : 26, weight: .bold))
                    .foregroundStyle(index < filled ? tint : TrackPalette.waiting.opacity(0.35))
                    .scaleEffect(emphasized && index < filled && pulse ? 1.16 : 1)
            }
        }
        .frame(height: 44)
        .onAppear { pulse = true }
        .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: pulse)
        .accessibilityLabel("\(filled) of 3")
    }
}
