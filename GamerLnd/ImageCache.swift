//
//  ImageCache.swift
//  GamerLnd
//
//  Created by Patrick  Flood on 10/14/25.
//


import SwiftUI

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: NSURL) -> UIImage? { cache.object(forKey: url) }
    func set(_ image: UIImage, for url: NSURL) { cache.setObject(image, forKey: url) }
}

struct CachedRemoteImage: View {
    let url: URL
    var cornerRadius: CGFloat = 10

    @State private var uiImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                SkeletonView(cornerRadius: cornerRadius)
                    .onAppear(perform: load)
            }
        }
        .clipped()
    }

    private func load() {
        if let cached = ImageCache.shared.image(for: url as NSURL) {
            uiImage = cached
            return
        }
        guard !isLoading else { return }
        isLoading = true
        let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            ImageCache.shared.set(img, for: url as NSURL)
            DispatchQueue.main.async { self.uiImage = img }
        }.resume()
    }
}
