import Foundation

enum GlyphKind: Equatable {
    case shape
    case letter
    case number
}

struct FinishGate: Equatable {
    var center: LetterPoint
    var radius: Double
}

struct RoadPiece: Equatable {
    var asphalt: [LetterPoint]
    var curb: [LetterPoint]
}

struct GateCell: Equatable {
    var along0: Double
    var across0: Double
    var cellAlong: Double
    var cellAcross: Double
    var isBlack: Bool
}

struct CheckeredGateCache: Equatable {
    var end: LetterPoint
    var heading: LetterPoint
    var half: Double
    var bandStart: Double
    var bandEnd: Double
    var drawsBorder: Bool
    var cells: [GateCell]
}

struct TrackBounds: Equatable {
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double
}

struct LetterStroke: Equatable, Identifiable {
    var id: Int
    var centerline: [LetterPoint]
    var gate: FinishGate
    var isStraight: Bool
    var cumulativeLengths: [Double]
    var totalLength: Double
    var directionMarks: [DirectionMark]
    var middleGuide: [LetterPoint]
    var endPaved: [LetterPoint]

    var start: LetterPoint { centerline[0] }

    init(id: Int, centerline: [LetterPoint], gate: FinishGate) {
        self.id = id
        self.centerline = centerline
        self.gate = gate
        self.isStraight = RoadGeometry.isStraightPolyline(centerline)
        let cumulative = RoadGeometry.cumulativeLengths(centerline)
        self.cumulativeLengths = cumulative
        self.totalLength = cumulative.last ?? 0
        self.directionMarks = RoadGeometry.directionMarks(along: centerline)
        var midLine = centerline
        var endLine = centerline
        if let heading = RoadGeometry.heading(of: centerline, at: 1) {
            midLine.append(LetterPoint(
                x: gate.center.x + heading.x * FinishZone.middleOffset,
                y: gate.center.y + heading.y * FinishZone.middleOffset
            ))
            endLine.append(LetterPoint(
                x: gate.center.x + heading.x * FinishZone.endOffset,
                y: gate.center.y + heading.y * FinishZone.endOffset
            ))
        } else {
            midLine.append(gate.center)
            endLine.append(gate.center)
        }
        self.middleGuide = midLine
        self.endPaved = endLine
    }
}

struct LetterTrack: Equatable {
    var strokes: [LetterStroke]
    var roadHalfWidth: Double
    var cachedBounds: TrackBounds
    var cachedPieces: [RoadPiece]
    var cachedGates: [CheckeredGateCache]

    init(strokes: [LetterStroke], roadHalfWidth: Double) {
        self.strokes = strokes
        self.roadHalfWidth = roadHalfWidth
        self.cachedBounds = RoadGeometry.computeTrackBounds(strokes: strokes, roadHalfWidth: roadHalfWidth)
        let pieces = RoadGeometry.computeRoadPieces(strokes: strokes, half: roadHalfWidth)
        self.cachedPieces = pieces
        let roads = pieces.map(\.asphalt)
        self.cachedGates = strokes.map {
            RoadGeometry.computeCheckeredGate(for: $0, roads: roads, half: roadHalfWidth)
        }
    }
}

struct Glyph: Equatable, Identifiable {
    var id: String
    var symbol: String
    var kind: GlyphKind
    var track: LetterTrack?

    var isPlayable: Bool { track != nil }
}
