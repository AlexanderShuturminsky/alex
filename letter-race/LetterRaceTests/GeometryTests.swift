import XCTest
#if canImport(LetterRaceCore)
@testable import LetterRaceCore
#else
@testable import LetterRace
#endif

final class GeometryTests: XCTestCase {
    func testFinishZoneMiddleIsBetweenTheHatches() {
        let marks = FinishZone.offsets
        XCTAssertEqual(marks.count, 6)
        XCTAssertLessThan(marks[0], 0)
        XCTAssertGreaterThan(marks[marks.count - 1], 0)
        XCTAssertEqual(FinishZone.middleOffset, (marks[0] + marks[marks.count - 1]) / 2, accuracy: 0.001)
        let stroke = LetterA.track.strokes[0]
        let middle = FinishZone.middle(on: stroke)
        XCTAssertGreaterThan(middle.distance(to: stroke.gate.center), 0)
    }

    func testProjectionOntoSegment() {
        let line = [LetterPoint(x: 0, y: 0), LetterPoint(x: 10, y: 0)]
        let beside = RoadGeometry.project(LetterPoint(x: 5, y: 4), onto: line)
        XCTAssertEqual(beside.distance, 4, accuracy: 0.001)
        XCTAssertEqual(beside.progress, 0.5, accuracy: 0.001)

        let pastEnd = RoadGeometry.project(LetterPoint(x: 14, y: 0), onto: line)
        XCTAssertEqual(pastEnd.progress, 1, accuracy: 0.001)
        XCTAssertEqual(pastEnd.closest.x, 10, accuracy: 0.001)
    }

    func testDirectionMarksPointAlongTheRoad() {
        let line = [LetterPoint(x: 0, y: 0), LetterPoint(x: 80, y: 0)]
        let marks = RoadGeometry.directionMarks(along: line, spacing: 16, leadingInset: 14, trailingInset: 8)
        XCTAssertEqual(marks.count, 4)
        XCTAssertEqual(marks[0].point.x, 14, accuracy: 0.001)
        XCTAssertEqual(marks[0].point.y, 0, accuracy: 0.001)
        XCTAssertEqual(marks[0].heading.x, 1, accuracy: 0.001)
        XCTAssertEqual(marks[0].heading.y, 0, accuracy: 0.001)
        XCTAssertEqual(marks[0].progress, 14.0 / 80.0, accuracy: 0.001)
        XCTAssertEqual(marks[3].point.x, 62, accuracy: 0.001)

        let bend = [
            LetterPoint(x: 0, y: 0),
            LetterPoint(x: 40, y: 0),
            LetterPoint(x: 40, y: 40),
        ]
        let turned = RoadGeometry.directionMarks(along: bend, spacing: 20, leadingInset: 10, trailingInset: 8)
        let before = turned.filter { $0.point.x < 39 }
        let after = turned.filter { $0.point.y > 1 }
        XCTAssertFalse(before.isEmpty)
        XCTAssertFalse(after.isEmpty)
        XCTAssertGreaterThan(before[0].heading.x, 0.9)
        XCTAssertGreaterThan(after[0].heading.y, 0.9)

        let short = RoadGeometry.directionMarks(
            along: [LetterPoint(x: 0, y: 0), LetterPoint(x: 20, y: 0)],
            spacing: 16,
            leadingInset: 14,
            trailingInset: 8
        )
        XCTAssertEqual(short.count, 1)

        for stroke in LetterA.track.strokes + LetterW.track.strokes {
            XCTAssertFalse(RoadGeometry.directionMarks(along: stroke.centerline).isEmpty)
        }
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

        let suffix = RoadGeometry.suffix(line, from: 0.5)
        XCTAssertEqual(suffix.count, 2)
        XCTAssertEqual(suffix[0].x, 5, accuracy: 0.001)
        XCTAssertEqual(RoadGeometry.suffix(line, from: 0).count, 2)
        XCTAssertEqual(RoadGeometry.suffix(line, from: 1).count, 1)
    }

    func testViewportRoundTrip() {
        let viewport = LetterViewport(width: 200, height: 400)
        XCTAssertEqual(viewport.scaleX, viewport.scaleY, accuracy: 0.001)
        XCTAssertEqual(viewport.scale, 1.68, accuracy: 0.001)
        let center = LetterPoint(x: 50, y: 50)
        XCTAssertEqual(viewport.viewX(center), 100, accuracy: 0.001)
        XCTAssertEqual(viewport.viewY(center), 200, accuracy: 0.001)
        let back = viewport.letter(x: viewport.viewX(center), y: viewport.viewY(center))
        XCTAssertEqual(back.x, center.x, accuracy: 0.001)
        XCTAssertEqual(back.y, center.y, accuracy: 0.001)
        let top = LetterPoint(x: 0, y: 0)
        let bottom = LetterPoint(x: 0, y: 100)
        let side = viewport.viewY(bottom) - viewport.viewY(top)
        XCTAssertEqual(viewport.viewX(LetterPoint(x: 100, y: 0)) - viewport.viewX(top), side, accuracy: 0.001)
        XCTAssertEqual(side / viewport.width, 0.84, accuracy: 0.001)

        let tiny = LetterViewport(width: 0, height: 0)
        XCTAssertEqual(tiny.letter(x: 4, y: 4), LetterPoint(x: 0, y: 0))
    }

