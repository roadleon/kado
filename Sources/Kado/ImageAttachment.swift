import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 送信する画像と、画面に残す小さなプレビュー。生成はバックグラウンドで行う。
struct ImageAttachment: Identifiable, Equatable {
    let id: UUID
    let thumbnail: NSImage
    let mediaType: String
    let base64: String

    enum Failure: Error {
        case unreadable, tooLarge

        var notice: String {
            switch self {
            case .unreadable: return L10n.t("この画像は読み込めませんでした", "Couldn’t load this image")
            case .tooLarge: return L10n.t("画像が大きすぎます", "This image is too large")
            }
        }
    }

    init?(image: NSImage) {
        guard let result = try? Self.load(image: image) else { return nil }
        self = result
    }

    init?(url: URL) {
        guard let result = try? Self.load(url: url) else { return nil }
        self = result
    }

    init?(data: Data) {
        guard let result = try? Self.load(data: data) else { return nil }
        self = result
    }

    private init(thumbnail: NSImage, mediaType: String, base64: String) {
        self.id = UUID()
        self.thumbnail = thumbnail
        self.mediaType = mediaType
        self.base64 = base64
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    static func load(image: NSImage) throws -> Self {
        guard let data = image.tiffRepresentation else { throw Failure.unreadable }
        return try load(data: data)
    }

    static func load(url: URL) throws -> Self {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        return try load(data: data)
    }

    static func load(data: Data) throws -> Self {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1568,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else { throw Failure.unreadable }

        // ImageIO は元のピクセル数を見て縮小し、小さい画像は拡大しない。
        let bitmap = NSBitmapImageRep(cgImage: pixels)
        guard var encoded = bitmap.representation(using: .png, properties: [:]) else { throw Failure.unreadable }
        var mediaType = "image/png"
        if encoded.count > 3_500_000 {
            // 透過画像も JPEG では白い背景にする。
            guard let context = CGContext(
                data: nil, width: pixels.width, height: pixels.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { throw Failure.unreadable }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            let rect = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
            context.fill(rect)
            context.draw(pixels, in: rect)
            guard let flattened = context.makeImage(),
                  let jpeg = NSBitmapImageRep(cgImage: flattened).representation(
                    using: .jpeg, properties: [.compressionFactor: 0.85]
                  ) else { throw Failure.unreadable }
            encoded = jpeg
            mediaType = "image/jpeg"
        }
        guard encoded.count <= 4_500_000 else { throw Failure.tooLarge }

        guard let previewSource = CGImageSourceCreateWithData(encoded as CFData, nil),
              let preview = CGImageSourceCreateThumbnailAtIndex(previewSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
              ] as CFDictionary) else { throw Failure.unreadable }
        return Self(
            thumbnail: NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height)),
            mediaType: mediaType, base64: encoded.base64EncodedString()
        )
    }
}

/// 貼り付けとドロップで共通に使う、画像ファイルの判定。
enum ImageTransfer {
    static func isImageURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        return type?.conforms(to: .image) == true
    }

    static func imageURLs(in pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter(isImageURL)
    }

    static func images(in pasteboard: NSPasteboard) -> [NSImage] {
        pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] ?? []
    }
}
