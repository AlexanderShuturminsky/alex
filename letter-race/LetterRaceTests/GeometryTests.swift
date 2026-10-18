import XCTest
#if canImport(LetterRaceCore)
@testable import LetterRaceCore
#else
@testable import LetterRace
#endif

final class GeometryTests: XCTestCase {
    func testProjectionOntoSegment() {
        let line = [LetterPoint(x: 0, y: 0), LetterPoint(x: 10, y: 0)]
        let beside = RoadGeometry.project(LetterPoint(x: 5, y: 4), onto: line)
        XCTAssertEqual(beside.distance, 4, accuracy: 0.001)
        XCTAssertEqual(beside.progress, 0.5, accuracy: 0.001)

        let pastEnd = RoadGeometry.project(LetterPoint(x: 14, y: 0), onto: line)
        XCTAssertEqual(pastEnd.progress, 1, accuracy: 0.001)
        XCTAssertEqual(pastEnd.closest.x, 10, accuracy: 0.001)
    }

    func testPointAndPrefixAlongPolyline() {
        let line = [LetterPoint(x: 0, y: 0), LetterPoint(x: 10, y: 0)]
        let mid = RoadGeometry.point(at: 0.5, along: line)
        XCTAssertEqual(mid.x, 5, accuracy: 0.001)
        XCTAssertEqual(mid.y, 0, accuracy: 0.001)

        let prefix = RoadGeometry.prefix(line, through: 0.5)
        XCTAssertEqual(prefix.count, 2)
        XCTAssertEqual(prefix[1].x, 5, accuracy: 0.001)
        XCTAssertEqual(RoadGeometry.prefix(line, through: 0).count, 1)
        XCTAssertEqual(RoadGeometry.prefix(line, through: 1).count, 2)
    }

    func testViewportRoundTrip() {
        let viewport = LetterViewport(width: 200, height: 400, inset: 20)
        XCTAssertEqual(viewport.scale, 1.6, accuracy: 0.001)
        let center = LetterPoint(x: 50, y: 50)
        XCTAssertEqual(viewport.viewX(center), 100, accuracy: 0.001)
        XCTAssertEqual(viewport.viewY(center), 200, accuracy: 0.001)
        let back = viewport.letter(x: viewport.viewX(center), y: viewport.viewY(center))
        XCTAssertEqual(back.x, center.x, accuracy: 0.001)
        XCTAssertEqual(back.y, center.y, accuracy: 0.001)

        let tiny = LetterViewport(width: 10, height: 10, inset: 36)
        XCTAssertEqual(tiny.letter(x: 4, y: 4), LetterPoint(x: 0, y: 0))
    }

    func testLetterAHasThreeSchoolStrokes() {
        let track = LetterA.track
        XCTAssertEqual(track.strokes.map(\.id), [1, 2, 3])
        XCTAssertEqual(track.strokes[0].start, LetterA.apex)
        XCTAssertEqual(track.strokes[1].start, LetterA.apex)
        XCTAssertEqual(track.strokes[0].centerline.last, LetterA.leftFoot)
        XCTAssertEqual(track.strokes[1].centerline.last, LetterA.rightFoot)

        let bar = track.strokes[2]
        XCTAssertLessThan(bar.start.x, bar.centerline[1].x)
        XCTAssertEqual(
            RoadGeometry.project(bar.start, onto: track.strokes[0].centerline).distance,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            RoadGeometry.project(bar.centerline[1], onto: track.strokes[1].centerline).distance,
            0,
            accuracy: 0.001
        )
        XCTAssertTrue(RoadGeometry.isOnRoad(LetterA.leftFoot, polyline: track.strokes[0].centerline, halfWidth: track.roadHalfWidth))
        XCTAssertFalse(RoadGeometry.isOnRoad(LetterPoint(x: -10, y: -10), polyline: track.strokes[0].centerline, halfWidth: track.roadHalfWidth))
    }

