//
//  ImageCache.swift
//  GamerLnd
//
//  Created by Patrick  Flood on 10/14/25.
//


import SwiftUI
import UIKit
import ImageIO

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 180
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for url: NSURL) -> UIImage? { cache.object(forKey: url) }
    func set(_ image: UIImage, for url: NSURL) {
        let bytes = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url, cost: max(1, bytes))
    }
    func clear() { cache.removeAllObjects() }
}

struct CachedRemoteImage: View {
    let url: URL
    var cornerRadius: CGFloat = 10
    var maxPixel: CGFloat = 320

    @State private var uiImage: UIImage?
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.medium)
                    .antialiased(true)
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                SkeletonView(cornerRadius: cornerRadius)
            }
        }
        .clipped()
        .task(id: url) { load() }
        .onDisappear { loadTask?.cancel() }
    }

    private func load() {
        if let cached = ImageCache.shared.image(for: url as NSURL) {
            uiImage = cached
            return
        }
        guard !isLoading else { return }
        isLoading = true
        loadTask?.cancel()
        loadTask = Task {
            defer { Task { @MainActor in isLoading = false } }
            let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            guard let (data, _) = try? await URLSession.shared.data(for: req) else { return }
            if Task.isCancelled { return }
            let px = Int(max(80, maxPixel))
            let img = downsampledImage(data: data, maxPixel: px) ?? UIImage(data: data)
            guard let img else { return }
            if Task.isCancelled { return }
            await MainActor.run {
                ImageCache.shared.set(img, for: url as NSURL)
                self.uiImage = img
            }
        }
    }

    private func downsampledImage(data: Data, maxPixel: Int) -> UIImage? {
        let options: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let downsampleOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
