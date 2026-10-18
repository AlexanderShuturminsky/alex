import Foundation

enum RacePhase: Equatable {
    case awaiting
    case tracing
    case driving
    case replaying
    case failed
    case almost
    case success
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
    var earnedStars: [Int] = []
    var shownStars = 0

    /// A fourth wall hit fails the attempt. Three are still allowed.
    static let maxWallHits = 3
    static let carReach = 12.0
    static let reverseSlack = 0.18
    static let minimumTravel = 0.62
    static let finishProgress = 0.8
    /// How far the finger must travel before a backward start counts.
    static let directionSample = 6.0
    /// Opening the stroke this far against its heading ends the attempt.
    static let openingProgress = 0.22

    var track: LetterTrack? { glyph.track }

    var activeStroke: LetterStroke? {
        guard let strokes = track?.strokes, strokes.indices.contains(activeStrokeIndex) else { return nil }
        return strokes[activeStrokeIndex]
    }

    var showsPointer: Bool {
        switch phase {
        case .awaiting, .failed, .almost:
            return true
        default:
            return false
        }
    }

    var isAcceptingTouch: Bool {
        phase == .awaiting || phase == .tracing || phase == .failed
    }

    mutating func press(at point: LetterPoint) {
        if phase == .failed || phase == .almost {
            clearAttempt()
            shownStars = 0
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
        if openedBackward(point, on: stroke) {
            currentTrace = []
            shownStars = 0
            phase = .failed
            return
        }
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
            let accuracy = StrokeAccuracy.measure(
                path: currentTrace,
                centerline: stroke.centerline,
                halfWidth: track.roadHalfWidth,
                wallHits: wallHits
            )
            shownStars = accuracy.stars
            if accuracy.isGoodEnough {
                recordedPaths.append(currentTrace)
                earnedStars.append(accuracy.stars)
                clearAttempt()
                phase = .driving
            } else {
                phase = .almost
            }
        } else {
            clearAttempt()
            shownStars = 0
            phase = .awaiting
        }
    }

    mutating func dismissAlmost() {
        guard phase == .almost else { return }
        clearAttempt()
        shownStars = 0
        phase = .awaiting
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
        earnedStars = []
        shownStars = 0
        clearAttempt()
    }

    private func openedBackward(_ point: LetterPoint, on stroke: LetterStroke) -> Bool {
        guard maxProgress < Self.openingProgress, let heading = RoadGeometry.heading(of: stroke.centerline) else {
            return false
        }
        let dx = point.x - stroke.start.x
        let dy = point.y - stroke.start.y
        let travel = (dx * dx + dy * dy).squareRoot()
        guard travel >= Self.directionSample else { return false }
        let dot = (dx * heading.x + dy * heading.y) / travel
        return dot < 0
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
