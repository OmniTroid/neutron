import AppKit
import SwiftUI

@MainActor
private let imageCache = NSCache<NSURL, NSImage>()

/// Loads a local Steam library-cache image off the main thread, with a placeholder until it arrives.
struct SteamImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = imageCache.object(forKey: url as NSURL) {
                image = cached
                return
            }
            let loaded = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
            if let loaded { imageCache.setObject(loaded, forKey: url as NSURL) }
            image = loaded
        }
    }
}
