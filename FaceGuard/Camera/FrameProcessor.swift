// FrameProcessor.swift
// FaceGuard — Sits between the camera and the face matching logic.
//
// Responsibilities:
//  • Frame skipping (processes every 3rd frame to reduce CPU load)
//  • Dispatches detection + matching to a low-priority background queue
//  • Manages the "no face" countdown timer
//  • Manages the "stranger cooldown" (unauthorised face must persist for 2s before lock)
//  • Notifies MenuBarController and ScreenLocker of status changes

import Foundation
import AppKit

// MARK: - Protection Status

/// The current protection state broadcast to the menu bar and rest of the app.
enum ProtectionStatus {
    case authorized(score: Float)
    case unauthorized(score: Float)
    case noFace(secondsRemaining: Double)
    case paused
    case enrolling
}

// MARK: - FrameProcessor

/// Processes camera frames to determine whether the authorised user is present.
final class FrameProcessor {

    // MARK: - Dependencies (set by AppDelegate after init)

    var faceDetector  = FaceDetector()
    var faceMatcher:    FaceMatcher
    var onStatusChange: ((ProtectionStatus) -> Void)?
    var onLockRequired: ((String) -> Void)?   // reason string

    // MARK: - Frame Skipping

    private var frameCounter = 0
    private let frameSkipCount = 3   // Process every 3rd frame (~10 fps at 30 fps input)

    // MARK: - No-Face Timer

    private var noFaceStartTime: Date?

    // MARK: - Stranger Cooldown

    /// When did we first start seeing an unauthorised face continuously?
    private var unauthorisedStartTime: Date?

    // MARK: - Processing Queue

    private let processingQueue = DispatchQueue(label: "com.faceguard.frameprocessor",
                                                qos: .utility)

    // MARK: - State

    private var lastStatus: ProtectionStatus = .noFace(secondsRemaining: 0)

    // MARK: - Initialisation

    init(faceMatcher: FaceMatcher) {
        self.faceMatcher = faceMatcher
    }

    // MARK: - Public API

    /// Resets all timers. Call when protection resumes after a pause.
    func reset() {
        noFaceStartTime       = nil
        unauthorisedStartTime = nil
        faceMatcher.resetBuffer()
        frameCounter = 0
    }

    /// Feed a raw pixel buffer from the camera. Called on the camera queue.
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // Skip frames to reduce CPU usage.
        frameCounter += 1
        guard frameCounter % frameSkipCount == 0 else { return }

        // Dispatch actual processing to the low-priority queue.
        processingQueue.async { [weak self] in
            self?.runDetection(on: pixelBuffer)
        }
    }

    // MARK: - Detection Logic

    private func runDetection(on pixelBuffer: CVPixelBuffer) {
        // If protection is paused, just update the status and bail.
        guard Settings.shared.isProtectionActive else {
            broadcast(.paused)
            return
        }

        let detectionResult = faceDetector.detect(in: pixelBuffer)

        switch detectionResult {

        case .noFace:
            // Reset stranger cooldown since we no longer see any face.
            unauthorisedStartTime = nil
            handleNoFace(image: nil)

        case .faceFoundNoLandmarks:
            // A face is present but landmarks failed — treat conservatively as noFace.
            unauthorisedStartTime = nil
            handleNoFace(image: nil)

        case .embedding(let embedding, _, let image):
            // A face was found with a valid embedding — reset the noFace timer.
            noFaceStartTime = nil

            let decision = faceMatcher.evaluate(liveEmbedding: embedding)

            switch decision {
            case .authorised(let score):
                unauthorisedStartTime = nil
                broadcast(.authorized(score: score))

            case .unauthorised(let score):
                handleUnauthorisedFace(score: score, image: image)

            case .noFace:
                handleNoFace(image: nil)
            }
        }
    }

    // MARK: - No-Face Handling

    private func handleNoFace(image: NSImage?) {
        let delay = Settings.shared.noFaceLockDelay

        if noFaceStartTime == nil {
            noFaceStartTime = Date()
        }

        let elapsed   = Date().timeIntervalSince(noFaceStartTime!)
        let remaining = max(0, delay - elapsed)

        if elapsed >= delay {
            // Grace period exceeded — lock the screen.
            noFaceStartTime = nil
            AppLogger.shared.warning("FrameProcessor: No face for \(Int(delay))s — triggering lock.")
            onLockRequired?("no_face_timeout")
        } else {
            broadcast(.noFace(secondsRemaining: remaining))
        }
    }

    // MARK: - Unauthorised Face Handling

    private func handleUnauthorisedFace(score: Float, image: NSImage?) {
        let cooldown = Settings.shared.strangerCooldownSeconds

        if unauthorisedStartTime == nil {
            unauthorisedStartTime = Date()
            AppLogger.shared.warning("FrameProcessor: Unauthorised face detected (score=\(String(format: "%.2f", score))). Starting cooldown.")
        }

        let elapsed = Date().timeIntervalSince(unauthorisedStartTime!)

        if elapsed >= cooldown {
            unauthorisedStartTime = nil
            AppLogger.shared.warning("FrameProcessor: Unauthorised face persisted for \(cooldown)s — triggering lock.")
            // Save snapshot if enabled.
            if let img = image {
                EmbeddingStore.shared.saveIntruderSnapshot(img, reason: "unauthorized_face")
            }
            onLockRequired?("unauthorized_face")
        } else {
            broadcast(.unauthorized(score: score))
        }
    }

    // MARK: - Status Broadcasting

    private func broadcast(_ status: ProtectionStatus) {
        // Avoid spamming identical updates to keep UI responsive.
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChange?(status)
        }
    }
}
