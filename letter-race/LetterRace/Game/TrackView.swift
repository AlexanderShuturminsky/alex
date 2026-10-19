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
    static let grass = Color(red: 0.30, green: 0.52, blue: 0.16)
    static let grassLight = Color(red: 0.43, green: 0.67, blue: 0.24)
    static let racingLine = Color(red: 1.0, green: 0.93, blue: 0.45)
    static let asphalt = Color(red: 0.24, green: 0.26, blue: 0.29)
    static let asphaltWorn = Color(red: 0.34, green: 0.35, blue: 0.38)
    static let curb = Color(red: 0.82, green: 0.08, blue: 0.11)
    static let curbShadow = Color(red: 0.40, green: 0.03, blue: 0.05)
    static let carRed = Color(red: 0.78, green: 0.07, blue: 0.11)
    static let carGreen = Color(red: 0.02, green: 0.46, blue: 0.22)
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
                    enabled: model.isAcceptingTouch,
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
                if usesRacingTrack {
                    let pose = movingPose(index)
                    ToyCar(
                        length: carLength(viewport: viewport),
                        angle: carAngle(index: index, stroke: stroke),
                        paint: stroke.id == 1 ? TrackPalette.carRed : TrackPalette.carGreen,
                        spin: pose?.spin ?? 0,
                        braking: pose?.braking ?? false,
                        pulsing: role == .active && model.showsPointer,
                        dimmed: role == .done
                    )
                } else {
                    CarBadge(
                        number: stroke.id,
                        role: role,
                        side: badgeSide(role, viewport: viewport),
                        pulsing: role == .active && model.showsPointer
                    )
                }
            }
            .position(place)
            .allowsHitTesting(false)
        }
    }

    private func carLength(viewport: LetterViewport) -> CGFloat {
        CGFloat(max(72, viewport.scale * 15.5))
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

    /// Mowed grass, a raised road, and a car that can leave rubber and smoke.
    private func drawRacingTrack(_ track: LetterTrack, viewport: LetterViewport, context: GraphicsContext, canvas: CGSize) {
        drawLawn(context: context, canvas: canvas)
        let half = track.roadHalfWidth
        let roadWidth = half * 2 * viewport.scale
        let curbExtra = max(8, viewport.scale * 2.5)
        let curbWidth = roadWidth + curbExtra * 2
        let dash = CGFloat(max(11, viewport.scale * 3.4))
        let pavedStrokes = track.strokes.map {
            FinishZone.extended($0.centerline, on: $0, through: FinishZone.endOffset)
        }
        let shadow = CGSize(width: viewport.scale * 0.35, height: max(4, viewport.scale * 1.05))
        for paved in pavedStrokes {
            strokeRoad(
                paved,
                width: curbWidth + 6,
                color: .black.opacity(0.22),
                viewport: viewport,
                context: context,
                viewShift: shadow
            )
            strokeRoad(paved, width: curbWidth + curbExtra * 0.55, color: TrackPalette.curbShadow, viewport: viewport, context: context)
            strokeRoad(paved, width: curbWidth, color: TrackPalette.curb, viewport: viewport, context: context)
            strokeRoad(
                paved,
                width: curbWidth,
                color: .white,
                viewport: viewport,
                context: context,
                dash: [dash, dash],
                cap: .butt
            )
        }
        for paved in pavedStrokes {
            strokeRoad(paved, width: roadWidth + max(2.5, viewport.scale * 0.45), color: Color.white.opacity(0.92), viewport: viewport, context: context)
            strokeRoad(paved, width: roadWidth, color: TrackPalette.asphalt, viewport: viewport, context: context)
            strokeRoad(paved, width: roadWidth * 0.46, color: TrackPalette.asphaltWorn, viewport: viewport, context: context)
        }
        for (index, stroke) in track.strokes.enumerated() {
            let alpha = hintAlpha(index)
            if alpha <= 0.01 { continue }
            let strength = index == highlightedIndex ? 0.92 : 0.45
            let guide = FinishZone.extended(stroke.centerline, on: stroke, through: FinishZone.middleOffset)
            let mark = CGFloat(max(7, viewport.scale * 2.1))
            strokeRoad(
                guide,
                width: max(2.2, half * 0.16 * viewport.scale),
                color: .white.opacity(strength * alpha),
                viewport: viewport,
                context: context,
                dash: [mark, mark * 0.85],
                cap: .butt
            )
        }
        for stroke in track.strokes {
            drawCheckeredGate(stroke, viewport: viewport, context: context)
        }
        if let ride {
            drawSkids(ride, until: driveTime, viewport: viewport, context: context)
            drawSmoke(ride, at: driveTime, viewport: viewport, context: context)
        }
        let ink = model.phase == .almost ? TrackPalette.active : TrackPalette.racingLine
        drawInk(viewport: viewport, context: context, color: ink)
    }

    private func drawLawn(context: GraphicsContext, canvas: CGSize) {
        let band: CGFloat = 26
        var y: CGFloat = 0
        var index = 0
        while y < canvas.height {
            let rect = CGRect(x: 0, y: y, width: canvas.width, height: band + 0.5)
            let color = index.isMultiple(of: 2) ? TrackPalette.grassLight : TrackPalette.grass
            context.fill(Path(rect), with: .color(color))
            y += band
            index += 1
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

    /// Black and white squares across the road, from the first hatch through the end of the pavement.
    private func drawCheckeredGate(_ stroke: LetterStroke, viewport: LetterViewport, context: GraphicsContext) {
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
        var border = Path()
        border.move(to: corner(along: bandStart, across: -half))
        border.addLine(to: corner(along: bandEnd, across: -half))
        border.addLine(to: corner(along: bandEnd, across: half))
        border.addLine(to: corner(along: bandStart, across: half))
        border.closeSubpath()
        context.stroke(border, with: .color(.black.opacity(0.85)), lineWidth: max(1.5, viewport.scale * 0.28))
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
            let drawn = drawnProgress(for: index)
            guard drawn < 0.98 else { continue }
            let emphasis = index == highlightedIndex ? 1.0 : 0.58
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
                        opacity: (0.58 + 0.42 * wave) * emphasis,
                        scale: CGFloat(0.94 + 0.06 * wave)
                    )
                )
            }
        }
        return items
    }

    /// The ghost of the stroke stays until that car reaches the hatches, then fades out.
    private func hintAlpha(_ index: Int) -> Double {
        switch model.phase {
        case .success, .replaying:
            return 0
        case .driving:
            if index < model.activeStrokeIndex { return 0 }
            if index == model.activeStrokeIndex {
                if usesRacingTrack, let ride {
                    return max(0, 1 - ride.sample(at: driveTime).progress)
                }
                return max(0, 1 - motion)
            }
            return 1
        default:
            return index >= model.activeStrokeIndex ? 1 : 0
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

/// Top-down toy sports car. It points right, then the view turns it onto its heading.
/// Wheels sit in arches, and the rims spin with `spin`.
private struct ToyCar: View {
    var length: CGFloat
    var angle: Angle
    var paint: Color
    var spin: Double
    var braking: Bool
    var pulsing: Bool
    var dimmed: Bool
    @State private var pulse = false

    var body: some View {
        let height = length * 0.46
        Canvas { context, size in
            var context = context
            draw(in: &context, size: size)
        }
        .frame(width: length, height: height)
        .rotationEffect(angle)
        .opacity(dimmed ? 0.78 : 1)
        .scaleEffect(pulsing && pulse ? 1.045 : 1)
        .onAppear { pulse = true }
        .animation(pulsing ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: pulse)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: width * x, y: height * y)
        }

        let shadow = CGRect(x: width * 0.1, y: height * 0.18, width: width * 0.8, height: height * 0.68)
        context.fill(
            Path(ellipseIn: shadow.offsetBy(dx: 0, dy: height * 0.05)),
            with: .color(.black.opacity(0.28))
        )

        let along = width * 0.16
        let across = height * 0.18
        wheel(in: &context, center: at(0.28, 0.1), along: along, across: across)
        wheel(in: &context, center: at(0.28, 0.9), along: along, across: across)
        wheel(in: &context, center: at(0.73, 0.1), along: along, across: across)
        wheel(in: &context, center: at(0.73, 0.9), along: along, across: across)

        let body = bodyPath(width: width, height: height)
        context.fill(body, with: .color(paint))
        context.fill(
            body,
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(0.5),
                    Color.white.opacity(0.08),
                    Color.black.opacity(0.28),
                ]),
                startPoint: at(0.5, 0.12),
                endPoint: at(0.5, 0.9)
            )
        )
        context.stroke(body, with: .color(.white.opacity(0.72)), lineWidth: max(1.3, width * 0.016))

        context.fill(
            Path(ellipseIn: CGRect(x: width * 0.7, y: height * 0.4, width: width * 0.18, height: height * 0.2)),
            with: .color(.white.opacity(0.16))
        )

        let cabin = Path(
            roundedRect: CGRect(x: width * 0.34, y: height * 0.28, width: width * 0.28, height: height * 0.44),
            cornerRadius: height * 0.12
        )
        context.fill(cabin, with: .color(.black.opacity(0.42)))

        var glass = Path()
        glass.move(to: at(0.52, 0.32))
        glass.addLine(to: at(0.64, 0.27))
        glass.addLine(to: at(0.64, 0.73))
        glass.addLine(to: at(0.52, 0.68))
        glass.closeSubpath()
        context.fill(glass, with: .color(Color(red: 0.62, green: 0.84, blue: 0.94).opacity(0.95)))
        var streak = Path()
        streak.move(to: at(0.55, 0.34))
        streak.addLine(to: at(0.61, 0.31))
        streak.addLine(to: at(0.59, 0.46))
        streak.closeSubpath()
        context.fill(streak, with: .color(.white.opacity(0.6)))

        let rearGlass = Path(
            roundedRect: CGRect(x: width * 0.34, y: height * 0.34, width: width * 0.09, height: height * 0.32),
            cornerRadius: height * 0.05
        )
        context.fill(rearGlass, with: .color(Color(red: 0.45, green: 0.68, blue: 0.8).opacity(0.9)))

        mirror(in: &context, center: at(0.60, 0.2), width: width, height: height)
        mirror(in: &context, center: at(0.60, 0.8), width: width, height: height)

        let spoiler = Path(
            roundedRect: CGRect(x: width * 0.07, y: height * 0.24, width: width * 0.045, height: height * 0.52),
            cornerRadius: width * 0.015
        )
        context.fill(spoiler, with: .color(.black.opacity(0.62)))

        lamp(in: &context, rect: CGRect(x: width * 0.9, y: height * 0.32, width: width * 0.05, height: height * 0.1), color: Color(red: 1, green: 0.96, blue: 0.75))
        lamp(in: &context, rect: CGRect(x: width * 0.9, y: height * 0.58, width: width * 0.05, height: height * 0.1), color: Color(red: 1, green: 0.96, blue: 0.75))
        let tail = braking ? Color(red: 1, green: 0.25, blue: 0.2) : Color(red: 0.72, green: 0.08, blue: 0.1)
        lamp(in: &context, rect: CGRect(x: width * 0.12, y: height * 0.33, width: width * 0.04, height: height * 0.09), color: tail)
        lamp(in: &context, rect: CGRect(x: width * 0.12, y: height * 0.58, width: width * 0.04, height: height * 0.09), color: tail)
        if braking {
            context.fill(
                Path(ellipseIn: CGRect(x: width * 0.08, y: height * 0.30, width: width * 0.08, height: height * 0.12)),
                with: .color(Color.red.opacity(0.35))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: width * 0.08, y: height * 0.58, width: width * 0.08, height: height * 0.12)),
                with: .color(Color.red.opacity(0.35))
            )
        }
    }

    private func bodyPath(width: CGFloat, height: CGFloat) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: width * x, y: height * y)
        }
        var path = Path()
        path.move(to: p(0.14, 0.36))
        path.addCurve(to: p(0.08, 0.5), control1: p(0.07, 0.38), control2: p(0.05, 0.44))
        path.addCurve(to: p(0.14, 0.64), control1: p(0.05, 0.56), control2: p(0.07, 0.62))
        path.addCurve(to: p(0.30, 0.9), control1: p(0.2, 0.78), control2: p(0.24, 0.94))
        path.addCurve(to: p(0.55, 0.78), control1: p(0.38, 0.84), control2: p(0.46, 0.78))
        path.addCurve(to: p(0.74, 0.92), control1: p(0.64, 0.8), control2: p(0.68, 0.96))
        path.addCurve(to: p(0.97, 0.5), control1: p(0.88, 0.84), control2: p(0.99, 0.66))
        path.addCurve(to: p(0.74, 0.08), control1: p(0.99, 0.34), control2: p(0.88, 0.16))
        path.addCurve(to: p(0.55, 0.22), control1: p(0.68, 0.04), control2: p(0.64, 0.2))
        path.addCurve(to: p(0.30, 0.1), control1: p(0.46, 0.22), control2: p(0.38, 0.16))
        path.addCurve(to: p(0.14, 0.36), control1: p(0.24, 0.06), control2: p(0.2, 0.22))
        path.closeSubpath()
        return path
    }

    private func wheel(in context: inout GraphicsContext, center: CGPoint, along: CGFloat, across: CGFloat) {
        let tire = Path(
            roundedRect: CGRect(x: center.x - along / 2, y: center.y - across / 2, width: along, height: across),
            cornerRadius: across * 0.42
        )
        context.fill(tire, with: .color(Color(red: 0.07, green: 0.07, blue: 0.08)))
        context.stroke(tire, with: .color(.white.opacity(0.18)), lineWidth: 0.8)
        let rimRadius = across * 0.34
        let rim = Path(ellipseIn: CGRect(x: center.x - rimRadius, y: center.y - rimRadius, width: rimRadius * 2, height: rimRadius * 2))
        context.fill(rim, with: .color(Color(red: 0.78, green: 0.81, blue: 0.86)))
        var spokes = Path()
        for index in 0..<5 {
            let angle = spin + Double(index) * Double.pi * 2 / 5
            spokes.move(to: center)
            spokes.addLine(to: CGPoint(
                x: center.x + CGFloat(cos(angle)) * rimRadius * 0.78,
                y: center.y + CGFloat(sin(angle)) * rimRadius * 0.78
            ))
        }
        context.stroke(spokes, with: .color(Color(red: 0.22, green: 0.24, blue: 0.28)), lineWidth: max(1, along * 0.07))
        let hub = rimRadius * 0.28
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)),
            with: .color(.white.opacity(0.95))
        )
    }

    private func mirror(in context: inout GraphicsContext, center: CGPoint, width: CGFloat, height: CGFloat) {
        let rect = CGRect(x: center.x - width * 0.035, y: center.y - height * 0.045, width: width * 0.07, height: height * 0.09)
        context.fill(Path(roundedRect: rect, cornerRadius: height * 0.03), with: .color(.black.opacity(0.55)))
        context.fill(
            Path(ellipseIn: rect.insetBy(dx: width * 0.015, dy: height * 0.02)),
            with: .color(Color(red: 0.7, green: 0.84, blue: 0.92))
        )
    }

    private func lamp(in context: inout GraphicsContext, rect: CGRect, color: Color) {
        context.fill(Path(roundedRect: rect, cornerRadius: rect.height * 0.4), with: .color(color))
    }
}

private struct CarBadge: View {
    var number: Int
    var role: CarRole
    var side: CGFloat
    var pulsing: Bool
    @State private var pulse = false

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
            .shadow(color: role == .active ? TrackPalette.active.opacity(pulse ? 0.7 : 0.25) : .clear, radius: pulse ? 12 : 4)
            .scaleEffect(pulsing && pulse ? 1.08 : 1)
            .onAppear { pulse = true }
            .animation(pulsing ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: pulse)
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
