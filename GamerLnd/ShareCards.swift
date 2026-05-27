import SwiftUI
import UIKit
import FirebaseFirestore

struct ShareSheetPayload: Identifiable {
    let id = UUID()
    let title: String
    let image: UIImage
    let items: [Any]
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SharePreviewSheet: View {
    let payload: ShareSheetPayload
    @Environment(\.dismiss) private var dismiss
    @State private var showSystemShare = false

    var body: some View {
        NavigationStack {
            ZStack {
                ShareBackdrop()
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    Text("Preview")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    GeometryReader { geo in
                        ScrollView(showsIndicators: false) {
                            Image(uiImage: payload.image)
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 8)
                                .padding(.bottom, 6)
                        }
                        .frame(height: geo.size.height)
                    }

                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Close")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(ColorTheme.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(ColorTheme.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(ColorTheme.separator, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            showSystemShare = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(ColorTheme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .navigationTitle(payload.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AppIconCentered()
                }
            }
        }
        .sheet(isPresented: $showSystemShare) {
            ActivityShareSheet(activityItems: payload.items)
        }
        .preferredColorScheme(.dark)
    }
}

struct ReviewShareCardRequest {
    let gameTitle: String
    let releaseYear: Int?
    let primaryStudio: String?
    let username: String
    let displayName: String
    let userRating: Double?
    let averageRating: Double?
    let reviewText: String?
    let coverImageId: String?
    let avatarImage: UIImage?
}

struct ShareListEntry: Identifiable {
    let id: String
    let title: String
    let coverImageId: String?
    let rank: Int?
    let tier: String?
}

struct ShareTierPreviewRow: Identifiable {
    let id: String
    let label: String
    let colorHex: String
    let itemTitles: [String]
    let coverImageIds: [String]
}

struct ListShareCardRequest {
    let title: String
    let ownerName: String
    let ownerHandle: String?
    let ownerAvatarImage: UIImage?
    let type: ListType
    let description: String
    let itemCount: Int
    let topEntries: [ShareListEntry]
    let tierPreviewRows: [ShareTierPreviewRow]
}

struct ShareUserIdentity {
    let displayName: String
    let handle: String?
    let avatarURL: String?
}

enum GamerLndShareCardRenderer {
    private static let canvasSize = CGSize(width: 900, height: 900)

    @MainActor
    static func makeReviewSharePayload(request: ReviewShareCardRequest) async -> ShareSheetPayload? {
        let coverImage = await loadCoverImage(imageId: request.coverImageId, size: "t_1080p")
        let card = ReviewShareCardView(request: request, coverImage: coverImage)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(Color.black)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        guard let image = renderer.uiImage else { return nil }
        return ShareSheetPayload(
            title: "Share Game Card",
            image: image,
            items: [image, "Shared from GamerLnd"]
        )
    }

    @MainActor
    static func makeListSharePayload(request: ListShareCardRequest) async -> ShareSheetPayload? {
        let tierCoverIds = request.tierPreviewRows.flatMap(\.coverImageIds)
        let coverIds = Array(Set(request.topEntries.compactMap(\.coverImageId) + tierCoverIds)).prefix(12)
        let coverPairs = await withTaskGroup(of: (String, UIImage?).self, returning: [(String, UIImage?)].self) { group in
            for imageId in coverIds {
                group.addTask {
                    let image = await loadCoverImage(imageId: imageId, size: "t_cover_big")
                    return (imageId, image)
                }
            }
            var results: [(String, UIImage?)] = []
            for await result in group { results.append(result) }
            return results
        }
        let coverImages = Dictionary(uniqueKeysWithValues: coverPairs)

        let card = ListShareCardView(request: request, coverImages: coverImages)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(Color.black)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        guard let image = renderer.uiImage else { return nil }
        return ShareSheetPayload(
            title: "Share List",
            image: image,
            items: [image, "Shared from GamerLnd"]
        )
    }

