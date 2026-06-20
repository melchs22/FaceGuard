// FrameProcessor.swift
// FaceGuard — Sits between the camera and the face matching logic.
//
// Responsibilities:
//  • Frame skipping (processes every 3rd frame to reduce CPU load)
//  • Dispatches detection + matching to a low-priority background queue
//  • Manages the "no face" countdown timer
//  • Manages the "stranger cooldown" (unauthorised face must persist for N s before lock)
//  • Multi-face detection → blur (second face nearby = privacy blur)
//  • Full lock when user walks away (no face detected)
//  • Meeting mode — skips all protection when a video call app is running
//  • Auto-pause media when user walks away
//  • Alarm after 3 consecutive unauthorized access events
//  • Notifies MenuBarController and ScreenLocker of status changes

import Foundation
import AppKit
import Vision

// MARK: - Protection Status

/// The current protection state broadcast to the menu bar and rest of the app.
enum ProtectionStatus {
    case authorized(score: Float)
    case unauthorized(score: Float)
    case noFace(secondsRemaining: Double)
    case paused
    case enrolling
    case blurActive   // second face detected nearby
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
    /// Whether media was paused due to no face (resume when user returns).
    private var didPauseMediaForNoFace = false
    /// Whether media was paused due to a second face (resume when second face leaves).
    private var didPauseMediaForSecondFace = false
    
    private let livenessDetector = LivenessDetector()

    // MARK: - Initialisation

    init(faceMatcher: FaceMatcher) {
        self.faceMatcher = faceMatcher
    }

    // MARK: - Public API

