import SwiftUI

struct RaceView: View {
    @EnvironmentObject private var progress: ProgressStore
    @State private var model: RaceModel
    @State private var motionStart: Date?
    @State private var ride: CarSimulation?
    @State private var arrivalBegan: Date?
    @State private var almostToken = 0

    init(glyph: Glyph) {
        _model = State(initialValue: RaceModel(glyph: glyph))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: motionStart == nil && arrivalBegan == nil)) { timeline in
            let elapsed = elapsedTime(at: timeline.date)
            let motion = inkMotion(elapsed: elapsed)
            let arrival = arrivalProgress(at: timeline.date)
            ZStack {
                TrackView(
                    model: model,
                    motion: motion,
                    ride: ride,
                    driveTime: elapsed,
                    arrival: arrival,
                    onBegin: { model.press(at: $0, time: $1) },
                    onMove: { model.move(to: $0, time: $1) },
                    onEnd: { model.release(at: $0, time: $1) },
                    onCancel: { model.cancel() }
                )

                VStack(spacing: 2) {
                    StarMeter(
                        filled: starCount,
                        tint: model.phase == .almost ? TrackPalette.active : TrackPalette.gold
                    )
                    .frame(height: 36)
                    PassDots(filled: progress.progress.count(for: model.glyph.id))
                        .frame(height: 12)
                    Spacer()
                    ZStack {
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
                            .transition(.opacity.combined(with: .scale(scale: 0.86)))
                            .accessibilityLabel("Race again")
                        }
                    }
                    .frame(height: 72)
                    .animation(.easeInOut(duration: 0.35), value: model.phase == .success)
                }
                .padding(.top, 4)
                .allowsHitTesting(model.phase == .success)
            }
            .onChange(of: timeline.date) { _, date in
                completeArrivalIfNeeded(date)
                completeMotionIfNeeded(elapsedTime(at: date))
            }
        }
        .background((model.glyph.id == "A" || model.glyph.id == "a" ? TrackPalette.grass : TrackPalette.paper).ignoresSafeArea())
        .navigationTitle(model.glyph.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.activeStrokeIndex) { _, index in
            beginArrival(for: index)
        }
        .onChange(of: model.phase) { _, phase in
            rebuildRide()
            if phase != .awaiting {
                arrivalBegan = nil
            }
            if phase == .driving || phase == .replaying {
                motionStart = .now
            }
            if phase == .success {
                progress.recordPass(for: model.glyph.id)
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
            rebuildRide()
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

    private var usesRacingDrive: Bool {
        model.glyph.id == "A" || model.glyph.id == "a"
    }

    /// The next car rolls onto its start. The first car is already waiting.
    private func beginArrival(for index: Int) {
        guard usesRacingDrive, model.phase == .awaiting, index > 0 else {
            arrivalBegan = nil
            return
        }
        arrivalBegan = .now
    }

    private func arrivalProgress(at date: Date) -> Double {
        guard usesRacingDrive, model.phase == .awaiting, model.activeStrokeIndex > 0, let arrivalBegan else { return 1 }
        return min(1, max(0, date.timeIntervalSince(arrivalBegan) / 0.42))
    }

    private func completeArrivalIfNeeded(_ date: Date) {
        guard let arrivalBegan, date.timeIntervalSince(arrivalBegan) >= 0.42 else { return }
        self.arrivalBegan = nil
    }

    private func elapsedTime(at date: Date) -> Double {
        guard let motionStart else { return 0 }
        return date.timeIntervalSince(motionStart)
    }

    /// Other letters still replay at the speed the finger drew. A and a follow the car,
    /// because that car brakes and drifts on its own clock.
    private func inkMotion(elapsed: Double) -> Double {
        if usesRacingDrive, let ride {
            return min(1, max(0, ride.sample(at: elapsed).progress))
        }
        let drawn = max(model.playbackDuration, 0.05)
        return min(1, elapsed / drawn)
    }

    private func completeMotionIfNeeded(_ elapsed: Double) {
        guard motionStart != nil else { return }
        let total = usesRacingDrive ? (ride?.duration ?? 0.35) : max(model.playbackDuration, 0.05)
        guard elapsed >= total - 0.02 else { return }
        motionStart = nil
        model.motionFinished()
    }

    private func rebuildRide() {
        guard usesRacingDrive, model.phase == .driving || model.phase == .replaying else {
            ride = nil
            return
        }
        let index = model.phase == .replaying ? model.replayIndex : model.activeStrokeIndex
        guard model.recordedPaths.indices.contains(index) else {
            ride = nil
            return
        }
        ride = CarSimulation.run(path: model.recordedPaths[index])
    }
}

private struct StarMeter: View {
    var filled: Int
    var tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < filled ? "star.fill" : "star")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(index < filled ? tint : TrackPalette.waiting.opacity(0.35))
                    .opacity(index < filled ? 1 : 0.45)
                    .scaleEffect(index < filled ? 1 : 0.92)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.easeInOut(duration: 0.35), value: index < filled)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: tint)
        .accessibilityLabel("\(filled) of 3")
    }
}