    static func fetchUserIdentity(userId: String, fallbackName: String) async -> ShareUserIdentity {
        let trimmedFallback = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("users").document(userId).getDocument()
            let data = snap.data() ?? [:]
            let displayName = (data["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let username = (data["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let handle = (data["handle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ShareUserIdentity(
                displayName: (displayName?.isEmpty == false ? displayName! : (username?.isEmpty == false ? username! : (trimmedFallback.isEmpty ? "Gamer" : trimmedFallback))),
                handle: handle?.isEmpty == false ? handle : nil,
                avatarURL: UserRecordAvatarResolver.url(from: data)
            )
        } catch {
            return ShareUserIdentity(displayName: trimmedFallback.isEmpty ? "Gamer" : trimmedFallback, handle: nil, avatarURL: nil)
        }
    }

    static func loadAvatarImage(urlString: String?) async -> UIImage? {
        guard let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if urlString.hasPrefix("data:image"),
           let commaIndex = urlString.firstIndex(of: ","),
           let data = Data(base64Encoded: String(urlString[urlString.index(after: commaIndex)...])),
           let image = UIImage(data: data) {
            return image
        }
        guard let url = URL(string: urlString) else { return nil }
        if let cached = ImageCache.shared.image(for: url as NSURL) {
            return cached
        }
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let image = UIImage(data: data) else { return nil }
            ImageCache.shared.set(image, for: url as NSURL)
            return image
        } catch {
            return nil
        }
    }

    private static func loadCoverImage(imageId: String?, size: String) async -> UIImage? {
        guard let imageId, !imageId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: "https://images.igdb.com/igdb/image/upload/\(size)/\(imageId).jpg") else {
            return nil
        }
        if let cached = ImageCache.shared.image(for: url as NSURL) {
            return cached
        }
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let image = UIImage(data: data) else { return nil }
            ImageCache.shared.set(image, for: url as NSURL)
            return image
        } catch {
            return nil
        }
    }
}

private struct ReviewShareCardView: View {
    let request: ReviewShareCardRequest
    let coverImage: UIImage?

    private var accentColor: Color {
        if let rating = request.userRating, rating > 0 {
            return ColorTheme.ratingBandColor(for: rating)
        }
        return ColorTheme.separator
    }

    private var excerpt: String {
        let text = (request.reviewText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let trimmed = text.replacingOccurrences(of: "\"", with: "”")
        if trimmed.count <= 132 { return "\"\(trimmed)\"" }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 132)
        return "\"\(String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines))...\""
    }