    func testSmallLettersStayCloseToTheirCapitals() {
        let pairs: [(Glyph, Glyph)] = [
            (GlyphCatalog.glyph(id: "A")!, GlyphCatalog.glyph(id: "a")!),
            (GlyphCatalog.glyph(id: "B")!, GlyphCatalog.glyph(id: "b")!),
            (GlyphCatalog.glyph(id: "Q")!, GlyphCatalog.glyph(id: "q")!),
            (GlyphCatalog.glyph(id: "W")!, GlyphCatalog.glyph(id: "w")!),
        ]
        for (capital, small) in pairs {
            let capitalSpan = Manuscript.span(of: capital.track!.strokes.map(\.centerline))
            let smallSpan = Manuscript.span(of: small.track!.strokes.map(\.centerline))
            XCTAssertGreaterThan(smallSpan, capitalSpan * 0.80)
            XCTAssertLessThan(smallSpan, capitalSpan * 0.90)
        }
        XCTAssertGreaterThan(LetterA.roadHalfWidth, 5)
    }

    func testCircleDoesNotFinishAtItsStart() {
        let circle = LetterQ.track.strokes[0].centerline
        let late = RoadGeometry.point(at: 0.98, along: circle)
        let jumped = RoadGeometry.project(late, onto: circle)
        XCTAssertGreaterThan(jumped.progress, 0.9)
        let held = RoadGeometry.project(late, onto: circle, near: 0)
        XCTAssertLessThan(held.progress, 0.3)

        var model = RaceModel(glyph: GlyphCatalog.glyph(id: "Q")!)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        for step in 1...16 {
            model.move(to: point(Double(step) / 40, on: stroke))
        }
        XCTAssertEqual(model.phase, .tracing)
        XCTAssertLessThan(model.maxProgress, 0.7)
        for step in 17...40 {
            model.move(to: point(Double(step) / 40, on: stroke))
        }
        model.release(at: FinishZone.middle(on: stroke))
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertEqual(model.activeStrokeIndex, 1)
        XCTAssertEqual(model.wallHits, 0)
    }

    func testFoldingBackAlongTheLetterDoesNotStop() {
        var model = RaceModel(glyph: GlyphCatalog.glyph(id: "B")!)
        trace(&model, along: model.track!.strokes[0])
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertEqual(model.activeStrokeIndex, 1)
        trace(&model, along: model.track!.strokes[1])
        XCTAssertEqual(model.phase, .replaying)
        XCTAssertEqual(model.wallHits, 0)
    }

    func testWaistOfBCanTurnTheOppositeWay() {
        var model = RaceModel(glyph: GlyphCatalog.glyph(id: "B")!)
        trace(&model, along: model.track!.strokes[0])
        let bowl = model.activeStroke!
        model.press(at: bowl.start)
        let line = bowl.centerline
        let stride = max(1, line.count / 10)
        var finger: [LetterPoint] = []
        var index = stride
        while index < line.count - 1 {
            let sample = line[index]
            finger.append(LetterPoint(x: sample.x - 4, y: sample.y))
            index += stride
        }
        finger.append(line[line.count - 1])
        for point in finger {
            model.move(to: point)
            XCTAssertEqual(model.phase, .tracing, "stopped at \(point)")
        }
        model.release(at: FinishZone.middle(on: bowl))
        XCTAssertEqual(model.phase, .replaying)
        XCTAssertEqual(model.wallHits, 0)
    }

    func testLetterAFollowsTheChart() {
        let track = LetterA.track
        XCTAssertEqual(track.strokes.map(\.id), [1, 2])
        let peak = track.strokes[0]
        XCTAssertEqual(peak.start, LetterA.leftFoot)
        XCTAssertGreaterThan(peak.centerline.count, 3)
        XCTAssertFalse(peak.centerline.contains(LetterA.apex))
        XCTAssertEqual(peak.centerline.last, LetterA.rightFoot)
        XCTAssertNotEqual(peak.centerline.last, LetterA.apex)

        let bar = track.strokes[1]
        XCTAssertGreaterThan(bar.centerline.count, 10)
        XCTAssertLessThan(bar.start.x, bar.centerline.last!.x)
        XCTAssertEqual(
            RoadGeometry.project(bar.start, onto: peak.centerline).distance,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            RoadGeometry.project(bar.centerline.last!, onto: peak.centerline).distance,
            0,
            accuracy: 0.001
        )
        let crown = RoadGeometry.point(at: 0.5, along: peak.centerline)
        XCTAssertTrue(RoadGeometry.isOnRoad(crown, polyline: peak.centerline, halfWidth: track.roadHalfWidth))
        XCTAssertFalse(RoadGeometry.isOnRoad(LetterPoint(x: -10, y: -10), polyline: peak.centerline, halfWidth: track.roadHalfWidth))
    }

