// UIStyles.swift
// Centralized UI sizes/tokens + small reusable UI components.
// THIS PASS:
// • AvatarView now supports optional `avatarURL` (remote image).
// • If no avatar is set, we render a person icon over a deterministic color
//   chosen from the palette: #194185, #F2C25C, #BB6266.
// • AppIconCentered unchanged.

import SwiftUI
import UIKit

func formatRatingValue(_ value: Double) -> String {
    let roundedWhole = value.rounded(.towardZero)
    if abs(value - roundedWhole) < 0.0001 {
        return String(Int(roundedWhole))
    }
    return String(format: "%.1f", value)
}

struct HeartValueText: View {
    let text: String
    let size: CGFloat
    var empty: Bool = false

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let offsets: [CGSize] = [
                    CGSize(width: -0.9, height: 0),
                    CGSize(width: 0.9, height: 0),
                    CGSize(width: 0, height: -0.9),
                    CGSize(width: 0, height: 0.9)
                ]
                Text(text)
                    .font(.system(size: max(8, size * 0.315), weight: .heavy, design: .rounded))
                    .foregroundColor(.black.opacity(0.8))
                    .offset(offsets[i])
            }
            Text(text)
                .font(.system(size: max(8, size * 0.315), weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(empty ? 0.82 : 0.99))
                .shadow(color: .black.opacity(0.45), radius: 1.2, x: 0, y: 0.8)
        }
        .minimumScaleFactor(0.55)
        .lineLimit(1)
        .padding(.horizontal, max(2, size * 0.12))
        .offset(y: -max(0.6, size * 0.035))
    }
}

struct RatingHeartBadge: View {
    let value: Double
    var size: CGFloat
    var color: Color? = nil
    var empty: Bool = false

    private var resolvedColor: Color {
        color ?? ColorTheme.ratingBandColor(for: value)
    }

    var body: some View {
        ZStack {
            PixelHeartIcon(
                color: resolvedColor,
                size: size,
                empty: empty,
                perfectScore: !empty && ColorTheme.isPerfectScore(value)
            )
            HeartValueText(
                text: formatRatingValue(value),
                size: size,
                empty: empty
            )
        }
    }
}

struct AverageHeartBadge: View {
    let value: Double
    var size: CGFloat

    var body: some View {
        LayeredHeartIcon(
            baseAssetName: "heart_fill_base",
            overlayAssetName: "gheart_no_color",
            color: ColorTheme.ratingBandColor(for: value),
            size: size,
            perfectScore: ColorTheme.isPerfectScore(value)
        )
        .scaleEffect(1.5)
    }
}

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

struct KeyboardDismissAccessoryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if UIImage(named: "keyboard_down") != nil {
                    Image("keyboard_down")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundColor(ColorTheme.accent)
                } else {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(ColorTheme.accent)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

struct OverlayCloseButton: View {
    var body: some View {
        Image(systemName: "xmark")
            .font(.caption.weight(.bold))
            .foregroundColor(ColorTheme.accent)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(ColorTheme.surface.opacity(0.96))
                    .overlay(
                        Circle()
                            .stroke(ColorTheme.separator, lineWidth: 1)
                    )
            )
            .contentShape(Circle())
    }
}

struct VisualEffectBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemUltraThinMaterialDark

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

struct OverlayBackdrop: View {
    var body: some View {
        ZStack {
            VisualEffectBlur(style: .systemUltraThinMaterialDark)
                .ignoresSafeArea()
            Color.black.opacity(0.36)
                .ignoresSafeArea()
        }
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
                CachedAvatarImage(urlString: url, fallback: AnyView(fallbackPerson))
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

struct PixelHeartIcon: View {
    var color: Color
    var size: CGFloat = 12
    var empty: Bool = false
    var outlined: Bool = true
    var outlineScale: CGFloat = 0.045
    var glossy: Bool = true
    var perfectScore: Bool = false
    @State private var shimmerPhase: CGFloat = -1.1

    var body: some View {
        LayeredHeartIcon(
            baseAssetName: "heart_fill_base",
            overlayAssetName: "heart_no_color",
            color: empty ? color.opacity(0.35) : color,
            size: size,
            perfectScore: perfectScore && !empty
        )
    }
}

private struct LayeredHeartIcon: View {
    let baseAssetName: String
    let overlayAssetName: String
    let color: Color
    let size: CGFloat
    var perfectScore: Bool = false

    var body: some View {
        ZStack {
            if perfectScore {
                AngularGradient(
                    colors: ColorTheme.perfectScoreRainbow + [ColorTheme.perfectScoreRainbow.first ?? .white],
                    center: .center
                )
                .saturation(1.08)
                .mask(baseMask)
            } else {
                baseShape(foreground: color)
            }

            Image(overlayAssetName)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .scaledToFit()
        }
        .scaleEffect(overlayAssetName == "gheart_no_color" ? 1.26 : 1.0)
        .frame(width: size, height: size)
    }

    private func baseShape(foreground: Color) -> some View {
        Image(baseAssetName)
            .renderingMode(.template)
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .scaledToFit()
            .foregroundStyle(foreground)
    }

    private var baseMask: some View {
        Image(baseAssetName)
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .scaledToFit()
    }
}

private final class AvatarImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 40 * 1024 * 1024
        return cache
    }()
    static let fm = FileManager.default
    static let cacheDir: URL = {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("gamerlnd-avatar-cache", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func diskURL(for urlString: String) -> URL {
        let safe = String(urlString.hashValue.magnitude)
        return cacheDir.appendingPathComponent("\(safe).img")
    }
}

enum AvatarCacheManager {
    static func clear() {
        AvatarImageCache.shared.removeAllObjects()
    }
}

private struct CachedAvatarImage: View {
    let urlString: String
    let fallback: AnyView
    @State private var image: UIImage? = nil
    @State private var isLoading: Bool = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView().tint(.white.opacity(0.8))
            } else {
                fallback
            }
        }
        .task(id: urlString) { await load() }
    }

    @MainActor
    private func load() async {
        if let cached = AvatarImageCache.shared.object(forKey: urlString as NSString) {
            image = cached
            return
        }

        let diskURL = AvatarImageCache.diskURL(for: urlString)
        if let data = try? Data(contentsOf: diskURL),
           let ui = UIImage(data: data) {
            AvatarImageCache.shared.setObject(ui, forKey: urlString as NSString)
            image = ui
            return
        }

        guard let url = URL(string: urlString) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let ui = UIImage(data: data) {
                let bytes = Int(ui.size.width * ui.size.height * ui.scale * ui.scale * 4)
                AvatarImageCache.shared.setObject(ui, forKey: urlString as NSString, cost: max(1, bytes))
                try? data.write(to: diskURL, options: .atomic)
                image = ui
            }
        } catch {
            return
        }
    }
}
