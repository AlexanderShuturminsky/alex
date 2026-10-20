import SwiftUI

enum TrackPalette {
    static let paper = Color(red: 0.937, green: 0.902, blue: 0.816)
    static let ink = Color(red: 0.141, green: 0.204, blue: 0.278)
    static let road = Color(red: 0.369, green: 0.431, blue: 0.471)
    static let edge = Color(red: 0.173, green: 0.220, blue: 0.251)
    static let hint = Color(red: 0.99, green: 0.96, blue: 0.90)
    static let active = Color(red: 0.878, green: 0.478, blue: 0.184)
    static let waiting = Color(red: 0.235, green: 0.290, blue: 0.333)
    static let done = Color(red: 0.184, green: 0.490, blue: 0.353)
    static let hatch = Color(red: 0.110, green: 0.141, blue: 0.169)
    static let fail = Color(red: 0.953, green: 0.839, blue: 0.800)
    static let success = Color(red: 0.835, green: 0.910, blue: 0.863)
    static let gold = Color(red: 0.93, green: 0.70, blue: 0.16)
    static let grass = Color(red: 0.239, green: 0.482, blue: 0.180)
    static let racingLine = Color(red: 1.0, green: 0.93, blue: 0.45)
    static let asphalt = Color(red: 0.24, green: 0.26, blue: 0.29)
    static let curb = Color(red: 0.82, green: 0.08, blue: 0.11)
}

enum CarRole {
    case active
    case waiting
    case done

    var fill: Color {
        switch self {
        case .active: TrackPalette.active
        case .waiting: TrackPalette.waiting
        case .done: TrackPalette.done
        }
    }
}

struct TrackView: View {
    var model: RaceModel
    var motion: Double
    var ride: CarSimulation?
    var driveTime: TimeInterval
    /// 0 is off the start, 1 is parked on it. The next car rolls in after the previous one finishes.
    var arrival: Double = 1
    var onBegin: (LetterPoint, TimeInterval) -> Void
    var onMove: (LetterPoint, TimeInterval) -> Void
    var onEnd: (LetterPoint, TimeInterval) -> Void
    var onCancel: () -> Void

