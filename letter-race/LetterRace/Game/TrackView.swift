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
    var onBegin: (LetterPoint, TimeInterval) -> Void
    var onMove: (LetterPoint, TimeInterval) -> Void
    var onEnd: (LetterPoint, TimeInterval) -> Void
    var onCancel: () -> Void

    var body: some View {
        GeometryReader { geo in
            let viewport = LetterViewport(width: geo.size.width, height: geo.size.height)
            ZStack {
                Canvas { context, _ in
                    drawTrack(context: context, viewport: viewport)
                }
                TrackPalette.fail
                    .opacity(model.phase == .failed ? 0.42 : 0)
                    .animation(.easeInOut(duration: 0.3), value: model.phase == .failed)
                    .allowsHitTesting(false)
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
                let carRadius = Double(badgeSide(.active, viewport: viewport)) / viewport.scale / 2
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

    private func badges(viewport: LetterViewport) -> some View {
        let strokes = model.track?.strokes ?? []
        return ForEach(Array(strokes.enumerated()), id: \.element.id) { index, stroke in
            let role = role(for: index)
            CarBadge(
                number: stroke.id,
                role: role,
                side: badgeSide(role, viewport: viewport),
                pulsing: role == .active && model.showsPointer
            )
            .position(badgePosition(index: index, stroke: stroke, viewport: viewport))
            .allowsHitTesting(false)
        }
    }

    private func drawTrack(context: GraphicsContext, viewport: LetterViewport) {
        guard let track = model.track else { return }
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
                width: half * 0.95 * viewport.scale,
                color: TrackPalette.hint.opacity(strength * alpha),
                viewport: viewport,
                context: context
            )
        }
        for (index, stroke) in track.strokes.enumerated() {
            drawGate(stroke, active: index == highlightedIndex, viewport: viewport, context: context)
        }
        for ink in inkPaths() {
            let partial = RoadGeometry.prefix(ink.points, through: ink.progress)
            strokeRoad(
                partial,
                width: max(2.5, viewport.scale * 2.2),
                color: model.phase == .almost ? TrackPalette.active : TrackPalette.ink.opacity(0.9),
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
        dash: [CGFloat]? = nil
    ) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: cg(first, viewport))
        for point in points.dropFirst() {
            path.addLine(to: cg(point, viewport))
        }
        var style = StrokeStyle(lineWidth: CGFloat(width), lineCap: .round, lineJoin: .round)
        if let dash {
            style.dash = dash
        }
        context.stroke(path, with: .color(color), style: style)
    }

    private func drawGate(_ stroke: LetterStroke, active: Bool, viewport: LetterViewport, context: GraphicsContext) {
        guard stroke.centerline.count >= 2 else { return }
        let start = stroke.centerline[stroke.centerline.count - 2]
        let end = stroke.centerline[stroke.centerline.count - 1]
        let angle = atan2(end.y - start.y, end.x - start.x)
        let center = cg(end, viewport)
        let half = CGFloat(viewport.scale * (model.track?.roadHalfWidth ?? 9) * 0.95)
        var path = Path()
        for offset in FinishZone.offsets {
            let along = CGFloat(offset * viewport.scale)
            let cx = center.x + CGFloat(cos(angle)) * along
            let cy = center.y + CGFloat(sin(angle)) * along
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

    /// The ghost of the stroke stays until that car reaches the hatches, then fades out.
    private func hintAlpha(_ index: Int) -> Double {
        switch model.phase {
        case .success, .replaying:
            return 0
        case .driving:
            if index < model.activeStrokeIndex { return 0 }
            if index == model.activeStrokeIndex { return max(0, 1 - motion) }
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
        let base = viewport.scale * (role == .active ? 13.0 : 10.0)
        return CGFloat(max(role == .active ? 36.0 : 28.0, base))
    }

    private func badgePosition(index: Int, stroke: LetterStroke, viewport: LetterViewport) -> CGPoint {
        cg(carPoint(index: index, stroke: stroke), viewport)
    }

    private func carPoint(index: Int, stroke: LetterStroke) -> LetterPoint {
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