    func testBowlsAreTallOvalsAndCornersAreLightlyRound() {
        for symbol in ["a", "Q", "q"] {
            let bowl = GlyphCatalog.glyph(id: symbol)!.track!.strokes[0].centerline
            let size = bounds(of: bowl)
            XCTAssertGreaterThan(size.height, size.width * 1.2, symbol)
        }

        let bowls = LetterB.track.strokes[1].centerline
        let waist = bowls[bowls.count / 2]
        XCTAssertGreaterThan(sharpestCornerDot(on: bowls, skippingAround: waist), 0.90)
        let rightmost = bowls.max { $0.x < $1.x }!
        let bowlSize = bounds(of: bowls)
        XCTAssertGreaterThan(bowlSize.height, bowlSize.width)
        XCTAssertGreaterThan(rightmost.x - bowls[0].x, LetterB.track.roadHalfWidth * 2 + 8)

        let zigzag = LetterW.track.strokes[0].centerline
        let valley = LetterPoint(x: 30, y: 84)
        XCTAssertFalse(zigzag.contains(valley))
        let rounded = RoadGeometry.project(valley, onto: zigzag).distance
        XCTAssertGreaterThan(rounded, 1.2)
        XCTAssertLessThan(rounded, 8)
        let apexOffset = RoadGeometry.project(LetterA.apex, onto: LetterA.track.strokes[0].centerline).distance
        XCTAssertGreaterThan(apexOffset, 10)
        XCTAssertLessThan(apexOffset, 18)
        XCTAssertGreaterThan(sharpestCornerDot(on: LetterA.track.strokes[0].centerline, skippingAround: LetterPoint(x: -100, y: -100)), 0.98)
        XCTAssertEqual(LetterW.track.strokes.count, 1)
        XCTAssertEqual(LetterA.track.strokes.count, 2)
    }

    func testLetterApexIsOneMove() {
        var model = RaceModel(glyph: playableA)
        let peak = model.track!.strokes[0]
        model.press(at: peak.start)
        for step in 1...40 {
            model.move(to: point(Double(step) / 40, on: peak))
        }
        model.release(at: FinishZone.middle(on: peak))
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertEqual(model.activeStrokeIndex, 1)
        XCTAssertEqual(model.wallHits, 0)
        XCTAssertEqual(model.recordedPaths.count, 1)
    }

    func testChartLettersAndLevelUnlocks() {
        XCTAssertEqual(GlyphCatalog.letters.map(\.symbol), Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init))
        XCTAssertEqual(GlyphCatalog.smallLetters.map(\.symbol), Array("abcdefghijklmnopqrstuvwxyz").map(String.init))
        XCTAssertEqual(GlyphCatalog.numbers.map(\.symbol), (0...9).map(String.init))
        XCTAssertEqual(GlyphCatalog.all.count, 62)
        XCTAssertEqual(GlyphCatalog.playableLevels.map(\.id), ["A", "B", "Q", "W"])
        XCTAssertEqual(GlyphCatalog.glyph(id: "A")?.track?.strokes.count, 2)
        XCTAssertEqual(GlyphCatalog.glyph(id: "a")?.track?.strokes.count, 2)
        XCTAssertEqual(GlyphCatalog.glyph(id: "B")?.track?.strokes.count, 2)
        XCTAssertEqual(GlyphCatalog.glyph(id: "b")?.track?.strokes.count, 2)
        XCTAssertEqual(GlyphCatalog.glyph(id: "Q")?.track?.strokes.count, 2)
        XCTAssertEqual(GlyphCatalog.glyph(id: "q")?.track?.strokes.count, 2)
        XCTAssertEqual(GlyphCatalog.glyph(id: "W")?.track?.strokes.count, 1)
        XCTAssertEqual(GlyphCatalog.glyph(id: "w")?.track?.strokes.count, 1)
        XCTAssertNil(GlyphCatalog.glyph(id: "C")?.track)
        XCTAssertNil(GlyphCatalog.glyph(id: "?"))

        var progress = LevelProgress()
        let playable = GlyphCatalog.playableLevels
        XCTAssertTrue(GlyphCatalog.isUnlocked(playable[0], progress: progress))
        XCTAssertFalse(GlyphCatalog.isUnlocked(playable[1], progress: progress))
        XCTAssertFalse(GlyphCatalog.isUnlocked(GlyphCatalog.levels[2], progress: progress))

