// FaceEnroller.swift
// FaceGuard — Orchestrates the face enrollment process.
//
// Enrollment flow:
//  1. Camera frames arrive via captureFrame(_:)
//  2. FaceDetector extracts embeddings from each frame
//  3. After collecting targetSampleCount good embeddings over enrollmentDuration seconds,
//     they are averaged into a single master embedding
//  4. The master embedding is saved via EmbeddingStore
//  5. Completion/failure callbacks notify the EnrollmentView

import Foundation
import AppKit

// MARK: - Enrollment State

/// Represents the current state of the enrollment process.
enum EnrollmentState {
    case idle
    case enrolling(progress: Double, countdown: Int)
    case success
    case failed(reason: String)
}

// MARK: - FaceEnroller

/// Collects multiple face embeddings during enrollment and averages them.
final class FaceEnroller {

    // MARK: - Configuration

    /// Number of good embeddings to collect before computing the master embedding.
    private let targetSampleCount = 10
    /// Total time the enrollment window stays open (seconds).
    private let enrollmentDuration: TimeInterval = 5.0

    // MARK: - Callbacks

    /// Called on the main thread whenever enrollment state changes.
    var onStateChange: ((EnrollmentState) -> Void)?
    /// Called on the main thread when a valid face is detected (for UI overlay).
    var onFaceDetected: ((CGRect) -> Void)?

    // MARK: - Private State

    private let detector = FaceDetector()
    /// Accumulated good embeddings collected so far.
    private var collectedEmbeddings: [[Float]] = []
    /// The last good thumbnail to save as the enrolled face image.
    private var lastThumbnail: NSImage?
    /// Whether enrollment is currently in progress.
    private(set) var isEnrolling = false
    /// When enrollment started.
    private var startTime: Date?
    /// Serial queue for enrollment frame processing.
    private let queue = DispatchQueue(label: "com.faceguard.enrolling", qos: .userInitiated)
    /// Timer that fires the countdown ticks.
    private var countdownTimer: Timer?
    /// Current countdown value displayed in the UI.
    private var countdown: Int = 3

    // MARK: - Public API

    /// Starts the enrollment session. Resets any previous partial state.
    func startEnrollment() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.collectedEmbeddings.removeAll()
            self.lastThumbnail = nil
            self.isEnrolling   = true
            self.startTime     = Date()
            self.countdown     = 3

            AppLogger.shared.info("FaceEnroller: Enrollment started.")
            self.notifyState(.enrolling(progress: 0, countdown: 3))

            // Fire countdown ticks on the main thread.
            DispatchQueue.main.async {
                self.startCountdownTimer()
            }
        }
    }

    /// Stops enrollment immediately without saving.
    func cancelEnrollment() {
        isEnrolling = false
        stopCountdownTimer()
        collectedEmbeddings.removeAll()
        notifyState(.idle)
        AppLogger.shared.info("FaceEnroller: Enrollment cancelled.")
    }

    /// Feed a pixel buffer into the enroller during an active enrollment session.
    /// Should be called on the camera's output queue.
    func captureFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isEnrolling else { return }

        queue.async { [weak self] in
            guard let self = self, self.isEnrolling else { return }

            let result = self.detector.detect(in: pixelBuffer)
            switch result {
            case .embedding(let embedding, let bbox, let image):
                self.collectedEmbeddings.append(embedding)
                if let image = image { self.lastThumbnail = image }
                DispatchQueue.main.async { self.onFaceDetected?(bbox) }

                let progress = Double(self.collectedEmbeddings.count) / Double(self.targetSampleCount)
                self.notifyState(.enrolling(progress: min(progress, 1.0), countdown: self.countdown))

                if self.collectedEmbeddings.count >= self.targetSampleCount {
                    self.finalise()
                }
            case .noFace, .faceFoundNoLandmarks:
                // Don't advance progress; face must be clearly visible.
                break
            }
        }
    }

    // MARK: - Private Helpers

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isEnrolling else { return }
            if self.countdown > 1 {
                self.countdown -= 1
                self.notifyState(.enrolling(
                    progress: Double(self.collectedEmbeddings.count) / Double(self.targetSampleCount),
                    countdown: self.countdown
                ))
            }
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    /// Averages all collected embeddings and saves the result.
    private func finalise() {
        guard !collectedEmbeddings.isEmpty else {
            isEnrolling = false
            stopCountdownTimer()
            notifyState(.failed(reason: "No face detected. Please centre your face and try again."))
            return
        }

        // Average all embeddings element-wise.
        let length = collectedEmbeddings.map(\.count).min() ?? 0
        var averaged = [Float](repeating: 0, count: length)
        for emb in collectedEmbeddings {
            for i in 0..<length { averaged[i] += emb[i] }
        }
        averaged = averaged.map { $0 / Float(collectedEmbeddings.count) }

        // L2-normalise the averaged embedding.
        let mag = sqrt(averaged.map { $0 * $0 }.reduce(0, +))
        if mag > 0 { averaged = averaged.map { $0 / mag } }

        isEnrolling = false
        stopCountdownTimer()

        // Persist to disk.
        do {
            try EmbeddingStore.shared.saveEmbedding(averaged)
            if let thumb = lastThumbnail { EmbeddingStore.shared.saveThumbnail(thumb) }
            Settings.shared.hasEnrolled = true
            AppLogger.shared.info("FaceEnroller: Enrollment complete — \(collectedEmbeddings.count) samples averaged.")
            notifyState(.success)
        } catch {
            AppLogger.shared.error("FaceEnroller: Failed to save embedding — \(error)")
            notifyState(.failed(reason: "Failed to save face data. Please try again."))
        }
    }

    private func notifyState(_ state: EnrollmentState) {
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(state)
        }
    }
}