    func testCatalogOffersEveryLetterAndNumberWithOnlyAPlayable() {
        XCTAssertEqual(GlyphCatalog.letters.map(\.symbol), Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init))
        XCTAssertEqual(GlyphCatalog.numbers.map(\.symbol), (0...9).map(String.init))
        XCTAssertEqual(GlyphCatalog.all.count, 36)
        XCTAssertTrue(GlyphCatalog.letters.allSatisfy { $0.kind == .letter })
        XCTAssertTrue(GlyphCatalog.numbers.allSatisfy { $0.kind == .number })
        XCTAssertEqual(GlyphCatalog.all.filter(\.isPlayable).map(\.id), ["A"])
        XCTAssertTrue(GlyphCatalog.all.allSatisfy { $0.isPlayable == ($0.track != nil) })
        XCTAssertEqual(GlyphCatalog.glyph(id: "A")?.track?.strokes.count, 3)
        XCTAssertNil(GlyphCatalog.glyph(id: "B")?.track)
        XCTAssertNil(GlyphCatalog.glyph(id: "?"))
    }

    func testWallHitIsCountedOnceUntilTheFingerReturns() {
        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        model.move(to: point(0.25, on: stroke))
        model.move(to: offRoad)
        model.move(to: offRoad)
        model.move(to: offRoad)
        XCTAssertEqual(model.wallHits, 1)
        XCTAssertEqual(model.phase, .tracing)

        model.move(to: point(0.45, on: stroke))
        model.move(to: offRoad)
        XCTAssertEqual(model.wallHits, 2)
    }

    func testFourthWallHitFailsAndPressingTheCarTriesAgain() {
        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        for step in 0..<4 {
            model.move(to: point(0.15 + Double(step) * 0.1, on: stroke))
            model.move(to: offRoad)
        }
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.currentTrace.isEmpty)
        XCTAssertEqual(RaceModel.maxWallHits, 3)

        model.press(at: stroke.start)
        XCTAssertEqual(model.phase, .tracing)
        XCTAssertEqual(model.wallHits, 0)
    }

    func testThreeWallHitsIsANiceTry() {
        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        for step in 0..<3 {
            model.move(to: point(0.25 + Double(step) * 0.2, on: stroke))
            model.move(to: offRoad)
            model.move(to: point(0.4 + Double(step) * 0.2, on: stroke))
        }
        XCTAssertEqual(model.wallHits, 3)
        model.release(at: stroke.gate.center)
        XCTAssertEqual(model.phase, .almost)
        XCTAssertEqual(model.shownStars, 1)
        XCTAssertTrue(model.recordedPaths.isEmpty)
        model.dismissAlmost()
        XCTAssertEqual(model.phase, .awaiting)
    }

    func testStartingBackwardEndsTheStroke() {
        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        let heading = RoadGeometry.heading(of: stroke.centerline)!
        model.press(at: stroke.start)

        let nudge = LetterPoint(
            x: stroke.start.x - heading.x * 3,
            y: stroke.start.y - heading.y * 3
        )
        model.move(to: nudge)
        XCTAssertEqual(model.phase, .tracing)

        let backward = LetterPoint(
            x: stroke.start.x - heading.x * 8,
            y: stroke.start.y - heading.y * 8
        )
        model.move(to: backward)
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.currentTrace.isEmpty)
        XCTAssertTrue(model.recordedPaths.isEmpty)
    }

    func testSloppyLineInsideTheRoadIsANiceTry() {
        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        let shifted = offset(stroke, by: 6)
        model.press(at: stroke.start)
        for (index, sample) in shifted.enumerated() {
            if index == shifted.count - 1 {
                model.release(at: sample)
            } else {
                model.move(to: sample)
            }
        }
        XCTAssertEqual(model.phase, .almost)
        XCTAssertEqual(model.shownStars, 1)
        XCTAssertTrue(model.recordedPaths.isEmpty)

        let centered = StrokeAccuracy.measure(
            path: stroke.centerline,
            centerline: stroke.centerline,
            halfWidth: model.track!.roadHalfWidth,
            wallHits: 0
        )
        XCTAssertEqual(centered.stars, 3)
        XCTAssertTrue(centered.isGoodEnough)
    }

    func testReversingOnTheRoadStopsTheStroke() {
        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        model.move(to: point(0.75, on: stroke))
        model.move(to: point(0.2, on: stroke))
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.currentTrace.isEmpty)
        XCTAssertTrue(model.recordedPaths.isEmpty)
    }

    func testReachingTheFinishStopsTheLine() {
        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        model.press(at: stroke.start, time: 5)
        for step in 1...20 {
            let progress = Double(step) / 20
            model.move(to: point(progress, on: stroke), time: 5 + 2 * progress)
        }
        XCTAssertEqual(model.phase, .driving)
        let kept = model.recordedPaths[0].count
        let drawnFor = model.recordedDurations[0]
        XCTAssertEqual(drawnFor, 1.6, accuracy: 0.05)
        XCTAssertEqual(model.playbackDuration, drawnFor, accuracy: 0.001)

        model.move(to: point(0.3, on: stroke), time: 9)
        model.release(at: stroke.start, time: 9.2)
        XCTAssertEqual(model.phase, .driving)
        XCTAssertEqual(model.recordedPaths[0].count, kept)
        XCTAssertEqual(model.recordedDurations, [drawnFor])
    }

    func testGoingBackOnTheCrossbarStopsTheStroke() {
        var model = RaceModel(glyph: playableA)
        trace(&model, along: model.track!.strokes[0])
        model.motionFinished()
        trace(&model, along: model.track!.strokes[1])
        model.motionFinished()

        let bar = model.activeStroke!
        XCTAssertEqual(bar.id, 3)
        model.press(at: bar.start)
        model.move(to: point(0.6, on: bar))
        model.move(to: point(0.25, on: bar))
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.recordedPaths.count == 2)
    }

    func testLeavingEarlyDoesNotLaunchTheCar() {
        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        model.press(at: LetterPoint(x: 0, y: 0))
        XCTAssertEqual(model.phase, .awaiting)

        model.press(at: stroke.start)
        model.move(to: point(0.2, on: stroke))
        model.release(at: point(0.3, on: stroke))
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertTrue(model.recordedPaths.isEmpty)
    }

    func testJumpingToTheFinishDoesNotCount() {
        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        model.release(at: stroke.gate.center)
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertTrue(model.recordedPaths.isEmpty)
    }

    func testSuccessfulLetterReplaysThenCelebrates() {
        var model = RaceModel(glyph: playableA)
        let strokes = model.track!.strokes
        for stroke in strokes {
            trace(&model, along: stroke)
            XCTAssertEqual(model.phase, .driving)
            XCTAssertEqual(model.wallHits, 0)
            model.motionFinished()
        }
        XCTAssertEqual(model.phase, .replaying)
        XCTAssertEqual(model.recordedPaths.count, 3)
        for _ in strokes {
            model.motionFinished()
        }
        XCTAssertEqual(model.phase, .success)
        XCTAssertEqual(model.earnedStars, [3, 3, 3])

        model.reset()
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertEqual(model.activeStrokeIndex, 0)
        XCTAssertTrue(model.recordedPaths.isEmpty)
    }

    func testCancelAndUnreadyGlyphDoNotRecordAPath() {
        var model = RaceModel(glyph: playableA)
        model.press(at: model.activeStroke!.start)
        model.cancel()
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertTrue(model.currentTrace.isEmpty)

        var number = RaceModel(glyph: GlyphCatalog.numbers[4])
        number.press(at: LetterPoint(x: 50, y: 50))
        XCTAssertEqual(number.phase, .awaiting)
        XCTAssertFalse(GlyphCatalog.numbers[4].isPlayable)
    }

    private var playableA: Glyph {
        GlyphCatalog.glyph(id: "A")!
    }

    private var offRoad: LetterPoint { LetterPoint(x: -20, y: -20) }

    private func point(_ progress: Double, on stroke: LetterStroke) -> LetterPoint {
        RoadGeometry.point(at: progress, along: stroke.centerline)
    }

    private func offset(_ stroke: LetterStroke, by amount: Double) -> [LetterPoint] {
        let start = stroke.centerline[0]
        let end = stroke.centerline[1]
        let dx = end.x - start.x
        let dy = end.y - start.y
        let span = (dx * dx + dy * dy).squareRoot()
        let px = -dy / span * amount
        let py = dx / span * amount
        return (1...12).map { step in
            let base = RoadGeometry.point(at: Double(step) / 12, along: stroke.centerline)
            return LetterPoint(x: base.x + px, y: base.y + py)
        }
    }

    private func trace(_ model: inout RaceModel, along stroke: LetterStroke) {
        model.press(at: stroke.start)
        for step in 1...20 {
            let sample = point(Double(step) / 20, on: stroke)
            if step == 20 {
                model.release(at: sample)
            } else {
                model.move(to: sample)
            }
        }
    }
}
