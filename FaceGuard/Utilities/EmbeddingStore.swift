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

    // MARK: - Embedding Persistence

    /// Saves the authorised face embedding to disk.
    /// - Parameter embedding: The averaged facial landmark vector to persist.
    func saveEmbedding(_ embedding: [Float]) throws {
        let stored = StoredFaceEmbedding(embedding: embedding)
        let data = try JSONEncoder().encode(stored)
        try data.write(to: embeddingFileURL, options: [.atomic])
        AppLogger.shared.info("Saved face embedding (\(embedding.count) values) to disk.")
    }

    /// Loads the stored authorised face embedding from disk.
    /// - Returns: The stored embedding, or nil if none has been saved.
    func loadEmbedding() -> StoredFaceEmbedding? {
        guard let data = try? Data(contentsOf: embeddingFileURL),
              let stored = try? JSONDecoder().decode(StoredFaceEmbedding.self, from: data)
        else {
            AppLogger.shared.info("No existing face embedding found.")
            return nil
        }
        AppLogger.shared.info("Loaded face embedding (\(stored.embedding.count) values) captured at \(stored.capturedAt).")
        return stored
    }

    /// Deletes the stored embedding and thumbnail from disk.
    func deleteEmbedding() {
        try? FileManager.default.removeItem(at: embeddingFileURL)
        try? FileManager.default.removeItem(at: thumbnailFileURL)
        AppLogger.shared.info("Deleted stored face embedding and thumbnail.")
    }

    /// Returns true if an embedding has been saved.
    var hasStoredEmbedding: Bool {
        FileManager.default.fileExists(atPath: embeddingFileURL.path)
    }

    // MARK: - Thumbnail Persistence

    /// Saves an NSImage as the enrolled face thumbnail.
    func saveThumbnail(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap   = NSBitmapImageRep(data: tiffData),
              let pngData  = bitmap.representation(using: .png, properties: [:]) else {
            AppLogger.shared.error("Failed to convert thumbnail to PNG.")
            return
        }
        try? pngData.write(to: thumbnailFileURL, options: .atomic)
        AppLogger.shared.info("Saved enrolled thumbnail.")
    }

    /// Loads the enrolled face thumbnail from disk.
    func loadThumbnail() -> NSImage? {
        guard FileManager.default.fileExists(atPath: thumbnailFileURL.path),
              let image = NSImage(contentsOf: thumbnailFileURL)
        else { return nil }
        return image
    }

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
    }
}