    private var hasReview: Bool {
        !(request.reviewText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ShareCardCanvas {
            VStack(alignment: .leading, spacing: 18) {
                ShareBrandHeader(label: "GAME CARD", compact: false)

                HStack(alignment: .top, spacing: 18) {
                    ShareGameCover(image: coverImage)

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(request.gameTitle)
                                    .font(.system(size: 44, weight: .heavy, design: .default))
                                    .foregroundColor(ColorTheme.text)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.82)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                shareMetaLine
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Rectangle()
                            .fill(accentColor.opacity(0.58))
                            .frame(height: 2)

                        ShareFeedStyleHeart(
                            value: request.userRating.map(formatRatingValue) ?? "—",
                            color: accentColor,
                            size: 164,
                            empty: (request.userRating ?? 0) <= 0
                        )

                        reviewPanel
                    }
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(ColorTheme.surface)
                        .overlay(
                            LinearGradient(
                                colors: [accentColor.opacity(0.20), ColorTheme.surface.opacity(0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(accentColor.opacity(0.46), lineWidth: 1.2)
                        )
                )
                .frame(maxHeight: 560, alignment: .top)

                ShareProfileFooter(
                    avatarImage: request.avatarImage,
                    title: request.displayName,
                    subtitle: "@\(request.username)",
                    rightText: "Your games. Your taste. Your community.",
                    supportingText: "Shared from GamerLnd",
                    compact: false
                )
            }
        }
    }

    private var reviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasReview {
                Text("Review")
                    .font(.system(size: 28, weight: .medium, design: .default))
                    .foregroundColor(accentColor)
                Text(excerpt)
                    .font(.system(size: 28, weight: .medium, design: .default))
                    .foregroundColor(ColorTheme.text.opacity(0.92))
                    .lineSpacing(6)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rate and review on GamerLnd.")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundColor(ColorTheme.text.opacity(0.92))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, minHeight: 152, maxHeight: .infinity, alignment: .topLeading)
    }

    private var shareMetaLine: some View {
        let parts = [
            request.releaseYear.map(String.init),
            request.primaryStudio?.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " • ")

        return Group {
            if parts.isEmpty {
                EmptyView()
            } else {
                Text(parts)
                    .font(.system(size: 21, weight: .semibold, design: .default))
                    .foregroundColor(ColorTheme.subtext)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

}

private struct ListShareCardView: View {
    let request: ListShareCardRequest
    let coverImages: [String: UIImage?]

    private var typeLabel: String {
        switch request.type {
        case .regular: return "LIST"
        case .ranked: return "RANKED LIST"
        case .tiered: return "TIER LIST"
        }
    }

    var body: some View {
        ShareCardCanvas {
            VStack(alignment: .leading, spacing: 16) {
                ShareBrandHeader(label: typeLabel, compact: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title)
                        .font(.system(size: 46, weight: .heavy, design: .default))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    if !request.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(request.description)
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundColor(ColorTheme.subtext)
                            .lineLimit(2)
                    }
                }

                ShareTypeBadge(
                    icon: request.type == .tiered ? "square.stack.3d.up.fill" : (request.type == .ranked ? "trophy.fill" : "list.bullet.rectangle"),
                    title: request.type == .tiered ? "Tiered List" : (request.type == .ranked ? "Ranked List" : "Standard List"),
                    subtitle: request.type == .tiered ? "\(request.tierPreviewRows.count) tiers" : "\(request.itemCount) games"
                )

                if request.type == .tiered {
                    VStack(spacing: 8) {
                        ForEach(Array(request.tierPreviewRows.prefix(5).enumerated()), id: \.element.id) { index, row in
                            ShareTierStripRow(
                                row: row,
                                coverImages: row.coverImageIds.prefix(3).map { coverImages[$0] ?? nil }
                            )
                        }
                    }
                } else {
                    if request.topEntries.count > 5 {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 10) {
                                ForEach(Array(request.topEntries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                                    ShareRankStripRow(
                                        entry: entry,
                                        coverImage: entry.coverImageId.flatMap { coverImages[$0] ?? nil },
                                        index: index,
                                        type: request.type,
                                        compact: true
                                    )
                                }
                            }
                            VStack(spacing: 10) {
                                ForEach(Array(request.topEntries.dropFirst(5).prefix(5).enumerated()), id: \.element.id) { offset, entry in
                                    ShareRankStripRow(
                                        entry: entry,
                                        coverImage: entry.coverImageId.flatMap { coverImages[$0] ?? nil },
                                        index: offset + 5,
                                        type: request.type,
                                        compact: true
                                    )
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(request.topEntries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                                ShareRankStripRow(
                                    entry: entry,
                                    coverImage: entry.coverImageId.flatMap { coverImages[$0] ?? nil },
                                    index: index,
                                    type: request.type,
                                    compact: true
                                )
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                ShareProfileFooter(
                    avatarImage: request.ownerAvatarImage,
                    title: request.ownerName,
                    subtitle: request.ownerHandle.map { "@\($0)" } ?? "Shared from GamerLnd",
                    rightText: request.type == .tiered ? "Create your own tier lists on GamerLnd" : "Create your own lists on GamerLnd",
                    supportingText: "Shared from GamerLnd",
                    compact: true
                )
            }
        }
    }
}

private struct ShareCardCanvas<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            ShareBackdrop()
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(ColorTheme.background.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [ColorTheme.xpGreen.opacity(0.85), ColorTheme.gold.opacity(0.95), ColorTheme.xpGreen.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        .padding(10)
                )
                .shadow(color: ColorTheme.gold.opacity(0.12), radius: 22, x: 0, y: 10)

            content
                .padding(24)
        }
        .padding(16)
    }
}

private struct ShareBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ColorTheme.background, ColorTheme.background.opacity(0.96), ColorTheme.surface.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { geo in
                Path { path in
                    let spacing: CGFloat = 24
                    var x: CGFloat = 0
                    while x <= geo.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        x += spacing
                    }
                    var y: CGFloat = 0
                    while y <= geo.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        y += spacing
                    }
                }
                .stroke(Color.white.opacity(0.025), lineWidth: 0.5)
            }

            RadialGradient(
                colors: [ColorTheme.gold.opacity(0.10), Color.clear],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 220
            )
        }
    }
}

private struct ShareBrandHeader: View {
    let label: String
    var compact: Bool = false

