import SwiftUI

struct HomeView: View {
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    glyphGrid(GlyphCatalog.letters)
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
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(glyphs) { glyph in
                if glyph.isPlayable {
                    NavigationLink(value: glyph.id) {
                        GlyphTile(glyph: glyph)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(glyph.symbol)
                } else {
                    GlyphTile(glyph: glyph)
                        .accessibilityLabel(glyph.symbol)
                }
            }
        }
    }
}

struct GlyphTile: View {
    let glyph: Glyph
    @State private var pulse = false

    var body: some View {
        Text(glyph.symbol)
            .font(.system(size: 36, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 84)
            .foregroundStyle(glyph.isPlayable ? TrackPalette.ink : TrackPalette.waiting.opacity(0.45))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(glyph.isPlayable ? 0.78 : 0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(glyph.isPlayable ? TrackPalette.active : Color.clear, lineWidth: pulse ? 4 : 1.5)
                    .opacity(glyph.isPlayable ? (pulse ? 1 : 0.4) : 1)
            )
            .scaleEffect(glyph.isPlayable && pulse ? 1.04 : 1)
            .onAppear {
                if glyph.isPlayable {
                    pulse = true
                }
            }
            .animation(
                glyph.isPlayable ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil,
                value: pulse
            )
    }
}
