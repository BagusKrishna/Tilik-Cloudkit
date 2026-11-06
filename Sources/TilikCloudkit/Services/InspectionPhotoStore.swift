#if os(iOS)
//
//  InspectionPhotoStore.swift
//  Tilik
//
//  Created by Amalia Sandi Alzahrah on 28/10/26.
//

import CryptoKit
import Foundation
import UIKit

/// Files for inspection photos: the outbox copy that is uploaded, and a cache so a
/// photo is downloaded from CloudKit only once per device.
public enum InspectionPhotoStore {
    /// Longest side of the uploaded JPEG and its quality (≈300–700 KB).
    static let maximumPixelSide: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.7

    /// Re-renders the photo (drops EXIF incl. GPS) and compresses it to JPEG.
    public static func compressedJPEG(from image: UIImage) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maximumPixelSide / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: jpegQuality)
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Durable copy kept until CloudKit confirms the response (survives app restarts).
    public static func stageForUpload(_ data: Data, responseID: String) throws -> String {
        let directory = URL.applicationSupportDirectory
            .appendingPathComponent("Collaboration/InspectionPhotos/" + responseID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("photo.jpg")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return url.path
    }

    public static func discardStaged(path: String) {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
    }

    // MARK: Cache (viewing)

    private static var cacheDirectory: URL {
        URL.cachesDirectory.appendingPathComponent("TilikInspectionPhotos", isDirectory: true)
    }

    private static func cacheURL(responseID: String) -> URL {
        // Response IDs are UUID strings; keep only safe file-name characters.
        let safe = responseID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return cacheDirectory.appendingPathComponent(safe + ".jpg")
    }

    public static func cachedImage(responseID: String) -> UIImage? {
        guard let data = try? Data(contentsOf: cacheURL(responseID: responseID)) else { return nil }
        return UIImage(data: data)
    }

    public static func cache(_ data: Data, responseID: String) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL(responseID: responseID), options: .atomic)
    }
}

#endif