    var body: some View {
        HStack {
            HStack(spacing: compact ? 10 : 12) {
                Image("icon")
                    .resizable()
                    .scaledToFill()
                    .frame(width: compact ? 36 : 54, height: compact ? 36 : 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("GamerLnd")
                    .font(.system(size: compact ? 30 : 46, weight: .heavy, design: .default))
                    .foregroundColor(ColorTheme.text)
            }
            Spacer()
            Text(label)
                .font(.system(size: compact ? 18 : 28, weight: .bold, design: .default))
                .foregroundColor(ColorTheme.gold)
        }
    }
}

private struct ShareGameCover: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(ColorTheme.surface)
                    .overlay(
                        Image("icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 74, height: 74)
                            .opacity(0.7)
                    )
            }
        }
        .frame(width: 332, height: 470)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ColorTheme.gold.opacity(0.7), lineWidth: 1.5)
        )
    }
}

private struct ShareHeroRatingTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 13, weight: .bold, design: .default))
                .foregroundColor(ColorTheme.subtext)

            HStack(spacing: 10) {
                ZStack {
                    PixelHeartIcon(color: color, size: 82, empty: false, perfectScore: ColorTheme.isPerfectScore(Double(value) ?? 0))
                    Text(value)
                        .font(.system(size: 22, weight: .heavy, design: .default))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.45), radius: 0.8, x: 0, y: 0.5)
                        .offset(y: -2)
                }

                Text(value)
                    .font(.system(size: 42, weight: .heavy, design: .default))
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ColorTheme.surface.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ShareFeedStyleHeart: View {
    let value: String
    let color: Color
    let size: CGFloat
    let empty: Bool

    var body: some View {
        ZStack {
            PixelHeartIcon(
                color: empty ? color.opacity(0.35) : color,
                size: size,
                empty: empty,
                perfectScore: !empty && ColorTheme.isPerfectScore(Double(value) ?? 0)
            )

            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    let offsets: [CGSize] = [
                        CGSize(width: -1.6, height: 0),
                        CGSize(width: 1.6, height: 0),
                        CGSize(width: 0, height: -1.6),
                        CGSize(width: 0, height: 1.6)
                    ]
                    Text(value)
                        .font(.system(size: max(18, size * 0.315), weight: .heavy, design: .rounded))
                        .foregroundColor(.black.opacity(0.82))
                        .offset(offsets[i])
                }
                Text(value)
                    .font(.system(size: max(18, size * 0.315), weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(empty ? 0.82 : 0.99))
                    .shadow(color: .black.opacity(0.45), radius: 1.2, x: 0, y: 0.8)
            }
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .padding(.horizontal, max(4, size * 0.12))
            .offset(y: -max(1, size * 0.035))
        }
        .frame(width: size, height: size)
    }
}

