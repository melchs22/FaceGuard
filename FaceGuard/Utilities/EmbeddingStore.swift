// EmbeddingStore.swift
// FaceGuard — Persists the authorised user's face embedding and thumbnail to disk.
// Storage location: ~/Library/Application Support/FaceGuard/

import Foundation
import AppKit

// MARK: - Stored Embedding Model

/// Codable container for the authorised face embedding data.
struct StoredFaceEmbedding: Codable {
    /// Flat array of Float32 values representing the normalised facial landmark vector.
    let embedding: [Float]
    /// When this embedding was captured.
    let capturedAt: Date
    /// Schema version for future migrations.
    let version: Int

    init(embedding: [Float], capturedAt: Date = Date(), version: Int = 1) {
        self.embedding   = embedding
        self.capturedAt  = capturedAt
        self.version     = version
    }
}

// MARK: - EmbeddingStore

/// Handles saving and loading of the face embedding and enrolled thumbnail image.
final class EmbeddingStore {

    // MARK: - Singleton

    static let shared = EmbeddingStore()
    private init() {
        setupStorageDirectory()
    }

    // MARK: - File Paths

    private var appSupportURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return base.appendingPathComponent("FaceGuard", isDirectory: true)
    }

    private var embeddingFileURL: URL {
        appSupportURL.appendingPathComponent("authorized_face.json")
    }

    private var thumbnailFileURL: URL {
        appSupportURL.appendingPathComponent("enrolled_thumbnail.png")
    }

    // MARK: - Setup

    private func setupStorageDirectory() {
        try? FileManager.default.createDirectory(at: appSupportURL,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - Multi-User Embedding Paths

    private func embeddingFileURL(for userIndex: Int) -> URL {
        let name = userIndex == 0 ? "authorized_face.json" : "authorized_face_\(userIndex).json"
        return appSupportURL.appendingPathComponent(name)
    }

    private func thumbnailFileURL(for userIndex: Int) -> URL {
        let name = userIndex == 0 ? "enrolled_thumbnail.png" : "enrolled_thumbnail_\(userIndex).png"
        return appSupportURL.appendingPathComponent(name)
    }

    /// Saves an embedding pool for a specific user slot (0 = primary, 1 = secondary).
    func savePool(_ pool: EmbeddingPool, forUser userIndex: Int = 0) throws {
        let data = try JSONEncoder().encode(pool)
        try data.write(to: embeddingFileURL(for: userIndex), options: [.atomic])
        AppLogger.shared.info("Saved EmbeddingPool for user \(userIndex) (Master + \(pool.supplementals.count) supplementals).")
    }

    /// Loads all stored embedding pools (primary + any secondary users).
    /// Automatically migrates old `StoredFaceEmbedding` format to `EmbeddingPool`.
    func loadAllPools() -> [EmbeddingPool] {
        var results: [EmbeddingPool] = []
        for i in 0..<2 {
            let url = embeddingFileURL(for: i)
            guard let data = try? Data(contentsOf: url) else { continue }

            if let pool = try? JSONDecoder().decode(EmbeddingPool.self, from: data) {
                results.append(pool)
            } else if let legacy = try? JSONDecoder().decode(StoredFaceEmbedding.self, from: data) {
                // Migration path: Convert legacy StoredFaceEmbedding to EmbeddingPool
                var newPool = EmbeddingPool(master: legacy.embedding)
                newPool.lastUpdated = legacy.capturedAt
                results.append(newPool)
                
                // Save the migrated pool right away
                try? savePool(newPool, forUser: i)
                AppLogger.shared.info("Migrated legacy face embedding for user \(i) to new EmbeddingPool format.")
            }
        }
        AppLogger.shared.info("Loaded \(results.count) authorized face pool(s).")
        return results
    }

    /// Legacy single load — returns first stored pool.
    func loadPool() -> EmbeddingPool? {
        return loadAllPools().first
    }

    /// Deletes all stored embeddings and thumbnails.
    func deleteEmbedding() {
        for i in 0..<2 {
            try? FileManager.default.removeItem(at: embeddingFileURL(for: i))
            try? FileManager.default.removeItem(at: thumbnailFileURL(for: i))
        }
        AppLogger.shared.info("Deleted all stored face embeddings and thumbnails.")
    }

    /// Returns true if at least one embedding has been saved.
    var hasStoredEmbedding: Bool {
        FileManager.default.fileExists(atPath: embeddingFileURL(for: 0).path)
    }

    // MARK: - Thumbnail Persistence

    /// Saves an NSImage as the enrolled face thumbnail for a given user slot.
    func saveThumbnail(_ image: NSImage, forUser userIndex: Int = 0) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap   = NSBitmapImageRep(data: tiffData),
              let pngData  = bitmap.representation(using: .png, properties: [:]) else {
            AppLogger.shared.error("Failed to convert thumbnail to PNG.")
            return
        }
        try? pngData.write(to: thumbnailFileURL(for: userIndex), options: .atomic)
        AppLogger.shared.info("Saved enrolled thumbnail for user \(userIndex).")
    }

    /// Legacy single-user thumbnail save.
    func saveThumbnail(_ image: NSImage) {
        saveThumbnail(image, forUser: 0)
    }

    /// Loads the enrolled face thumbnail from disk for a given user slot.
    func loadThumbnail(forUser userIndex: Int = 0) -> NSImage? {
        let url = thumbnailFileURL(for: userIndex)
        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url)
        else { return nil }
        return image
    }

    /// Legacy single-user thumbnail load.
    func loadThumbnail() -> NSImage? { loadThumbnail(forUser: 0) }

    // MARK: - Intruder Snapshots

    /// Saves an intruder snapshot to ~/Library/Logs/FaceGuard/intruders/
    /// - Parameters:
    ///   - image: The captured frame image.
    ///   - reason: Reason string for the lock event ("unauthorized_face" / "no_face_timeout").
    func saveIntruderSnapshot(_ image: NSImage, reason: String) {
        guard Settings.shared.saveIntruderSnapshots else { return }

        let dir = AppLogger.shared.intruderDirectoryURL
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "\(formatter.string(from: Date()))_\(reason).png"
        let url  = dir.appendingPathComponent(name)

        guard let tiffData = image.tiffRepresentation,
              let bitmap   = NSBitmapImageRep(data: tiffData),
              let pngData  = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        try? pngData.write(to: url, options: .atomic)
        AppLogger.shared.info("Saved intruder snapshot: \(name)")

        // Record into EventLog
        EventLog.shared.record(SecurityEvent(
            type: reason == "unauthorized_face" ? .unauthorizedFace : .noFaceLock,
            details: reason,
            snapshotFilename: name
        ))
    }
}
