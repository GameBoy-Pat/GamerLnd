// GameActivitySnapshotView.swift
// Small, reusable “activity card” row used in feeds/profile snapshots.
// BEGINNERS:
// • This file also defines a `.cardify()` view modifier so any container can get a card look.
// • If you previously saw “no member 'cardify'”, that’s because the modifier didn’t exist yet.

import SwiftUI

struct GameActivitySnapshotView: View {
    // Minimal model needed to render a snapshot row.
    // Use it anywhere you need a compact row for a game log-like item.
    let gameName: String
    let username: String
    let coverImageId: String?
    let rating: Double?
    let previewText: String? // short review or blurb

    init(gameName: String,
         username: String,
         coverImageId: String? = nil,
         rating: Double? = nil,
         previewText: String? = nil) {
        self.gameName = gameName
        self.username = username
        self.coverImageId = coverImageId
        self.rating = rating
        self.previewText = previewText
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let img = coverImageId {
                GameCoverImage(id: img, preset: .medium, cornerRadius: 10)
            } else {
                // Placeholder if no cover is available
                RoundedRectangle(cornerRadius: 10)
                    .fill(ColorTheme.separator.opacity(0.3))
                    .frame(width: 80, height: 106)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(gameName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)

                Text(username)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)

                if let txt = previewText, !txt.isEmpty {
                    Text(txt)
                        .font(.footnote)
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(2)
                }

                if let r = rating {
                    RatingHeartBadge(value: r, size: 22)
                }
            }
            Spacer(minLength: 0)
        }
        .cardify() // ← shared card styling defined below
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Cardify View Modifier (shared)

/// A small helper to give any view a card look (surface background + border).
/// Use: `someView.cardify()` or with custom radius: `.cardify(cornerRadius: 16)`
extension View {
    func cardify(cornerRadius: CGFloat = 12) -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(ColorTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(ColorTheme.separator, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Preview

#if DEBUG
struct GameActivitySnapshotView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            GameActivitySnapshotView(
                gameName: "The Legend of Zelda: Tears of the Kingdom",
                username: "patrick",
                coverImageId: "co1abc123",
                rating: 9.4,
                previewText: "Massive and inventive. The fuse system makes every shrine feel fresh."
            )
            GameActivitySnapshotView(
                gameName: "Stardew Valley",
                username: "alex",
                coverImageId: nil,
                rating: nil,
                previewText: "Cozy farming vibes 🌾"
            )
        }
        .padding()
        .background(ColorTheme.background.ignoresSafeArea())
        .preferredColorScheme(ColorTheme.preferredScheme)
    }
}
#endif