private struct ShareTypeBadge: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ColorTheme.gold)
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundColor(ColorTheme.gold)
            Text("•")
                .foregroundColor(ColorTheme.subtext)
            Text(subtitle)
                .font(.system(size: 18, weight: .medium, design: .default))
                .foregroundColor(ColorTheme.subtext)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ColorTheme.surface.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ShareRankStripRow: View {
    let entry: ShareListEntry
    let coverImage: UIImage?
    let index: Int
    let type: ListType
    var compact: Bool = false

    private var label: String {
        if type == .ranked {
            return "#\(entry.rank ?? (index + 1))"
        }
        return "\(index + 1)."
    }

    private var medalColor: Color {
        switch index {
        case 0: return ColorTheme.gold
        case 1: return Color(red: 0.78, green: 0.81, blue: 0.88)
        case 2: return Color(red: 0.73, green: 0.52, blue: 0.36)
        default: return ColorTheme.text
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            if type == .ranked {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(medalColor.opacity(0.12))
                        .frame(width: compact ? 64 : 86, height: compact ? 64 : 86)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(medalColor.opacity(0.55), lineWidth: 1)
                        )
                    VStack(spacing: 4) {
                        if index == 0 && !compact {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(ColorTheme.gold)
                        }
                        Text(label)
                            .font(.system(size: compact ? 22 : 28, weight: .heavy, design: .default))
                            .foregroundColor(medalColor)
                    }
                }
            }

            ShareMiniCover(image: coverImage)

            Text(entry.title)
                .font(.system(size: compact ? 21 : 28, weight: .bold, design: .default))
                .foregroundColor(ColorTheme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: compact ? 92 : 106)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ColorTheme.surface.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ShareTierStripRow: View {
    let row: ShareTierPreviewRow
    let coverImages: [UIImage?]

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(row.label)
                    .font(.system(size: 30, weight: .heavy, design: .default))
                    .foregroundColor(.white)
            }
            .frame(width: 90, height: 90)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorFromHex(row.colorHex))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(colorFromHex(row.colorHex), lineWidth: 1.5)
                    )
            )

            HStack(spacing: 12) {
                if coverImages.isEmpty {
                    Text("No games placed yet")
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .foregroundColor(ColorTheme.subtext)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(coverImages.enumerated()), id: \.offset) { _, image in
                        ShareMiniCover(image: image)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 94)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ColorTheme.surface.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ShareMiniCover: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ColorTheme.background)
                    .overlay(
                        Image("icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .opacity(0.65)
                    )
            }
        }
        .frame(width: 74, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ShareProfileFooter: View {
    let avatarImage: UIImage?
    let title: String
    let subtitle: String
    let rightText: String
    let supportingText: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 18) {
            ShareAvatar(image: avatarImage, fallbackName: title)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: compact ? 25 : 35, weight: .heavy, design: .default))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: compact ? 17 : 23, weight: .medium, design: .default))
                    .foregroundColor(ColorTheme.subtext)
                    .lineLimit(1)
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1, height: compact ? 46 : 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(rightText)
                    .font(.system(size: compact ? 19 : 28, weight: .bold, design: .default))
                    .foregroundColor(ColorTheme.text)
                Text(supportingText)
                    .font(.system(size: compact ? 14 : 20, weight: .semibold, design: .default))
                    .foregroundColor(ColorTheme.xpGreen.opacity(0.92))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.vertical, compact ? 12 : 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ColorTheme.surface.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ShareAvatar: View {
    let image: UIImage?
    let fallbackName: String

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor(for: fallbackName))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .opacity(0.9)
            }
        }
        .frame(width: 68, height: 68)
        .clipShape(Circle())
        .overlay(Circle().stroke(ColorTheme.gold.opacity(0.55), lineWidth: 1.5))
    }

    private func backgroundColor(for name: String) -> Color {
        let palette: [Color] = [
            Color(red: 25/255, green: 65/255, blue: 133/255),
            Color(red: 242/255, green: 194/255, blue: 92/255),
            Color(red: 187/255, green: 98/255, blue: 102/255)
        ]
        let hash = name.unicodeScalars.map { UInt32($0.value) }.reduce(0, +)
        let idx = Int(hash % UInt32(palette.count))
        return palette[idx]
    }
}

private func colorFromHex(_ hex: String) -> Color {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&int)
    let r, g, b: UInt64
    switch cleaned.count {
    case 6:
        (r, g, b) = ((int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
    default:
        (r, g, b) = (120, 120, 120)
    }
    return Color(
        .sRGB,
        red: Double(r) / 255,
        green: Double(g) / 255,
        blue: Double(b) / 255,
        opacity: 1
    )
}
