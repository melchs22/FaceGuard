// FaceMatcher.swift
// FaceGuard — Compares live face embeddings against enrolled ones.
//
// Uses EUCLIDEAN DISTANCE on VNFeaturePrint vectors (not cosine similarity).
// VNFeaturePrintObservation is designed for euclidean comparison:
//   Same person:      distance < 0.35  → authorized
//   Different person: distance > 0.70  → unauthorized
//
// The threshold stored in Settings is a DISTANCE threshold (lower = stricter).
// Default 0.40 gives good balance between security and usability.

import Foundation

// MARK: - Match Decision

enum MatchDecision {
    case authorised(score: Float, userSlot: Int)
    case unauthorised(score: Float)
    case noFace
}

// MARK: - FaceMatcher

final class FaceMatcher {

    var authorizedPools: [EmbeddingPool] = []

    // Rolling buffer of raw distances (smooths per-frame noise)
    private var distanceBuffer: [Float] = []
    private var bufferSize: Int { Settings.shared.rollingBufferSize }

    init() { loadEmbedding() }

    func loadEmbedding() {
        authorizedPools = EmbeddingStore.shared.loadAllPools()
        distanceBuffer.removeAll()
        if authorizedPools.isEmpty {
            AppLogger.shared.warning("FaceMatcher: No authorised embedding available.")
        } else {
            AppLogger.shared.info("FaceMatcher: \(authorizedPools.count) authorized pool(s) loaded.")
        }
    }

    func updatePools(_ pools: [EmbeddingPool]) {
        authorizedPools = pools
        distanceBuffer.removeAll()
    }

    func resetBuffer() { distanceBuffer.removeAll() }

    // MARK: - Core Matching

    func evaluate(liveEmbedding: [Float]) -> (decision: MatchDecision, rawScore: Float) {
        guard !authorizedPools.isEmpty else { return (.noFace, 1.0) }

        // Find the minimum distance across all pools
        var bestDistance: Float = Float.greatestFiniteMagnitude
        var bestSlot = 0

        for i in 0..<authorizedPools.count {
            let dist = authorizedPools[i].bestDistance(for: liveEmbedding)
            if dist < bestDistance {
                bestDistance = dist
                bestSlot = i
            }
        }

        // Rolling average of distances
        distanceBuffer.append(bestDistance)
        if distanceBuffer.count > bufferSize { distanceBuffer.removeFirst() }
        let avgDistance = distanceBuffer.reduce(0, +) / Float(distanceBuffer.count)

        // Threshold is a distance — LOWER means MORE similar
        let threshold = Float(Settings.shared.similarityThreshold)

        let decision: MatchDecision
        if avgDistance <= threshold {
            decision = .authorised(score: avgDistance, userSlot: bestSlot)
        } else {
            decision = .unauthorised(score: avgDistance)
        }

        AppLogger.shared.debug("FaceMatcher: dist=\(String(format: "%.3f", bestDistance)) avg=\(String(format: "%.3f", avgDistance)) threshold=\(String(format: "%.2f", threshold)) → \(decision)")

        return (decision, bestDistance)
    }

    var currentAverageScore: Float? {
        guard !distanceBuffer.isEmpty else { return nil }
        return distanceBuffer.reduce(0, +) / Float(distanceBuffer.count)
    }
}

// MARK: - CustomDebugStringConvertible

extension MatchDecision: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .authorised(let score, let slot): return "authorised(dist:\(String(format: "%.3f", score)), slot:\(slot))"
        case .unauthorised(let score):         return "unauthorised(dist:\(String(format: "%.3f", score)))"
        case .noFace:                          return "noFace"
        }
    }
}
