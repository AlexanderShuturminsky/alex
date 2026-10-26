import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var progress: ProgressStore
    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    StarterStrip(starters: GlyphCatalog.starters, progress: progress.progress)
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(GlyphCatalog.levels) { level in
                            LevelCard(level: level, progress: progress.progress)
                        }
                    }
                    glyphGrid(GlyphCatalog.numbers)
                }
                .padding(20)
                .padding(.top, 8)
            }
            .background(TrackPalette.paper.ignoresSafeArea())
            .navigationDestination(for: String.self) { id in
                if let glyph = GlyphCatalog.glyph(id: id), glyph.isPlayable {
                    RaceView(glyph: glyph)
                }
            }
        }
    }

    private func glyphGrid(_ glyphs: [Glyph]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 12) {
            ForEach(glyphs) { glyph in
                GlyphTile(glyph: glyph, open: false, passes: 0)
                    .accessibilityLabel(glyph.symbol)
            }
        }
    }
}

private struct StarterStrip: View {
    let starters: [Glyph]
    let progress: LevelProgress

    var body: some View {
        HStack(spacing: 14) {
            ForEach(starters) { glyph in
                let open = GlyphCatalog.isStarterUnlocked(glyph, progress: progress)
                let passes = open ? progress.count(for: glyph.id) : 0
                Group {
                    if open {
                        NavigationLink(value: glyph.id) {
                            GlyphTile(glyph: glyph, open: true, passes: passes)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(glyph.symbol)
                    } else {
                        GlyphTile(glyph: glyph, open: false, passes: 0)
                            .accessibilityLabel(glyph.symbol)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(open ? 0.78 : 0.28))
                )
            }
        }
    }
}

private struct LevelCard: View {
    let level: LetterLevel
    let progress: LevelProgress

    private var open: Bool {
        GlyphCatalog.isUnlocked(level, progress: progress)
    }

    var body: some View {
        HStack(spacing: 8) {
            letter(level.capital)
            letter(level.small)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(open ? 0.78 : 0.28))
        )
    }

    @ViewBuilder
    private func letter(_ glyph: Glyph) -> some View {
        let passes = open ? progress.count(for: glyph.id) : 0
        if open {
            NavigationLink(value: glyph.id) {
                GlyphTile(glyph: glyph, open: true, passes: passes)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(glyph.symbol)
        } else {
            GlyphTile(glyph: glyph, open: false, passes: 0)
                .accessibilityLabel(glyph.symbol)
        }
    }
}

struct GlyphTile: View {
    let glyph: Glyph
    var open: Bool
    var passes: Int
    @State private var pulse = false

    private var practicing: Bool {
        open && passes < LevelProgress.required
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if glyph.kind == .shape, let stroke = glyph.track?.strokes.first {
                    StarterShapePreview(points: stroke.centerline)
                        .stroke(
                            open ? TrackPalette.ink : TrackPalette.waiting.opacity(0.45),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 36, height: 36)
                } else {
                    Text(glyph.symbol)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(open ? TrackPalette.ink : TrackPalette.waiting.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            PassDots(filled: passes)
        }
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(practicing ? TrackPalette.active : Color.clear, lineWidth: pulse ? 3 : 1.5)
                .opacity(practicing ? (pulse ? 1 : 0.45) : 1)
        )
        .scaleEffect(practicing && pulse ? 1.03 : 1)
        .onAppear {
            if practicing {
                pulse = true
            }
        }
        .animation(
            practicing ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil,
            value: pulse
        )
    }
}

struct PassDots: View {
    var filled: Int
    var total: Int = LevelProgress.required

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? TrackPalette.active : TrackPalette.waiting.opacity(0.22))
                    .frame(width: 8, height: 4)
                    .scaleEffect(index < filled ? 1 : 0.92)
                    .animation(.easeInOut(duration: 0.35), value: filled)
            }
        }
        .accessibilityLabel("\(min(filled, total)) of \(total)")
    }
}

private struct StarterShapePreview: Shape {
    var points: [LetterPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 100
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 100
        let span = max(maxX - minX, maxY - minY, 1)
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let scale = min(rect.width, rect.height) / CGFloat(span)

        func map(_ pt: LetterPoint) -> CGPoint {
            CGPoint(
                x: rect.midX + CGFloat(pt.x - centerX) * scale,
                y: rect.midY + CGFloat(pt.y - centerY) * scale
            )
        }

        path.move(to: map(first))
        for pt in points.dropFirst() {
            path.addLine(to: map(pt))
        }
        return path
    }
}
