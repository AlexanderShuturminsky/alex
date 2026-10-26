import SwiftUI

struct RaceView: View {
    @EnvironmentObject private var progress: ProgressStore
    @State private var model: RaceModel
    @State private var motionStart: Date?
    @State private var ride: CarSimulation?
    @State private var arrivalBegan: Date?
    @State private var almostToken = 0
    @State private var recordedPass = false

    init(glyph: Glyph) {
        _model = State(initialValue: RaceModel(glyph: glyph))
    }

    var body: some View {
        let shouldAnimateChevrons = model.phase == .awaiting || model.phase == .tracing
        let isTimelinePaused = motionStart == nil && arrivalBegan == nil && !shouldAnimateChevrons
        let interval = (motionStart != nil || arrivalBegan != nil)
            ? (1.0 / 60.0)
            : (1.0 / 24.0)
        TimelineView(.animation(minimumInterval: interval, paused: isTimelinePaused)) { timeline in
            let elapsed = elapsedTime(at: timeline.date)
            let motion = inkMotion(elapsed: elapsed)
            let arrival = arrivalProgress(at: timeline.date)
            let chevronTime = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                TrackView(
                    model: model,
                    motion: motion,
                    ride: ride,
                    driveTime: elapsed,
                    arrival: arrival,
                    chevronTime: chevronTime,
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
                            HStack(spacing: 18) {
                                Button {
                                    model.replay()
                                } label: {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(TrackPalette.ink)
                                        .frame(width: 64, height: 64)
                                        .background(TrackPalette.gold, in: Circle())
                                }
                                .accessibilityLabel("Replay")

                                Button {
                                    recordedPass = false
                                    model.reset()
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(TrackPalette.ink)
                                        .frame(width: 64, height: 64)
                                        .background(TrackPalette.success, in: Circle())
                                }
                                .accessibilityLabel("Race again")
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.86)))
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
        .background((usesRacingDrive ? TrackPalette.grass : TrackPalette.paper).ignoresSafeArea())
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
            if phase == .success, !recordedPass {
                recordedPass = true
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
        case .awaiting, .tracing:
            return model.earnedStars.min() ?? model.shownStars
        default:
            return model.earnedStars.min() ?? 0
        }
    }

    private var usesRacingDrive: Bool {
        model.glyph.isPlayable
    }

    /// Zero pause between strokes: the next car is immediately parked and ready at its start.
    private func beginArrival(for index: Int) {
        arrivalBegan = nil
    }

    private func arrivalProgress(at date: Date) -> Double {
        1
    }

    private func completeArrivalIfNeeded(_ date: Date) {
        arrivalBegan = nil
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
        let liveStart = model.phase == .driving ? model.completedLiveCar : nil
        ride = CarSimulation.run(path: model.recordedPaths[index], startingFrom: liveStart)
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