        for _ in 0..<6 {
            progress.recordPass("A")
            progress.recordPass("a")
        }
        XCTAssertFalse(GlyphCatalog.isUnlocked(playable[1], progress: progress))
        progress.recordPass("A")
        XCTAssertEqual(progress.count(for: "A"), 7)
        XCTAssertFalse(GlyphCatalog.isUnlocked(playable[1], progress: progress))
        progress.recordPass("a")
        progress.recordPass("A")
        XCTAssertEqual(progress.count(for: "A"), 7)
        XCTAssertTrue(GlyphCatalog.isUnlocked(playable[1], progress: progress))
        XCTAssertFalse(GlyphCatalog.isUnlocked(playable[2], progress: progress))

        for _ in 0..<7 {
            progress.recordPass("B")
            progress.recordPass("b")
        }
        XCTAssertTrue(GlyphCatalog.isUnlocked(playable[2], progress: progress))
        XCTAssertFalse(GlyphCatalog.isUnlocked(playable[3], progress: progress))
    }

    func testWallHitIsCountedOnceUntilTheFingerReturns() {
        var model = RaceModel(glyph: longRoad)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        glide(&model, on: stroke, from: 0.02, to: 0.14, sideFrom: 0, sideTo: 12)
        glide(&model, on: stroke, from: 0.14, to: 0.18, sideFrom: 12, sideTo: 12)
        XCTAssertEqual(model.wallHits, 1)
        XCTAssertEqual(model.phase, .tracing)

        glide(&model, on: stroke, from: 0.18, to: 0.30, sideFrom: 12, sideTo: 0)
        glide(&model, on: stroke, from: 0.30, to: 0.42, sideFrom: 0, sideTo: 12)
        XCTAssertEqual(model.wallHits, 2)
        XCTAssertEqual(model.phase, .tracing)
    }

    func testFourthWallHitFailsAndPressingTheCarTriesAgain() {
        var model = RaceModel(glyph: longRoad)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        var progress = 0.02
        for _ in 0..<4 {
            glide(&model, on: stroke, from: progress, to: progress + 0.12, sideFrom: 0, sideTo: 12)
            progress += 0.12
            glide(&model, on: stroke, from: progress, to: progress + 0.12, sideFrom: 12, sideTo: 0)
            progress += 0.12
        }
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.currentTrace.isEmpty)
        XCTAssertEqual(RaceModel.maxWallHits, 3)

        model.press(at: stroke.start)
        XCTAssertEqual(model.phase, .tracing)
        XCTAssertEqual(model.wallHits, 0)
    }

    func testThreeWallHitsIsANiceTry() {
        var model = RaceModel(glyph: longRoad)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        var progress = 0.02
        for _ in 0..<3 {
            glide(&model, on: stroke, from: progress, to: progress + 0.10, sideFrom: 0, sideTo: 12)
            progress += 0.10
            glide(&model, on: stroke, from: progress, to: progress + 0.10, sideFrom: 12, sideTo: 0)
            progress += 0.10
        }
        XCTAssertEqual(model.wallHits, 3)
        XCTAssertEqual(model.phase, .tracing)
        model.release(at: FinishZone.middle(on: stroke))
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
        var model = RaceModel(glyph: longRoad)
        let stroke = model.activeStroke!
        let shifted = offset(stroke, by: 6)
        model.press(at: stroke.start)
        for sample in shifted {
            model.move(to: sample)
        }
        XCTAssertEqual(model.phase, .tracing)
        model.release(at: FinishZone.middle(on: stroke))
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
        var model = RaceModel(glyph: longRoad)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        model.move(to: point(0.30, on: stroke))
        model.move(to: point(0.288, on: stroke))
        XCTAssertEqual(model.phase, .tracing)

        model.move(to: point(0.05, on: stroke))
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.currentTrace.isEmpty)
        XCTAssertTrue(model.recordedPaths.isEmpty)
    }

    func testReversingOffTheRoadStopsTheStroke() {
        var model = RaceModel(glyph: longRoad)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        glide(&model, on: stroke, from: 0.08, to: 0.22, sideFrom: 0, sideTo: 12)
        XCTAssertEqual(model.phase, .tracing)
        XCTAssertEqual(model.wallHits, 1)

        var progress = 0.22
        while progress > 0.08 {
            progress -= 0.02
            model.move(to: drifted(progress, on: stroke, sideways: 12))
            if model.phase == .failed { break }
        }
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.currentTrace.isEmpty)
        XCTAssertTrue(model.recordedPaths.isEmpty)
    }

    func testZigzagLetterCanBeTracedThroughItsBends() {
        var model = RaceModel(glyph: GlyphCatalog.glyph(id: "W")!)
        let stroke = model.activeStroke!
        model.press(at: stroke.start)
        for step in 1...48 {
            model.move(to: point(Double(step) / 48, on: stroke))
        }
        model.release(at: FinishZone.middle(on: stroke))
        XCTAssertEqual(model.phase, .replaying)
        XCTAssertEqual(model.wallHits, 0)
    }

    func testSharpCornerEndsTheStroke() {
        var model = RaceModel(glyph: longRoad)
        let stroke = model.activeStroke!
        let heading = RoadGeometry.heading(of: stroke.centerline)!
        model.press(at: stroke.start)
        model.move(to: point(0.35, on: stroke))
        let tip = point(0.35, on: stroke)
        let corner = LetterPoint(x: tip.x - heading.y * 16, y: tip.y + heading.x * 16)
        model.move(to: corner)
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.currentTrace.isEmpty)
        XCTAssertTrue(model.recordedPaths.isEmpty)
    }

    func testLineIsNotFinishedUntilTheStripes() {
        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        model.press(at: stroke.start, time: 1)
        model.move(to: point(0.82, on: stroke), time: 2)
        XCTAssertEqual(model.phase, .tracing)

        model.move(to: point(0.86, on: stroke), time: 2.2)
        model.move(to: point(0.83, on: stroke), time: 2.3)
        XCTAssertEqual(model.phase, .tracing)

        model.move(to: stroke.gate.center, time: 2.6)
        XCTAssertEqual(model.phase, .tracing)

        let middle = FinishZone.middle(on: stroke)
        let past = FinishZone.point(on: stroke, offset: FinishZone.middleOffset + 6)
        model.move(to: past, time: 2.9)
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertEqual(model.activeStrokeIndex, 1)
        let last = model.recordedPaths[0].last
        XCTAssertEqual(last?.distance(to: middle) ?? 99, 0, accuracy: 0.001)
    }

    func testReachingTheFinishStopsTheLine() {
        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        model.press(at: stroke.start, time: 5)
        for step in 1...20 {
            let progress = Double(step) / 20
            model.move(to: point(progress, on: stroke), time: 5 + 2 * progress)
        }
        XCTAssertEqual(model.phase, .tracing)
        model.move(to: FinishZone.middle(on: stroke), time: 7.4)
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertEqual(model.activeStrokeIndex, 1)
        let kept = model.recordedPaths[0].count
        let drawnFor = model.recordedDurations[0]
        XCTAssertEqual(drawnFor, 2.4, accuracy: 0.05)

        model.move(to: point(0.3, on: stroke), time: 9)
        model.release(at: stroke.start, time: 9.2)
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertEqual(model.recordedPaths[0].count, kept)
        XCTAssertEqual(model.recordedDurations, [drawnFor])
    }

    func testGoingBackOnTheCrossbarStopsTheStroke() {
        var model = RaceModel(glyph: playableA)
        trace(&model, along: model.track!.strokes[0])

        let bar = model.activeStroke!
        XCTAssertEqual(bar.id, 2)
        model.press(at: bar.start)
        model.move(to: point(0.7, on: bar))
        model.move(to: point(0.25, on: bar))
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.recordedPaths.count == 1)
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
        model.release(at: FinishZone.middle(on: stroke))
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertTrue(model.recordedPaths.isEmpty)
    }

    func testSuccessfulLetterReplaysThenCelebrates() {
        var model = RaceModel(glyph: playableA)
        let strokes = model.track!.strokes
        trace(&model, along: strokes[0])
        // Zero pause between strokes: immediately awaiting stroke 2 without intermediate driving wait.
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertEqual(model.activeStrokeIndex, 1)
        XCTAssertEqual(model.wallHits, 0)

        trace(&model, along: strokes[1])
        // After finishing the final stroke, the whole letter replays from stroke 0.
        XCTAssertEqual(model.phase, .replaying)
        XCTAssertEqual(model.replayIndex, 0)
        XCTAssertEqual(model.recordedPaths.count, strokes.count)
        for _ in strokes {
            model.motionFinished()
        }
        XCTAssertEqual(model.phase, .success)
        XCTAssertEqual(model.earnedStars, [3, 3])

        model.replay()
        XCTAssertEqual(model.phase, .replaying)
        for _ in strokes {
            model.motionFinished()
        }
        XCTAssertEqual(model.phase, .success)

        model.reset()
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertEqual(model.activeStrokeIndex, 0)
        XCTAssertTrue(model.recordedPaths.isEmpty)
    }

    func testSmoothedDrivePathAndHeadingContinuity() {
        let jagged = [
            LetterPoint(x: 0, y: 0),
            LetterPoint(x: 20, y: 0),
            LetterPoint(x: 20, y: 20),
        ]
        let smoothed = RoadGeometry.smoothed(jagged, iterations: 2)
        XCTAssertEqual(smoothed.first, jagged.first)
        XCTAssertEqual(smoothed.last, jagged.last)
        XCTAssertGreaterThan(smoothed.count, jagged.count)

        let beforeCorner = RoadGeometry.heading(of: jagged, at: 0.48)!
        let atCorner = RoadGeometry.heading(of: jagged, at: 0.50)!
        let afterCorner = RoadGeometry.heading(of: jagged, at: 0.52)!
        XCTAssertGreaterThan(atCorner.x, 0.2)
        XCTAssertGreaterThan(atCorner.y, 0.2)
        XCTAssertGreaterThan(beforeCorner.x, atCorner.x)
        XCTAssertGreaterThan(afterCorner.y, atCorner.y)

        var model = RaceModel(glyph: playableA)
        let stroke = model.activeStroke!
        let offsetStart = LetterPoint(x: stroke.start.x + 4, y: stroke.start.y)
        model.press(at: offsetStart)
        model.move(to: LetterPoint(x: offsetStart.x + 0.3, y: offsetStart.y - 0.2))
        XCTAssertEqual(model.currentTrace.count, 1)
        for step in 1...20 {
            model.move(to: point(Double(step) / 20, on: stroke))
        }
        model.release(at: FinishZone.middle(on: stroke))
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertEqual(model.activeStrokeIndex, 1)
        XCTAssertEqual(model.recordedPaths[0].first?.distance(to: stroke.start) ?? 99, 0, accuracy: 0.001)
        XCTAssertEqual(model.recordedPaths[0].last?.distance(to: FinishZone.middle(on: stroke)) ?? 99, 0, accuracy: 0.001)
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

    func testCarBurnsOutBeforeItRollsAndDriftsATightCorner() {
        let straight = [
            LetterPoint(x: 0, y: 40),
            LetterPoint(x: 140, y: 40),
        ]
        let launch = CarSimulation.run(path: straight)
        let early = launch.sample(at: 0.28)
        XCTAssertTrue(early.burning)
        XCTAssertLessThan(early.speed, launch.cruise * 0.45)
        XCTAssertGreaterThan(early.spinRate, early.speed * 2)
        XCTAssertLessThan(early.position.distance(to: straight[0]), 8)
        XCTAssertGreaterThan(launch.skids.filter { $0.time < CarSimulation.burnout }.count, 8)
        XCTAssertFalse(launch.puffs.isEmpty)
        let cruising = launch.sample(at: CarSimulation.burnout + 0.45)
        XCTAssertFalse(cruising.burning)
        XCTAssertGreaterThan(cruising.speed, launch.cruise * 0.55)
        let straightOff = launch.samples
            .filter { $0.time > CarSimulation.burnout + 0.2 && $0.progress < 0.9 }
            .map { abs($0.position.y - 40) }
            .max() ?? 0
        XCTAssertLessThan(straightOff, 2.2, "straight offset \(straightOff)")
        let parked = launch.sample(at: launch.duration)
        XCTAssertLessThan(parked.position.distance(to: straight[1]), 8)

        let hairpin = [
            LetterPoint(x: 0, y: 70),
            LetterPoint(x: 46, y: 70),
            LetterPoint(x: 46, y: 8),
        ]
        let slide = CarSimulation.run(path: hairpin)
        let corner = slide.samples.filter { $0.time > CarSimulation.burnout && $0.progress > 0.25 && $0.progress < 0.85 }
        let maxSlip = corner.map(\.slip).max() ?? 0
        let maxOff = corner
            .map { RoadGeometry.project($0.position, onto: hairpin).distance }
            .max() ?? 0
        XCTAssertGreaterThan(maxSlip, 0.45, "slip \(maxSlip)")
        XCTAssertGreaterThan(maxOff, 3.5, "offset \(maxOff)")
        let approach = slide.samples.filter { !$0.burning && $0.progress > 0.30 && $0.progress < 0.43 }
        let approachSpeed = approach.map(\.speed).max() ?? 999
        XCTAssertLessThan(approachSpeed, slide.cruise * 0.72, "approach \(approachSpeed)")
        let earlier = slide.samples.filter { !$0.burning && $0.progress > 0.05 && $0.progress < 0.18 }
        let earlierSpeed = earlier.map(\.speed).max() ?? 0
        XCTAssertGreaterThan(earlierSpeed, approachSpeed, "earlier \(earlierSpeed) approach \(approachSpeed)")
        XCTAssertGreaterThan(slide.puffs.filter { $0.time > CarSimulation.burnout }.count, 2)
        XCTAssertLessThan(slide.sample(at: slide.duration).position.distance(to: hairpin[2]), 10)

        let peak = LetterA.track.strokes[0].centerline
        let apex = CarSimulation.run(path: peak)
        let crown = apex.samples.filter { $0.progress > 0.35 && $0.progress < 0.7 }
        let crownOff = crown
            .map { RoadGeometry.project($0.position, onto: peak, near: $0.progress).distance }
            .max() ?? 0
        XCTAssertGreaterThan(crownOff, 2.5, "apex offset \(crownOff)")
        XCTAssertLessThan(crownOff, 9.5, "apex offset \(crownOff)")
        XCTAssertLessThan(apex.sample(at: apex.duration).position.distance(to: peak.last ?? LetterA.rightFoot), 10)

        let ovalPath = GlyphCatalog.glyph(id: "a")!.track!.strokes[0].centerline
        let oval = CarSimulation.run(path: ovalPath)
        let ovalWide = oval.samples
            .map { RoadGeometry.project($0.position, onto: ovalPath, near: $0.progress).distance }
            .max() ?? 0
        XCTAssertLessThan(ovalWide, 9, "oval offset \(ovalWide)")
        XCTAssertLessThan(oval.sample(at: oval.duration).position.distance(to: ovalPath.last!), 8)
        XCTAssertLessThan(oval.duration, 7, "oval took \(oval.duration)")
        XCTAssertLessThan(launch.duration, 4.5, "straight took \(launch.duration)")
        XCTAssertLessThan(slide.duration, 6, "hairpin took \(slide.duration)")
        XCTAssertLessThan(apex.duration, 6.5, "apex took \(apex.duration)")

        for ride in [launch, slide, apex, oval] {
            let jump = largestStep(in: ride)
            XCTAssertLessThan(jump, 2.8, "the car jumped \(jump) in one frame")
        }
    }

    func testTrackAwareViewportMaximizesSizeWhilePreservingAspectRatio() {
        let baseViewport = LetterViewport(width: 393, height: 752)
        for id in ["A", "a", "B", "b", "Q", "q", "W", "w"] {
            let track = GlyphCatalog.glyph(id: id)!.track!
            let fitted = LetterViewport(width: 393, height: 752, track: track)
            XCTAssertEqual(fitted.scaleX, fitted.scaleY, accuracy: 0.0001, "\(id) aspect ratio")
            XCTAssertGreaterThan(fitted.scale, baseViewport.scale, "\(id) should scale larger than base")

            let pad = track.roadHalfWidth
            for stroke in track.strokes {
                for point in stroke.centerline {
                    let vx = fitted.viewX(point)
                    let vy = fitted.viewY(point)
                    XCTAssertGreaterThan(vx - pad * fitted.scale, 0, "\(id) left clip")
                    XCTAssertLessThan(vx + pad * fitted.scale, 393, "\(id) right clip")
                    XCTAssertGreaterThan(vy - pad * fitted.scale, 0, "\(id) top clip")
                    XCTAssertLessThan(vy + pad * fitted.scale, 752, "\(id) bottom clip")
                }
            }
        }
    }

    func testLiveCarChasingAndLetterBDoubleBowlWithoutDonuts() {
        var model = RaceModel(glyph: GlyphCatalog.glyph(id: "B")!)
        trace(&model, along: model.track!.strokes[0])
        XCTAssertEqual(model.phase, .awaiting)
        XCTAssertEqual(model.activeStrokeIndex, 1)

        let bowls = model.activeStroke!
        model.press(at: bowls.start, time: 0)
        XCTAssertFalse(model.liveCar.hasLaunched)
        XCTAssertEqual(model.liveCar.position, bowls.start)

        // While tracing, the car stays parked on the start line until the entire letter is drawn.
        for step in 1...60 {
            let progress = Double(step) / 60.0
            model.move(to: point(progress, on: bowls), time: Double(step) * 0.04)
            XCTAssertFalse(model.liveCar.hasLaunched)
            XCTAssertEqual(model.liveCar.position, bowls.start)
        }

        model.release(at: FinishZone.middle(on: bowls), time: 2.5)
        XCTAssertEqual(model.phase, .replaying)
        XCTAssertEqual(model.replayIndex, 0)
        XCTAssertNil(model.completedLiveCar)

        let fullSim = CarSimulation.run(path: model.recordedPaths[1])
        var prevProgress = 0.0
        for sample in fullSim.samples {
            XCTAssertGreaterThanOrEqual(sample.progress + 0.0001, prevProgress, "progress went backward on B")
            prevProgress = sample.progress
            let off = RoadGeometry.project(sample.position, onto: bowls.centerline, near: sample.progress).distance
            XCTAssertLessThan(off, 9.0, "B double-bowl offset \(off) at progress \(sample.progress)")
        }
        XCTAssertLessThan(fullSim.sample(at: fullSim.duration).position.distance(to: FinishZone.middle(on: bowls)), 8)
    }

    func testThreeStarterSingleStrokeShapesBeforeLetters() {
        let starters = GlyphCatalog.starters
        XCTAssertEqual(starters.count, 3)
        XCTAssertEqual(starters.map(\.id), ["shape-line", "shape-curve", "shape-circle"])

        var progress = LevelProgress()
        for starter in starters {
            XCTAssertEqual(starter.kind, .shape)
            XCTAssertTrue(starter.isPlayable)
            XCTAssertTrue(GlyphCatalog.isStarterUnlocked(starter, progress: progress))
            XCTAssertEqual(starter.track?.strokes.count, 1)
            XCTAssertEqual(GlyphCatalog.glyph(id: starter.id), starter)

            var model = RaceModel(glyph: starter)
            let stroke = model.activeStroke!
            trace(&model, along: stroke)
            XCTAssertEqual(model.phase, .replaying)
            model.motionFinished()
            XCTAssertEqual(model.phase, .success)

            progress.recordPass(starter.id)
            XCTAssertEqual(progress.count(for: starter.id), 1)
        }
    }

    func testHighFrequencyCoalescedTouchAndRenderPrepPerformance() {
        var model = RaceModel(glyph: GlyphCatalog.glyph(id: "B")!)
        trace(&model, along: model.track!.strokes[0])
        let bowls = model.activeStroke!

        // Simulate 240 Hz coalesced touch stream (200 events over 0.85s) + 60 Hz frame ticks.
        let points = (1...200).map { point(Double($0) / 200.0, on: bowls) }
        let start = CFAbsoluteTimeGetCurrent()
        model.press(at: bowls.start, time: 0)
        for (idx, pt) in points.enumerated() {
            let step = idx + 1
            let time = Double(step) / 200.0 * 0.85
            model.move(to: pt, time: time)
            if step.isMultiple(of: 4) {
                model.advanceLiveCar(dt: 1.0 / 60.0, at: time)
                _ = LetterViewport(width: 393, height: 752, track: model.track).scale
                _ = model.track?.cachedPieces.count
                _ = model.track?.cachedGates.count
                if model.liveCar.hasLaunched {
                    _ = RoadGeometry.suffix(model.cachedLivePath, cumulative: model.cachedLiveCumulative, from: model.liveCar.progress)
                }
            }
        }
        model.release(at: FinishZone.middle(on: bowls), time: 0.86)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        XCTAssertEqual(model.phase, .replaying)
        XCTAssertLessThan(elapsedMs, 15.0, "200 coalesced touch moves + frame prep took \(elapsedMs) ms")
    }

    private func largestStep(in ride: CarSimulation) -> Double {
        var worst = 0.0
        for index in 1..<ride.samples.count {
            let step = ride.samples[index].position.distance(to: ride.samples[index - 1].position)
            worst = max(worst, step)
        }
        return worst
    }

    private var playableA: Glyph {
        GlyphCatalog.glyph(id: "A")!
    }

    private var longRoad: Glyph {
        let start = LetterPoint(x: 0, y: 0)
        let end = LetterPoint(x: 200, y: 0)
        let stroke = LetterStroke(
            id: 1,
            centerline: [start, end],
            gate: FinishGate(center: end, radius: 13)
        )
        return Glyph(
            id: "line",
            symbol: "I",
            kind: .letter,
            track: LetterTrack(strokes: [stroke], roadHalfWidth: 9)
        )
    }

    private func drifted(_ progress: Double, on stroke: LetterStroke, sideways: Double) -> LetterPoint {
        let base = point(progress, on: stroke)
        let start = stroke.centerline[0]
        let end = stroke.centerline[stroke.centerline.count - 1]
        return RoadGeometry.shifted(base, from: start, toward: end, sideways: sideways)
    }

    private func glide(
        _ model: inout RaceModel,
        on stroke: LetterStroke,
        from start: Double,
        to end: Double,
        sideFrom: Double,
        sideTo: Double
    ) {
        let steps = 8
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let progress = start + (end - start) * t
            let side = sideFrom + (sideTo - sideFrom) * t
            model.move(to: drifted(progress, on: stroke, sideways: side))
        }
    }

    private func bounds(of line: [LetterPoint]) -> (width: Double, height: Double) {
        let minX = line.map(\.x).min() ?? 0
        let maxX = line.map(\.x).max() ?? 0
        let minY = line.map(\.y).min() ?? 0
        let maxY = line.map(\.y).max() ?? 0
        return (maxX - minX, maxY - minY)
    }

    /// Smallest neighboring-heading dot, ignoring the fold at `skip`. Near 1 means every corner is round.
    private func sharpestCornerDot(on line: [LetterPoint], skippingAround skip: LetterPoint) -> Double {
        var smoothest = 1.0
        guard line.count >= 3 else { return smoothest }
        for index in 1..<(line.count - 1) {
            if line[index].distance(to: skip) < 4 { continue }
            let inbound = heading(from: line[index - 1], to: line[index])
            let outbound = heading(from: line[index], to: line[index + 1])
            smoothest = min(smoothest, inbound.x * outbound.x + inbound.y * outbound.y)
        }
        return smoothest
    }

    private func heading(from start: LetterPoint, to end: LetterPoint) -> LetterPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        return LetterPoint(x: dx / length, y: dy / length)
    }

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
            model.move(to: point(Double(step) / 20, on: stroke))
        }
        model.release(at: FinishZone.middle(on: stroke))
    }
}