    var body: some View {
        GeometryReader { geo in
            let viewport = LetterViewport(width: geo.size.width, height: geo.size.height)
            ZStack {
                Canvas { context, size in
                    drawTrack(context: context, viewport: viewport, canvas: size)
                }
                TrackPalette.fail
                    .opacity(model.phase == .failed ? 0.42 : 0)
                    .animation(.easeInOut(duration: 0.3), value: model.phase == .failed)
                    .allowsHitTesting(false)
                directionChevrons(viewport: viewport)
                badges(viewport: viewport)
                pointer(viewport: viewport)
                TouchCapture(
                    enabled: model.isAcceptingTouch && arrival >= 0.98,
                    onBegin: { onBegin(viewport.letter(x: $0.x, y: $0.y), $1) },
                    onMove: { onMove(viewport.letter(x: $0.x, y: $0.y), $1) },
                    onEnd: { onEnd(viewport.letter(x: $0.x, y: $0.y), $1) },
                    onCancel: onCancel
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Letter \(model.glyph.symbol) track")
        }
    }

    private func pointer(viewport: LetterViewport) -> some View {
        Group {
            if model.showsPointer,
               arrival >= 0.98,
               viewport.scale > 0,
               let stroke = highlightedStroke,
               let heading = RoadGeometry.heading(of: stroke.centerline) {
                let length = max(44, viewport.scale * 12)
                let carRadius = usesRacingTrack
                    ? Double(carLength(viewport: viewport)) / viewport.scale / 2
                    : Double(badgeSide(.active, viewport: viewport)) / viewport.scale / 2
                let tipClearance = carRadius + 5
                let centerBack = tipClearance + Double(length) / viewport.scale / 2
                let mid = LetterPoint(
                    x: stroke.start.x - heading.x * centerBack,
                    y: stroke.start.y - heading.y * centerBack
                )
                let angle = Angle(radians: atan2(heading.y, heading.x))
                PointingArrow(angle: angle, length: length)
                    .position(cg(mid, viewport))
                    .animation(.easeInOut(duration: 0.4), value: model.activeStrokeIndex)
            }
        }
    }

    private var usesRacingTrack: Bool {
        model.glyph.id == "A" || model.glyph.id == "a"
    }

    private func badges(viewport: LetterViewport) -> some View {
        let strokes = model.track?.strokes ?? []
        return ForEach(Array(strokes.enumerated()), id: \.element.id) { index, stroke in
            let role = role(for: index)
            let place = badgePosition(index: index, stroke: stroke, viewport: viewport)
            Group {
                if showsThisCar(index) {
                if usesRacingTrack {
                    let pose = movingPose(index)
                    PhotoCar(
                        length: carLength(viewport: viewport),
                        angle: carAngle(index: index, stroke: stroke),
                        imageName: stroke.id == 1 ? "CarRed" : "CarGreen",
                        braking: pose?.braking ?? false,
                        dimmed: role == .done
                    )
                } else {
                    CarBadge(
                        number: stroke.id,
                        role: role,
                        side: badgeSide(role, viewport: viewport)
                    )
                }
                }
            }
            .position(place)
            .animation(nil, value: place)
            .allowsHitTesting(false)
        }
    }

    /// On A and a, the other cars stay off the road so two of them never cross.
    private func showsThisCar(_ index: Int) -> Bool {
        guard usesRacingTrack else { return true }
        return index == highlightedIndex && model.phase != .success
    }

    private func carLength(viewport: LetterViewport) -> CGFloat {
        CGFloat(max(84, viewport.scale * 18))
    }

    private func movingPose(_ index: Int) -> CarSimulation.Sample? {
        guard isMoving(index), let ride else { return nil }
        return ride.sample(at: driveTime)
    }

    private func carAngle(index: Int, stroke: LetterStroke) -> Angle {
        if let pose = movingPose(index) {
            return Angle(radians: pose.body)
        }
        let path: [LetterPoint]
        let progress: Double
        if isMoving(index), model.recordedPaths.indices.contains(index) {
            path = model.recordedPaths[index]
            progress = motion
        } else if isParkedAtStart(index) {
            path = stroke.centerline
            progress = 0
        } else if model.recordedPaths.indices.contains(index) {
            path = model.recordedPaths[index]
            progress = 1
        } else {
            path = stroke.centerline
            progress = 1
        }
        guard let heading = RoadGeometry.heading(of: path, at: progress) ?? RoadGeometry.heading(of: path) else {
            return .zero
        }
        return Angle(radians: atan2(heading.y, heading.x))
    }

    private func drawTrack(context: GraphicsContext, viewport: LetterViewport, canvas: CGSize) {
        guard let track = model.track else { return }
        if usesRacingTrack {
            drawRacingTrack(track, viewport: viewport, context: context, canvas: canvas)
            return
        }
        let half = track.roadHalfWidth
        for stroke in track.strokes {
            let paved = FinishZone.extended(stroke.centerline, on: stroke, through: FinishZone.endOffset)
            strokeRoad(paved, width: (half * 2 + 2.4) * viewport.scale, color: TrackPalette.edge, viewport: viewport, context: context)
        }
        for stroke in track.strokes {
            let paved = FinishZone.extended(stroke.centerline, on: stroke, through: FinishZone.endOffset)
            strokeRoad(paved, width: half * 2 * viewport.scale, color: TrackPalette.road, viewport: viewport, context: context)
        }
        for (index, stroke) in track.strokes.enumerated() {
            let alpha = hintAlpha(index)
            if alpha <= 0.01 { continue }
            let strength = index == highlightedIndex ? 0.62 : 0.34
            let guide = FinishZone.extended(stroke.centerline, on: stroke, through: FinishZone.middleOffset)
            strokeRoad(
                guide,
                width: half * 0.34 * viewport.scale,
                color: TrackPalette.hint.opacity(strength * alpha),
                viewport: viewport,
                context: context
            )
        }
        for (index, stroke) in track.strokes.enumerated() {
            drawGate(stroke, active: index == highlightedIndex, viewport: viewport, context: context)
        }
        drawInk(viewport: viewport, context: context, color: model.phase == .almost ? TrackPalette.active : TrackPalette.ink.opacity(0.9))
    }

    /// Grass, asphalt, and a red-and-white curb. Chevrons, the dashed guide, and the
    /// checker belong only to the stroke the next car will drive.
    private func drawRacingTrack(_ track: LetterTrack, viewport: LetterViewport, context: GraphicsContext, canvas: CGSize) {
        drawLawn(context: context, canvas: canvas)
        let half = track.roadHalfWidth
        let roadWidth = half * 2 * viewport.scale
        let curbExtra = max(8, viewport.scale * 2.5)
        let curbWidth = roadWidth + curbExtra * 2
        let dash = CGFloat(max(11, viewport.scale * 3.4))
        let pieces = roadPieces(of: track)
        let shadow = CGSize(width: viewport.scale * 0.35, height: max(4, viewport.scale * 1.05))
        for piece in pieces {
            strokeRoad(
                piece.asphalt,
                width: curbWidth + 6,
                color: .black.opacity(0.18),
                viewport: viewport,
                context: context,
                viewShift: shadow
            )
        }
        for piece in pieces {
            strokeRoad(piece.curb, width: curbWidth, color: TrackPalette.curb, viewport: viewport, context: context)
            strokeRoad(
                piece.curb,
                width: curbWidth,
                color: .white,
                viewport: viewport,
                context: context,
                dash: [dash, dash],
                cap: .butt
            )
        }
        for piece in pieces {
            strokeRoad(piece.asphalt, width: roadWidth, color: TrackPalette.asphalt, viewport: viewport, context: context)
        }
        if let stroke = highlightedStroke, hintAlpha(highlightedIndex) > 0.01 {
            let guide = FinishZone.extended(stroke.centerline, on: stroke, through: FinishZone.middleOffset)
            let mark = CGFloat(max(7, viewport.scale * 2.1))
            strokeRoad(
                guide,
                width: max(2.2, half * 0.16 * viewport.scale),
                color: .white.opacity(0.92 * hintAlpha(highlightedIndex)),
                viewport: viewport,
                context: context,
                dash: [mark, mark * 0.85],
                cap: .butt
            )
        }
        if model.phase != .success, let stroke = highlightedStroke {
            drawCheckeredGate(stroke, roads: pieces.map(\.asphalt), viewport: viewport, context: context)
        }
        if let ride {
            drawSkids(ride, until: driveTime, viewport: viewport, context: context)
            drawSmoke(ride, at: driveTime, viewport: viewport, context: context)
        }
        let ink = model.phase == .almost ? TrackPalette.active : TrackPalette.racingLine
        drawInk(viewport: viewport, context: context, color: ink)
    }

    private func drawLawn(context: GraphicsContext, canvas: CGSize) {
        let tile: CGFloat = 180
        let image = context.resolve(Image("Grass"))
        var y: CGFloat = 0
        while y < canvas.height {
            var x: CGFloat = 0
            while x < canvas.width {
                context.draw(image, in: CGRect(x: x, y: y, width: tile, height: tile))
                x += tile
            }
            y += tile
        }
    }

    private func drawSkids(_ ride: CarSimulation, until time: Double, viewport: LetterViewport, context: GraphicsContext) {
        let visible = ride.skids.filter { $0.time <= time + 0.0001 }
        guard visible.count >= 2 else { return }
        let halfTrack = Double(carLength(viewport: viewport)) / viewport.scale * 0.155
        let width = max(2.4, viewport.scale * 0.62)
        for side in [-1.0, 1.0] {
            var run: [LetterPoint] = []
            var lastTime = -1.0
            func flush() {
                if run.count >= 2 {
                    strokeRoad(
                        run,
                        width: width,
                        color: Color.black.opacity(0.48),
                        viewport: viewport,
                        context: context
                    )
                }
                run = []
            }
            for skid in visible {
                if lastTime >= 0, skid.time - lastTime > 0.08 {
                    flush()
                }
                let sideX = -sin(skid.body) * halfTrack * side
                let sideY = cos(skid.body) * halfTrack * side
                run.append(LetterPoint(x: skid.position.x + sideX, y: skid.position.y + sideY))
                lastTime = skid.time
            }
            flush()
        }
    }

    private func drawSmoke(_ ride: CarSimulation, at time: Double, viewport: LetterViewport, context: GraphicsContext) {
        for puff in ride.puffs where puff.time <= time {
            let age = time - puff.time
            guard age < 0.9 else { continue }
            let fade = 1 - age / 0.9
            let center = cg(
                LetterPoint(
                    x: puff.position.x + puff.blowX * age,
                    y: puff.position.y + puff.blowY * age
                ),
                viewport
            )
            let radius = viewport.scale * (1.15 + age * 5.2)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.42 * fade)))
            let core = radius * 0.55
            let inner = CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)
            context.fill(Path(ellipseIn: inner), with: .color(Color(red: 0.85, green: 0.87, blue: 0.9).opacity(0.35 * fade)))
        }
    }

    private func drawInk(viewport: LetterViewport, context: GraphicsContext, color: Color) {
        for ink in inkPaths() {
            let partial = RoadGeometry.prefix(ink.points, through: ink.progress)
            strokeRoad(
                partial,
                width: max(4, viewport.scale * 3.4),
                color: color,
                viewport: viewport,
                context: context
            )
        }
    }

    private func strokeRoad(
        _ points: [LetterPoint],
        width: Double,
        color: Color,
        viewport: LetterViewport,
        context: GraphicsContext,
        dash: [CGFloat]? = nil,
        cap: CGLineCap = .round,
        viewShift: CGSize = .zero
    ) {
        guard let first = points.first else { return }
        func shifted(_ point: LetterPoint) -> CGPoint {
            let view = cg(point, viewport)
            return CGPoint(x: view.x + viewShift.width, y: view.y + viewShift.height)
        }
        var path = Path()
        path.move(to: shifted(first))
        for point in points.dropFirst() {
            path.addLine(to: shifted(point))
        }
        var style = StrokeStyle(lineWidth: CGFloat(width), lineCap: cap, lineJoin: cap == .butt ? .bevel : .round)
        if let dash {
            style.dash = dash
        }
        context.stroke(path, with: .color(color), style: style)
    }

    /// One outline for the whole letter. A stroke that ends inside another stroke
    /// stops its curb at that edge, so the join is a single road instead of two caps.
    private func roadPieces(of track: LetterTrack) -> [(asphalt: [LetterPoint], curb: [LetterPoint])] {
        let half = track.roadHalfWidth
        let strokes = track.strokes
        return strokes.enumerated().map { index, stroke in
            let line = stroke.centerline
            guard line.count >= 2 else { return (line, line) }
            let startJoined = joins(line[0], besides: index, strokes: strokes, half: half)
            let endJoined = joins(line[line.count - 1], besides: index, strokes: strokes, half: half)
            var asphalt = line
            if !endJoined {
                asphalt = FinishZone.extended(line, on: stroke, through: FinishZone.endOffset)
            }
            var curb = asphalt
            if startJoined {
                curb = trim(curb, fromEnd: false, besides: index, strokes: strokes, half: half)
            }
            if endJoined {
                curb = trim(curb, fromEnd: true, besides: index, strokes: strokes, half: half)
            }
            if curb.count < 2 { curb = asphalt }
            return (asphalt, curb)
        }
    }

    private func joins(_ point: LetterPoint, besides index: Int, strokes: [LetterStroke], half: Double) -> Bool {
        for (other, stroke) in strokes.enumerated() where other != index {
            if RoadGeometry.project(point, onto: stroke.centerline).distance <= half * 1.25 {
                return true
            }
        }
        return false
    }

    private func covered(_ point: LetterPoint, besides index: Int, strokes: [LetterStroke], half: Double) -> Bool {
        for (other, stroke) in strokes.enumerated() where other != index {
            if RoadGeometry.project(point, onto: stroke.centerline).distance <= half * 0.94 {
                return true
            }
        }
        return false
    }

    /// Drops the end that sits inside another stroke, stopping where that road's edge is.
    private func trim(
        _ line: [LetterPoint],
        fromEnd: Bool,
        besides index: Int,
        strokes: [LetterStroke],
        half: Double
    ) -> [LetterPoint] {
        guard line.count >= 2 else { return line }
        let sequence = fromEnd ? Array(line.reversed()) : line
        if !covered(sequence[0], besides: index, strokes: strokes, half: half) { return line }
        var traveled = 0.0
        var previous = sequence[0]
        for point in sequence.dropFirst() {
            let step = previous.distance(to: point)
            if !covered(point, besides: index, strokes: strokes, half: half) {
                let cut = traveled + step * 0.55
                let trimmed = fromEnd ? drop(cut, fromEndOf: line) : drop(cut, fromStartOf: line)
                return trimmed.count >= 2 ? trimmed : line
            }
            traveled += step
            previous = point
        }
        return line
    }

    private func drop(_ distance: Double, fromStartOf line: [LetterPoint]) -> [LetterPoint] {
        guard line.count >= 2, distance > 0 else { return line }
        var left = distance
        var index = 0
        while index < line.count - 1 {
            let step = line[index].distance(to: line[index + 1])
            if left <= step {
                let t = step > 0 ? left / step : 0
                let mid = LetterPoint(
                    x: line[index].x + (line[index + 1].x - line[index].x) * t,
                    y: line[index].y + (line[index + 1].y - line[index].y) * t
                )
                return [mid] + Array(line[(index + 1)...])
            }
            left -= step
            index += 1
        }
        return [line[line.count - 1]]
    }

    private func drop(_ distance: Double, fromEndOf line: [LetterPoint]) -> [LetterPoint] {
        let trimmed = drop(distance, fromStartOf: Array(line.reversed()))
        return Array(trimmed.reversed())
    }

    /// Black and white squares across the road, from the first hatch through the end of the pavement.
    private func drawCheckeredGate(
        _ stroke: LetterStroke,
        roads: [[LetterPoint]],
        viewport: LetterViewport,
        context: GraphicsContext
    ) {
        guard stroke.centerline.count >= 2,
              let heading = RoadGeometry.heading(of: stroke.centerline, at: 1) else { return }
        let end = stroke.centerline[stroke.centerline.count - 1]
        let endV = cg(end, viewport)
        let ahead = cg(LetterPoint(x: end.x + heading.x, y: end.y + heading.y), viewport)
        let angle = atan2(ahead.y - endV.y, ahead.x - endV.x)
        let alongScale = viewport.viewScale(along: heading)
        let acrossScale = viewport.viewScale(across: heading)
        let half = model.track?.roadHalfWidth ?? 10
        let bandStart = FinishZone.offsets.first ?? 0
        let bandEnd = FinishZone.endOffset
        let rows = 6
        let cellAcross = (half * 2) / Double(rows)
        let columns = max(2, Int(((bandEnd - bandStart) / cellAcross).rounded()))
        let cellAlong = (bandEnd - bandStart) / Double(columns)
        let forwardX = cos(angle)
        let forwardY = sin(angle)
        let sideX = cos(angle + .pi / 2)
        let sideY = sin(angle + .pi / 2)

        func corner(along: Double, across: Double) -> CGPoint {
            CGPoint(
                x: endV.x + CGFloat(forwardX * along * alongScale + sideX * across * acrossScale),
                y: endV.y + CGFloat(forwardY * along * alongScale + sideY * across * acrossScale)
            )
        }

        for row in 0..<rows {
            for column in 0..<columns {
                let along0 = bandStart + Double(column) * cellAlong
                let across0 = -half + Double(row) * cellAcross
                let center = LetterPoint(
                    x: end.x + heading.x * (along0 + cellAlong / 2) - heading.y * (across0 + cellAcross / 2),
                    y: end.y + heading.y * (along0 + cellAlong / 2) + heading.x * (across0 + cellAcross / 2)
                )
                let onRoad = roads.contains { road in
                    RoadGeometry.project(center, onto: road).distance <= half * 0.98
                }
                if !onRoad { continue }
                var path = Path()
                path.move(to: corner(along: along0, across: across0))
                path.addLine(to: corner(along: along0 + cellAlong, across: across0))
                path.addLine(to: corner(along: along0 + cellAlong, across: across0 + cellAcross))
                path.addLine(to: corner(along: along0, across: across0 + cellAcross))
                path.closeSubpath()
                let black = (row + column).isMultiple(of: 2)
                context.fill(path, with: .color(black ? Color.black : Color.white))
            }
        }
        let shared = roads.filter { RoadGeometry.project(end, onto: $0).distance <= half * 0.5 }.count
        if shared < 2 {
            var border = Path()
            border.move(to: corner(along: bandStart, across: -half))
            border.addLine(to: corner(along: bandEnd, across: -half))
            border.addLine(to: corner(along: bandEnd, across: half))
            border.addLine(to: corner(along: bandStart, across: half))
            border.closeSubpath()
            context.stroke(border, with: .color(.black.opacity(0.85)), lineWidth: max(1.5, viewport.scale * 0.28))
        }
    }

    private func drawGate(_ stroke: LetterStroke, active: Bool, viewport: LetterViewport, context: GraphicsContext) {
        guard stroke.centerline.count >= 2 else { return }
        let start = stroke.centerline[stroke.centerline.count - 2]
        let end = stroke.centerline[stroke.centerline.count - 1]
        let letterDx = end.x - start.x
        let letterDy = end.y - start.y
        let letterSpan = max(0.001, hypot(letterDx, letterDy))
        let heading = LetterPoint(x: letterDx / letterSpan, y: letterDy / letterSpan)
        let startV = cg(start, viewport)
        let endV = cg(end, viewport)
        let angle = atan2(endV.y - startV.y, endV.x - startV.x)
        let alongScale = viewport.viewScale(along: heading)
        let half = CGFloat(viewport.scale * (model.track?.roadHalfWidth ?? 13) * 0.95)
        var path = Path()
        for offset in FinishZone.offsets {
            let along = CGFloat(offset * alongScale)
            let cx = endV.x + CGFloat(cos(angle)) * along
            let cy = endV.y + CGFloat(sin(angle)) * along
            let px = CGFloat(cos(angle + .pi / 2))
            let py = CGFloat(sin(angle + .pi / 2))
            path.move(to: CGPoint(x: cx - px * half, y: cy - py * half))
            path.addLine(to: CGPoint(x: cx + px * half, y: cy + py * half))
        }
        context.stroke(
            path,
            with: .color(active ? TrackPalette.active : TrackPalette.hatch.opacity(0.85)),
            style: StrokeStyle(lineWidth: active ? 2.4 : 1.6, lineCap: .round)
        )
    }

    /// Chevrons sit on the hint and leave as the finger draws over them.
    @ViewBuilder
    private func directionChevrons(viewport: LetterViewport) -> some View {
        if showsDirectionMarks, viewport.scale > 0 {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let items = chevronItems(viewport: viewport, time: time)
                ZStack {
                    ForEach(items) { item in
                        ChevronShape()
                            .fill((usesRacingTrack ? Color.white : TrackPalette.ink).opacity(item.opacity))
                            .frame(width: item.along, height: item.across)
                            .scaleEffect(item.scale)
                            .rotationEffect(item.angle)
                            .position(item.position)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var showsDirectionMarks: Bool {
        guard let strokes = model.track?.strokes else { return false }
        return strokes.indices.contains { drawnProgress(for: $0) < 0.98 }
    }

    /// 1 means that stroke's line is already drawn, so its chevrons are gone.
    private func drawnProgress(for index: Int) -> Double {
        switch model.phase {
        case .success, .replaying:
            return 1
        case .driving:
            return index <= model.activeStrokeIndex ? 1 : 0
        case .tracing:
            if index < model.activeStrokeIndex { return 1 }
            if index == model.activeStrokeIndex { return model.maxProgress }
            return 0
        default:
            return index < model.activeStrokeIndex ? 1 : 0
        }
    }

    private func chevronItems(viewport: LetterViewport, time: TimeInterval) -> [ChevronItem] {
        guard let track = model.track else { return [] }
        let half = track.roadHalfWidth
        let along = CGFloat(max(14, viewport.scale * half * 0.72))
        let across = CGFloat(max(12, viewport.scale * half * 0.55))
        var items: [ChevronItem] = []
        for (index, stroke) in track.strokes.enumerated() {
            guard index == highlightedIndex else { continue }
            let drawn = drawnProgress(for: index)
            guard drawn < 0.98 else { continue }
            let marks = RoadGeometry.directionMarks(along: stroke.centerline)
            for (markIndex, mark) in marks.enumerated() where mark.progress > drawn + 0.03 {
                let wave = 0.5 + 0.5 * sin(time * 2.4 - mark.progress * 9)
                let angle = Angle(radians: atan2(mark.heading.y, mark.heading.x))
                items.append(
                    ChevronItem(
                        id: "\(stroke.id)-\(markIndex)",
                        position: cg(mark.point, viewport),
                        angle: angle,
                        along: along,
                        across: across,
                        opacity: 0.58 + 0.42 * wave,
                        scale: CGFloat(0.94 + 0.06 * wave)
                    )
                )
            }
        }
        return items
    }

    /// The guide belongs to the stroke that is next. It fades once that car is on its way.
    private func hintAlpha(_ index: Int) -> Double {
        guard index == highlightedIndex, model.phase != .success, model.phase != .replaying else { return 0 }
        switch model.phase {
        case .driving:
            if usesRacingTrack, let ride {
                return max(0, 1 - ride.sample(at: driveTime).progress)
            }
            return max(0, 1 - motion)
        default:
            return 1
        }
    }

    private func inkPaths() -> [(points: [LetterPoint], progress: Double)] {
        switch model.phase {
        case .replaying:
            return model.recordedPaths.enumerated().compactMap { index, path in
                if index < model.replayIndex { return (path, 1) }
                if index == model.replayIndex { return (path, motion) }
                return nil
            }
        default:
            var paths = model.recordedPaths.map { (points: $0, progress: 1.0) }
            if !model.currentTrace.isEmpty {
                paths.append((model.currentTrace, 1))
            }
            return paths
        }
    }

    private var highlightedIndex: Int {
        model.phase == .replaying ? model.replayIndex : model.activeStrokeIndex
    }

    private var highlightedStroke: LetterStroke? {
        guard let strokes = model.track?.strokes, strokes.indices.contains(highlightedIndex) else { return nil }
        return strokes[highlightedIndex]
    }

    private func role(for index: Int) -> CarRole {
        if isMoving(index) || (index == highlightedIndex && model.phase != .success) {
            return .active
        }
        if isParkedAtStart(index) {
            return .waiting
        }
        return .done
    }

    private func isMoving(_ index: Int) -> Bool {
        switch model.phase {
        case .driving:
            return index == model.activeStrokeIndex
        case .replaying:
            return index == model.replayIndex
        default:
            return false
        }
    }

    private func isParkedAtStart(_ index: Int) -> Bool {
        switch model.phase {
        case .success:
            return false
        case .replaying:
            return index > model.replayIndex
        case .driving:
            return index > model.activeStrokeIndex
        default:
            return index >= model.activeStrokeIndex
        }
    }

    private func badgeSide(_ role: CarRole, viewport: LetterViewport) -> CGFloat {
        let base = viewport.scale * (role == .active ? 18.0 : 14.0)
        return CGFloat(max(role == .active ? 48.0 : 36.0, base))
    }

    private func badgePosition(index: Int, stroke: LetterStroke, viewport: LetterViewport) -> CGPoint {
        cg(carPoint(index: index, stroke: stroke), viewport)
    }

    private func carPoint(index: Int, stroke: LetterStroke) -> LetterPoint {
        if let pose = movingPose(index) {
            return pose.position
        }
        if isMoving(index), model.recordedPaths.indices.contains(index) {
            return RoadGeometry.point(at: motion, along: model.recordedPaths[index])
        }
        if isParkedAtStart(index) {
            if usesRacingTrack, arrival < 0.999, index == highlightedIndex,
               let heading = RoadGeometry.heading(of: stroke.centerline) {
                let eased = 1 - (1 - arrival) * (1 - arrival)
                let distance = 34 * (1 - eased)
                return LetterPoint(
                    x: stroke.start.x - heading.x * distance,
                    y: stroke.start.y - heading.y * distance
                )
            }
            if shouldNudge(index, stroke: stroke) {
                return LetterPoint(x: stroke.start.x + 22, y: stroke.start.y - 20)
            }
            return stroke.start
        }
        if model.recordedPaths.indices.contains(index), let last = model.recordedPaths[index].last {
            return last
        }
        return stroke.gate.center
    }

    private func shouldNudge(_ index: Int, stroke: LetterStroke) -> Bool {
        guard index != highlightedIndex, isParkedAtStart(index) else { return false }
        guard let highlighted = highlightedStroke, isParkedAtStart(highlightedIndex) else { return false }
        return highlighted.start.distance(to: stroke.start) < 2
    }

    private func cg(_ point: LetterPoint, _ viewport: LetterViewport) -> CGPoint {
        CGPoint(x: viewport.viewX(point), y: viewport.viewY(point))
    }
}

/// The photographed car. Its nose points right, and the view turns that onto the heading.
private struct PhotoCar: View {
    var length: CGFloat
    var angle: Angle
    var imageName: String
    var braking: Bool
    var dimmed: Bool

    var body: some View {
        let height = length * 0.46
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.22))
                .frame(width: length * 0.62, height: height * 0.42)
                .offset(y: height * 0.12)
            Image(imageName)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: length, height: height)
            if braking {
                Capsule()
                    .fill(Color.red.opacity(0.55))
                    .frame(width: length * 0.05, height: height * 0.22)
                    .offset(x: -length * 0.46)
                    .blur(radius: 3)
            }
        }
        .frame(width: length, height: height)
        .rotationEffect(angle)
        .opacity(dimmed ? 0.85 : 1)
    }
}

