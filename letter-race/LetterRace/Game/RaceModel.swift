import Foundation

enum RacePhase: Equatable {
    case awaiting
    case tracing
    case driving
    case replaying
    case failed
    case success
}

enum RaceCopy {
    static let failed = "The car hit the wall too many times. Try this part again."
    static let driving = "There it goes."
    static let tracing = "Stay between the walls."

    static func replay(_ symbol: String) -> String {
        "Watch how \(symbol) is written."
    }

    static func success(_ symbol: String) -> String {
        "Nice writing. You wrote \(symbol)."
    }

    static func hint(car: Int) -> String {
        "Hold car \(car) and trace the road to the finish."
    }

    static func progress(car: Int, total: Int) -> String {
        "Car \(car) of \(total)"
    }

    static func walls(hits: Int, limit: Int) -> String {
        "Walls \(hits)/\(limit)"
    }
}

struct RaceModel: Equatable {
    var glyph: Glyph
    var phase: RacePhase = .awaiting
    var activeStrokeIndex = 0
    var wallHits = 0
    var currentTrace: [LetterPoint] = []
    var recordedPaths: [[LetterPoint]] = []
    var maxProgress = 0.0
    var onRoad = false
    var reversalArmed = false
    var replayIndex = 0

    /// A fourth wall hit fails the attempt. Three are still allowed.
    static let maxWallHits = 3
    static let carReach = 12.0
    static let reverseSlack = 0.18
    static let minimumTravel = 0.62
    static let finishProgress = 0.8

    var track: LetterTrack? { glyph.track }

    var activeStroke: LetterStroke? {
        guard let strokes = track?.strokes, strokes.indices.contains(activeStrokeIndex) else { return nil }
        return strokes[activeStrokeIndex]
    }

    var isAcceptingTouch: Bool {
        phase == .awaiting || phase == .tracing || phase == .failed
    }

    mutating func press(at point: LetterPoint) {
        if phase == .failed {
            clearAttempt()
            phase = .awaiting
        }
        guard phase == .awaiting, let stroke = activeStroke, let track else { return }
        guard point.distance(to: stroke.start) <= Self.carReach else { return }

        let projection = RoadGeometry.project(point, onto: stroke.centerline)
        phase = .tracing
        wallHits = 0
        currentTrace = [point]
        onRoad = projection.distance <= track.roadHalfWidth
        maxProgress = onRoad ? projection.progress : 0
        reversalArmed = true
    }

    mutating func move(to point: LetterPoint) {
        guard phase == .tracing, let stroke = activeStroke, let track else { return }
        currentTrace.append(point)
        let projection = RoadGeometry.project(point, onto: stroke.centerline)
        let inside = projection.distance <= track.roadHalfWidth

        if inside {
            if projection.progress + Self.reverseSlack < maxProgress, reversalArmed {
                reversalArmed = false
                registerHit()
                if phase != .tracing { return }
            }
            if projection.progress >= maxProgress {
                maxProgress = projection.progress
                reversalArmed = true
            }
            onRoad = true
        } else if onRoad {
            onRoad = false
            registerHit()
        }
    }

    mutating func release(at point: LetterPoint) {
        guard phase == .tracing, let stroke = activeStroke, let track else { return }
        let inGate = point.distance(to: stroke.gate.center) <= stroke.gate.radius
        if inGate {
            currentTrace.append(point)
        } else {
            move(to: point)
        }
        guard phase == .tracing else { return }

        let projection = RoadGeometry.project(point, onto: stroke.centerline)
        let onRoadNow = projection.distance <= track.roadHalfWidth
        let traveled = maxProgress >= Self.minimumTravel
        let finished = traveled && (inGate || (onRoadNow && maxProgress >= Self.finishProgress))
        if finished {
            recordedPaths.append(currentTrace)
            clearAttempt()
            phase = .driving
        } else {
            clearAttempt()
            phase = .awaiting
        }
    }

    mutating func cancel() {
        guard phase == .tracing else { return }
        clearAttempt()
        phase = .awaiting
    }

    mutating func tryAgain() {
        guard phase == .failed else { return }
        clearAttempt()
        phase = .awaiting
    }

    mutating func motionFinished() {
        guard let count = track?.strokes.count else { return }
        switch phase {
        case .driving:
            if activeStrokeIndex + 1 < count {
                activeStrokeIndex += 1
                clearAttempt()
                phase = .awaiting
            } else {
                replayIndex = 0
                phase = .replaying
            }
        case .replaying:
            if replayIndex + 1 < count {
                replayIndex += 1
            } else {
                phase = .success
            }
        default:
            break
        }
    }

    mutating func reset() {
        phase = .awaiting
        activeStrokeIndex = 0
        recordedPaths = []
        replayIndex = 0
        clearAttempt()
    }

    private mutating func registerHit() {
        wallHits += 1
        if wallHits > Self.maxWallHits {
            currentTrace = []
            phase = .failed
        }
    }

    private mutating func clearAttempt() {
        currentTrace = []
        wallHits = 0
        maxProgress = 0
        onRoad = false
        reversalArmed = false
    }
}
