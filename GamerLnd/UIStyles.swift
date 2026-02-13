// UIStyles.swift
// Centralized UI sizes/tokens + small reusable UI components.
// THIS PASS:
// • AvatarView now supports optional `avatarURL` (remote image).
// • If no avatar is set, we render a person icon over a deterministic color
//   chosen from the palette: #194185, #F2C25C, #BB6266.
// • AppIconCentered unchanged.

import SwiftUI

// MARK: - Design Tokens

enum UIStyles {
    // Like button (thumbs up)
    struct LikeIcon {
        static let sizeFeed: CGFloat = 18
        static let hitAreaPadding: CGFloat = 6
    }

    // Rating hearts – dynamic sizing handled in HeartRatingBarAligned
    struct RatingHeart {
        static let spacingPrimary: CGFloat = 8
        static let maxSize: CGFloat = 28
        static let minSize: CGFloat = 16
    }

    // Game art
    struct Art {
        static let headerHeight: CGFloat = 190
        static let screenshotHeight: CGFloat = 120
        static let screenshotCorner: CGFloat = 10
    }

    // Search cells
    struct SearchCell {
        static let imageSize: CGFloat = 80
        static let verticalPadding: CGFloat = 10
    }

    // Feed cells
    struct FeedCell {
        static let coverWidth: CGFloat = 100
        static let coverCorner: CGFloat = 12
    }

    // Buttons
    struct Buttons {
        static let primaryCorner: CGFloat = 12
        static let compactHeight: CGFloat = 42
        static let borderWidth: CGFloat = 1
    }
}

// MARK: - Reusable Components

/// App icon component, shown centered in navigation bars.
struct AppIconCentered: View {
    var body: some View {
        Image("icon")
            .resizable()
            .scaledToFill()
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.top, 4)
    }
}

// MARK: - Containers

// MARK: - Avatar

/// Simple avatar view.
/// - If `avatarURL` exists, shows the remote image in a circle.
/// - Else renders a person icon over a palette background chosen deterministically by `name`.
struct AvatarView: View {
    let name: String
    let size: CGFloat
    var avatarURL: String? = nil

    // Default palette: #194185, #F2C25C, #BB6266
    private let palette: [Color] = [
        Color(red: 25/255, green: 65/255, blue: 133/255),
        Color(red: 242/255, green: 194/255, blue: 92/255),
        Color(red: 187/255, green: 98/255, blue: 102/255)
    ]

    var body: some View {
        ZStack {
            Circle().fill(backgroundColor(for: name))

            if let url = avatarURL, !url.isEmpty {
                // Remote avatar image
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView().tint(.white.opacity(0.8))
                    case .failure:
                        fallbackPerson
                    @unknown default:
                        fallbackPerson
                    }
                }
                .clipShape(Circle())
            } else {
                fallbackPerson
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
        .accessibilityLabel(Text("\(name) avatar"))
    }

    private var fallbackPerson: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .padding(size * 0.22)
            .foregroundColor(.white.opacity(0.95))
    }

    private func backgroundColor(for name: String) -> Color {
        // Deterministically pick one of the palette colors based on the name hash.
        let hash = name.unicodeScalars.map { UInt32($0.value) }.reduce(0, +)
        let idx = Int(hash % UInt32(palette.count))
        return palette[idx]
    }
}
