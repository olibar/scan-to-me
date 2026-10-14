// Adds a JPEG scan to the Photos library (add-only permission).
import Foundation
import os
import Photos

enum PhotosSaver {
    private static let log = Logger(subsystem: "com.obarlier.scantome", category: "photos")

    enum PhotosError: Error, LocalizedError {
        case notAuthorized
        var errorDescription: String? { "Photos access was not granted" }
    }

    static func save(jpeg data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        log.debug("photos: authorization \(status.rawValue) bytes=\(data.count)")
        guard status == .authorized || status == .limited else { throw PhotosError.notAuthorized }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
        log.debug("photos: asset created")
    }
}