private struct CarBadge: View {
    var number: Int
    var role: CarRole
    var side: CGFloat

    var body: some View {
        Text("\(number)")
            .font(.system(size: role == .active ? 18 : 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(role.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(role == .active ? 0.95 : 0.35), lineWidth: role == .active ? 2 : 1)
            )
    }
}

private struct ChevronItem: Identifiable {
    var id: String
    var position: CGPoint
    var angle: Angle
    var along: CGFloat
    var across: CGFloat
    var opacity: Double
    var scale: CGFloat
}

private struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct PointingArrow: View {
    var angle: Angle
    var length: CGFloat
    @State private var pulse = false

    var body: some View {
        ArrowShape()
            .fill(TrackPalette.active)
            .frame(width: length, height: length * 0.62)
            .scaleEffect(pulse ? 1.06 : 0.94)
            .rotationEffect(angle)
            .opacity(pulse ? 1 : 0.55)
            .shadow(color: TrackPalette.active.opacity(0.45), radius: pulse ? 8 : 2)
            .allowsHitTesting(false)
            .onAppear { pulse = true }
            .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: pulse)
    }
}

private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let neck = rect.minX + rect.width * 0.58
        path.move(to: CGPoint(x: rect.minX, y: midY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: neck, y: midY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: neck, y: rect.minY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: midY))
        path.addLine(to: CGPoint(x: neck, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: neck, y: midY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.minX, y: midY + rect.height * 0.18))
        path.closeSubpath()
        return path
    }
}