    /// Resets all timers. Call when protection resumes after a pause.
    func reset() {
        noFaceStartTime            = nil
        unauthorisedStartTime      = nil
        faceMatcher.resetBuffer()
        livenessDetector.reset()
        frameCounter               = 0
        didPauseMediaForNoFace     = false
        didPauseMediaForSecondFace = false
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
        guard Settings.shared.isProtectionActive else {
            broadcast(.paused)
            return
        }

        if MeetingModeDetector.shared.isMeetingActive {
            broadcast(.paused)
            return
        }

        let detectionResult = faceDetector.detect(in: pixelBuffer)

        switch detectionResult {

        case .noFace:
            unauthorisedStartTime = nil
            AlarmManager.shared.resetFailures()
            livenessDetector.reset()

            if PrivacyBlurWindow.shared.isVisible {
                PrivacyBlurWindow.shared.hide()
                EventLog.shared.record(SecurityEvent(type: .blurDeactivated, details: "No face detected"))
            }
            if didPauseMediaForSecondFace {
                didPauseMediaForSecondFace = false
                MediaController.shared.resumeMedia()
            }
            handleNoFace()

        case .faceFoundNoLandmarks:
            unauthorisedStartTime = nil
            handleNoFace()

        case .embedding(let embedding, _, let image, let landmarks, let totalFaceCount):
            noFaceStartTime = nil
            if didPauseMediaForNoFace {
                didPauseMediaForNoFace = false
                MediaController.shared.resumeMedia()
            }
            
            // 1. Evaluate Liveness
            let liveness = livenessDetector.processFrame(pixelBuffer: pixelBuffer, landmarks: landmarks, embedding: embedding)
            var isSpoof = false
            var livenessConfirmed = false

            switch liveness {
            case .spoof(let reason):
                isSpoof = true
                AppLogger.shared.warning("FrameProcessor: SPOOF DETECTED — \(reason.rawValue)")
            case .live(let confidence):
                livenessConfirmed = true
                AppLogger.shared.debug("FrameProcessor: Liveness confirmed (\(String(format: "%.2f", confidence)))")
            case .inconclusive:
                break // Wait for more frames
            }

            if isSpoof {
                // Only act on spoof if the face is NOT already confirmed as authorized.
                // A 0.99 similarity match is not a photo — liveness is a secondary signal.
                let quickMatch = faceMatcher.evaluate(liveEmbedding: embedding)
                if case .authorised = quickMatch.decision {
                    // Authorized face flagged as spoof — ignore spoof, treat as live.
                    isSpoof = false
                    AppLogger.shared.info("FrameProcessor: Spoof signal overridden by high-confidence match.")
                } else {
                    unauthorisedStartTime = nil
                    if PrivacyBlurWindow.shared.isVisible { PrivacyBlurWindow.shared.hide() }
                    if let img = image { EmbeddingStore.shared.saveIntruderSnapshot(img, reason: "spoof_detected") }
                    AlarmManager.shared.recordUnauthorizedAttempt()
                    onLockRequired?("spoof_detected")
                    broadcast(.unauthorized(score: 0.0))
                    return
                }
            }
            
            // 2. Face Matching
            let match = faceMatcher.evaluate(liveEmbedding: embedding)

            switch match.decision {
            case .authorised(let score, let userSlot):
                unauthorisedStartTime = nil
                AlarmManager.shared.resetFailures()
                
                // 3. Adaptive Learning (only if liveness was fully confirmed)
                if livenessConfirmed {
                    let pool = faceMatcher.authorizedPools[userSlot]
                    
                    AdaptiveLearner.shared.recordSuccessfulFrame(
                        similarity: match.rawScore,
                        embedding: embedding,
                        livenessConfirmed: true,
                        pool: pool
                    ) { [weak self] adaptedPool in
                        guard let self = self, let newPool = adaptedPool else { return }
                        
                        // If AdaptiveLearner returned a modified pool, save it and update FaceMatcher
                        do {
                            try EmbeddingStore.shared.savePool(newPool, forUser: userSlot)
                            // Note: we update faceMatcher on the main/processing queue
                            self.faceMatcher.authorizedPools[userSlot] = newPool
                            AppLogger.shared.info("FrameProcessor: Saved adapted profile for user \(userSlot).")
                        } catch {
                            AppLogger.shared.error("FrameProcessor: Failed to save adapted pool — \(error)")
                        }
                    }
                }

                // Check for secondary faces
                if totalFaceCount > 1 {
                    if !PrivacyBlurWindow.shared.isVisible {
                        PrivacyBlurWindow.shared.show()
                        EventLog.shared.record(SecurityEvent(type: .blurActivated, details: "Secondary face detected"))
                    }
                    if !didPauseMediaForSecondFace {
                        didPauseMediaForSecondFace = true
                        MediaController.shared.pauseMedia()
                    }
                    broadcast(.blurActive)
                } else {
                    if PrivacyBlurWindow.shared.isVisible {
                        PrivacyBlurWindow.shared.hide()
                        EventLog.shared.record(SecurityEvent(type: .blurDeactivated, details: "Authorized user only"))
                    }
                    if didPauseMediaForSecondFace {
                        didPauseMediaForSecondFace = false
                        MediaController.shared.resumeMedia()
                    }
                    broadcast(.authorized(score: score))
                    EventLog.shared.record(SecurityEvent(type: .authorizedAccess))
                }

            case .unauthorised(let score):
                if PrivacyBlurWindow.shared.isVisible { PrivacyBlurWindow.shared.hide() }
                // Reset the score buffer so previous authorized frames don't dilute the signal
                if unauthorisedStartTime == nil { faceMatcher.resetBuffer() }
                handleUnauthorisedFace(score: score, image: image)

            case .noFace:
                handleNoFace()
            }
        }
    }
    // MARK: - No-Face Handling

    private func handleNoFace() {
        let delay = Settings.shared.noFaceLockDelay

        if noFaceStartTime == nil {
            noFaceStartTime = Date()
            if !didPauseMediaForNoFace {
                didPauseMediaForNoFace = true
                MediaController.shared.pauseMedia()
            }
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
            // Show blur immediately so there is visible feedback before the lock triggers
            if !PrivacyBlurWindow.shared.isVisible {
                PrivacyBlurWindow.shared.show()
                EventLog.shared.record(SecurityEvent(type: .blurActivated, details: "Unauthorized face detected"))
            }
            AppLogger.shared.warning("FrameProcessor: Unauthorised face detected (score=\(String(format: "%.2f", score))). Starting cooldown.")
        }

        let elapsed = Date().timeIntervalSince(unauthorisedStartTime!)

        if elapsed >= cooldown {
            unauthorisedStartTime = nil
            PrivacyBlurWindow.shared.hide()
            AppLogger.shared.warning("FrameProcessor: Unauthorised face persisted for \(cooldown)s — triggering lock.")
            // Save snapshot if enabled (silently, in background).
            if let img = image {
                EmbeddingStore.shared.saveIntruderSnapshot(img, reason: "unauthorized_face")
            }
            AlarmManager.shared.recordUnauthorizedAttempt()
            onLockRequired?("unauthorized_face")
        } else {
            broadcast(.unauthorized(score: score))
        }
    }

    // MARK: - Status Broadcasting

    private func broadcast(_ status: ProtectionStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChange?(status)
        }
    }
}
