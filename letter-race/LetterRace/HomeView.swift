import SwiftUI

struct HomeView: View {
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Letter Race")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(TrackPalette.ink)
                        Text("Trace the road. The cars follow your line.")
                            .font(.system(size: 17, weight: .regular, design: .rounded))
                            .foregroundStyle(TrackPalette.waiting)
                    }

                    glyphSection("Letters", glyphs: GlyphCatalog.letters)
                    glyphSection("Numbers", glyphs: GlyphCatalog.numbers)
                }
                .padding(20)
            }
            .background(TrackPalette.paper.ignoresSafeArea())
            .navigationDestination(for: String.self) { id in
                if let glyph = GlyphCatalog.glyph(id: id), glyph.isPlayable {
                    RaceView(glyph: glyph)
                }
            }
        }
    }

    private func glyphSection(_ title: String, glyphs: [Glyph]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .tracking(1.1)
                .foregroundStyle(TrackPalette.waiting)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(glyphs) { glyph in
                    if glyph.isPlayable {
                        NavigationLink(value: glyph.id) {
                            GlyphTile(glyph: glyph)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(glyph.symbol), race")
                    } else {
                        GlyphTile(glyph: glyph)
                            .accessibilityLabel("\(glyph.symbol), coming soon")
                    }
                }
            }
        }
    }
}

struct GlyphTile: View {
    let glyph: Glyph

    var body: some View {
        VStack(spacing: 4) {
            Text(glyph.symbol)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
            Text(glyph.isPlayable ? "Race" : "Soon")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .foregroundStyle(glyph.isPlayable ? TrackPalette.ink : TrackPalette.waiting.opacity(0.7))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(glyph.isPlayable ? 0.78 : 0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(glyph.isPlayable ? TrackPalette.active : Color.clear, lineWidth: 2)
        )
    }
}
