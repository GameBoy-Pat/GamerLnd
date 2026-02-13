// GameScreenshotImage.swift
// Dedicated screenshot renderer (IGDB screenshot sizes).

import SwiftUI

struct GameScreenshotImage: View {
    enum Size {
        case medium   // t_screenshot_med
        case big      // t_screenshot_big
        case hd720    // t_720p
        case hd1080   // t_1080p
        case custom(width: CGFloat)
    }

    let id: String
    let size: Size
    let cornerRadius: CGFloat

    init(id: String, size: Size = .medium, cornerRadius: CGFloat = 10) {
        self.id = id
        self.size = size
        self.cornerRadius = cornerRadius
    }

    private var url: URL? {
        let sizeToken: String
        switch size {
        case .medium: sizeToken = "t_screenshot_med"
        case .big: sizeToken = "t_screenshot_big"
        case .hd720: sizeToken = "t_720p"
        case .hd1080: sizeToken = "t_1080p"
        case .custom:
            sizeToken = "t_screenshot_med"
        }
        return URL(string: "https://images.igdb.com/igdb/image/upload/\(sizeToken)/\(id).jpg")
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty:
                ZStack {
                    ColorTheme.surface
                    ProgressView().tint(ColorTheme.accent)
                }
            case .failure:
                ColorTheme.surface
            @unknown default:
                ColorTheme.surface
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
