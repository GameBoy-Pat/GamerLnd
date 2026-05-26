// GameCoverImage.swift
// Unified game cover component with a consistent 3:4 rounded-rectangle style.
// BEGINNERS:
// • IGDB cover/screenshot IDs map to URLs like https://images.igdb.com/igdb/image/upload/t_{size}/{imageId}.jpg
// • We standardize the aspect ratio to 3:4 (width:height) for visual consistency across the app.
// • Use the presets below; avoid ad-hoc sizes so the UI feels cohesive.

import SwiftUI

struct GameCoverImage: View {
    enum Preset {
        // Width x Height (3:4) — pick one look and use it everywhere.
        case tiny     // 48x64
        case small    // 56x75
        case medium   // 84x112
        case large    // 96x128
        case custom(width: CGFloat) // height is computed as width * 4/3
    }

    let id: String
    let preset: Preset
    let cornerRadius: CGFloat

    // MARK: - Initializers

    /// Preferred initializer using presets.
    init(id: String, preset: Preset = .small, cornerRadius: CGFloat = 10) {
        self.id = id
        self.preset = preset
        self.cornerRadius = cornerRadius
    }

    /// Backward-compat convenience (kept for older calls). Height is ignored and recomputed to keep 3:4.
    init(id: String, width: CGFloat, height: CGFloat) {
        self.id = id
        // Convert loose size to nearest preset; still enforce 3:4 and radius 10
        if width <= 52 { self.preset = .tiny }
        else if width <= 70 { self.preset = .small }
        else if width <= 92 { self.preset = .medium }
        else { self.preset = .large }
        self.cornerRadius = 10
    }

    // MARK: - Body

    var body: some View {
        let size = computeSize(for: preset)
        let url = URL(string: "https://images.igdb.com/igdb/image/upload/\(igdbSizeToken(for: size))/\(id).jpg")

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(ColorTheme.surface.opacity(0.4))
                .frame(width: size.width, height: size.height)

            if let url {
                CachedRemoteImage(
                    url: url,
                    cornerRadius: cornerRadius,
                    maxPixel: max(size.width, size.height) * 3
                )
                .frame(width: size.width, height: size.height)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(ColorTheme.background)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(ColorTheme.subtext)
                    )
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    // MARK: - Helpers

    private func computeSize(for preset: Preset) -> CGSize {
        switch preset {
        case .tiny:    return CGSize(width: 48, height: 64)   // 3:4
        case .small:   return CGSize(width: 56, height: 75)   // 3:4
        case .medium:  return CGSize(width: 84, height: 112)  // 3:4
        case .large:   return CGSize(width: 96, height: 128)  // 3:4
        case .custom(let w):
            return CGSize(width: w, height: w * 4.0 / 3.0)
        }
    }

    private func igdbSizeToken(for size: CGSize) -> String {
        let longestEdge = max(size.width, size.height)
        if longestEdge >= 170 {
            return "t_1080p"
        }
        if longestEdge >= 120 {
            return "t_720p"
        }
        return "t_cover_big"
    }
}
