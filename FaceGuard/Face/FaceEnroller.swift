// FaceEnroller.swift
// FaceGuard — Orchestrates multi-phase Face ID-style enrollment.

import Foundation
import AppKit
import CoreImage

// MARK: - Enrollment State

enum EnrollmentPhase: Int, CaseIterable {
    case center = 0
    case leftTilt
    case rightTilt
    case upTilt
    
    var instruction: String {
        switch self {
        case .center:    return "Look straight at the camera"
        case .leftTilt:  return "Slowly tilt your head left"
        case .rightTilt: return "Slowly tilt your head right"
        case .upTilt:    return "Look up slightly"
        }
    }
    
    var totalPhases: Int { 4 }
}

enum EnrollmentState {
    case idle
    case enrolling(progress: Double, phase: EnrollmentPhase, instruction: String)
    case lowLight(progress: Double)
    case success
    case failed(reason: String)
}

// MARK: - FaceEnroller

final class FaceEnroller {

    // MARK: - Configuration

    /// Number of good embeddings to collect PER PHASE.
    private let samplesPerPhase = 5
    private var targetSampleCount: Int { samplesPerPhase * EnrollmentPhase.allCases.count }
    
    private let captureInterval: TimeInterval = 0.15
    private let luminanceThreshold: Float = 0.20
    var userSlot: Int = 0

    // MARK: - Callbacks

    var onStateChange: ((EnrollmentState) -> Void)?
    var onFaceDetected: ((CGRect) -> Void)?
    var onPhaseChange: ((EnrollmentPhase, String) -> Void)?

    // MARK: - Private State

    private let detector = FaceDetector()
    private let ciContext = CIContext(options: nil)

    private var collectedEmbeddings: [[Float]] = []
    private var currentPhaseIndex = 0
    private var phaseSamplesCount = 0
    
    private var lastThumbnail: NSImage?
    private(set) var isEnrolling = false
    private var lastCaptureTime: Date?
    
    private let queue = DispatchQueue(label: "com.faceguard.enrolling", qos: .userInitiated)

    // MARK: - Public API

    func startEnrollment() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.collectedEmbeddings.removeAll()
            self.currentPhaseIndex = 0
            self.phaseSamplesCount = 0
            self.lastThumbnail = nil
            self.isEnrolling   = true
            self.lastCaptureTime = nil

            AppLogger.shared.info("FaceEnroller: Enrollment started.")
            self.notifyPhaseChange()
            self.notifyState(.enrolling(progress: 0, phase: .center, instruction: EnrollmentPhase.center.instruction))
        }
    }

    func cancelEnrollment() {
        isEnrolling = false
        collectedEmbeddings.removeAll()
        notifyState(.idle)
        AppLogger.shared.info("FaceEnroller: Enrollment cancelled.")
    }

    func captureFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isEnrolling else { return }

        if let last = lastCaptureTime, Date().timeIntervalSince(last) < captureInterval { return }

        queue.async { [weak self] in
            guard let self = self, self.isEnrolling else { return }

            let luminance = self.calculateLuminance(of: pixelBuffer)
            let progress = Double(self.collectedEmbeddings.count) / Double(self.targetSampleCount)
            let currentPhase = EnrollmentPhase(rawValue: self.currentPhaseIndex) ?? .center

            if luminance < self.luminanceThreshold {
                self.notifyState(.lowLight(progress: progress))
                return
            }

            let result = self.detector.detect(in: pixelBuffer)
            switch result {
            case .embedding(let embedding, let bbox, let image, _):
                self.lastCaptureTime = Date()
                self.collectedEmbeddings.append(embedding)
                self.phaseSamplesCount += 1
                if let image = image { self.lastThumbnail = image }
                
                DispatchQueue.main.async { self.onFaceDetected?(bbox) }

                // Check phase progression
                if self.phaseSamplesCount >= self.samplesPerPhase {
                    self.currentPhaseIndex += 1
                    self.phaseSamplesCount = 0
                    
                    if self.currentPhaseIndex < EnrollmentPhase.allCases.count {
                        self.notifyPhaseChange()
                    }
                }

                let newProgress = Double(self.collectedEmbeddings.count) / Double(self.targetSampleCount)
                let phase = EnrollmentPhase(rawValue: min(self.currentPhaseIndex, EnrollmentPhase.allCases.count - 1)) ?? .center
                self.notifyState(.enrolling(progress: min(newProgress, 1.0), phase: phase, instruction: phase.instruction))

                if self.collectedEmbeddings.count >= self.targetSampleCount {
                    self.finalise()
                }
                
            case .noFace, .faceFoundNoLandmarks:
                self.notifyState(.enrolling(progress: progress, phase: currentPhase, instruction: currentPhase.instruction))
            }
        }
    }

    // MARK: - Private Helpers

    private func calculateLuminance(of pixelBuffer: CVPixelBuffer) -> Float {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let filter = CIFilter(name: "CIAreaAverage") else { return 1.0 }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        
        guard let outputImage = filter.outputImage else { return 1.0 }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        let r = Float(bitmap[0])
        let g = Float(bitmap[1])
        let b = Float(bitmap[2])
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
    }

    private func notifyPhaseChange() {
        guard let phase = EnrollmentPhase(rawValue: currentPhaseIndex) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onPhaseChange?(phase, phase.instruction)
        }
    }

    private func finalise() {
        guard !collectedEmbeddings.isEmpty else {
            isEnrolling = false
            notifyState(.failed(reason: "No face detected. Please try again."))
            return
        }

        // Average all embeddings to create the master
        let length = collectedEmbeddings.map(\.count).min() ?? 0
        var averaged = [Float](repeating: 0, count: length)
        for emb in collectedEmbeddings {
            for i in 0..<length { averaged[i] += emb[i] }
        }
        averaged = averaged.map { $0 / Float(collectedEmbeddings.count) }

        // Normalise
        let mag = sqrt(averaged.map { $0 * $0 }.reduce(0, +))
        if mag > 0 { averaged = averaged.map { $0 / mag } }

        isEnrolling = false

        // Create the pool instead of raw embedding
        var pool = EmbeddingPool(master: averaged)
        pool.lastUpdated = Date()

        do {
            try EmbeddingStore.shared.savePool(pool, forUser: userSlot)
            if let thumb = lastThumbnail { EmbeddingStore.shared.saveThumbnail(thumb, forUser: userSlot) }
            Settings.shared.hasEnrolled = true
            Settings.shared.authorizedUserCount = max(Settings.shared.authorizedUserCount, userSlot + 1)
            AppLogger.shared.info("FaceEnroller: Enrollment complete (slot \(userSlot)) — 4 phases, \(collectedEmbeddings.count) samples.")
            notifyState(.success)
        } catch {
            AppLogger.shared.error("FaceEnroller: Failed to save pool — \(error)")
            notifyState(.failed(reason: "Failed to save face data. Please try again."))
        }
    }

    private func notifyState(_ state: EnrollmentState) {
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(state)
        }
    }
}
