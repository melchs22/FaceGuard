// FaceMatcher.swift
// FaceGuard — Compares a live face embedding against the authorised one.
//
// Uses cosine similarity on the normalised landmark vectors.
// Maintains a rolling buffer of the last N similarity scores to smooth out
// per-frame noise and reduce false positives.

import Foundation

// MARK: - Match Decision

/// The outcome of a face match evaluation.
enum MatchDecision {
    /// The face belongs to an authorised user.
    case authorised(score: Float, userSlot: Int)
    /// A face was detected but it doesn't match (score < threshold).
    case unauthorised(score: Float)
    /// No face was present in the frame.
    case noFace
}

// MARK: - FaceMatcher

/// Evaluates whether a live face embedding matches the stored authorised embedding.
final class FaceMatcher {

    // MARK: - Properties

    /// All authorized face embedding pools (primary + secondary users).
    var authorizedPools: [EmbeddingPool] = []

    /// Circular buffer storing the last N similarity scores.
    private var scoreBuffer: [Float] = []

    /// Maximum number of scores to hold in the rolling buffer.
    private var bufferSize: Int { Settings.shared.rollingBufferSize }

    // MARK: - Initialisation

    init() {
        loadEmbedding()
    }

    // MARK: - Embedding Management

    /// Loads all authorized pools from disk and resets the score buffer.
    func loadEmbedding() {
        authorizedPools = EmbeddingStore.shared.loadAllPools()
        scoreBuffer.removeAll()
        if authorizedPools.isEmpty {
            AppLogger.shared.warning("FaceMatcher: No authorised embedding available.")
        } else {
            AppLogger.shared.info("FaceMatcher: \(authorizedPools.count) authorized pool(s) loaded.")
        }
    }

    /// Updates the authorized pools directly (e.g., after a fresh enrollment or adaptation).
    func updatePools(_ pools: [EmbeddingPool]) {
        self.authorizedPools = pools
        scoreBuffer.removeAll()
        AppLogger.shared.info("FaceMatcher: Pools updated in memory.")
    }

    /// Clears the rolling buffer (e.g., when the app resumes after a pause).
    func resetBuffer() {
        scoreBuffer.removeAll()
    }

    // MARK: - Core Matching

    /// Evaluates a live embedding against all authorized pools.
    /// Returns the MatchDecision and the raw highest similarity score found.
    func evaluate(liveEmbedding: [Float]) -> (decision: MatchDecision, rawScore: Float) {
        guard !authorizedPools.isEmpty else {
            AppLogger.shared.warning("FaceMatcher: evaluate() called but no authorised embedding is loaded.")
            return (.noFace, 0)
        }

        // Find the best score across all pools (and all supplementals within those pools)
        var bestScore: Float = 0
        var bestUserSlot: Int = 0
        
        for i in 0..<authorizedPools.count {
            let result = authorizedPools[i].bestMatch(for: liveEmbedding)
            if result.score > bestScore {
                bestScore = result.score
                bestUserSlot = i
            }
        }

        // Push to rolling buffer, capping at bufferSize.
        scoreBuffer.append(bestScore)
        if scoreBuffer.count > bufferSize {
            scoreBuffer.removeFirst()
        }

        // Compute rolling average.
        let averageScore = scoreBuffer.reduce(0, +) / Float(scoreBuffer.count)
        let threshold    = Float(Settings.shared.similarityThreshold)

        let decision: MatchDecision
        if averageScore >= threshold {
            decision = .authorised(score: averageScore, userSlot: bestUserSlot)
        } else {
            decision = .unauthorised(score: averageScore)
        }


        AppLogger.shared.debug("FaceMatcher: raw=\(String(format: "%.3f", bestScore)) avg=\(String(format: "%.3f", averageScore)) → \(decision)")

        return (decision, bestScore)
    }


    // MARK: - Similarity Maths

    /// Computes the cosine similarity between two equal-length float vectors.
    ///
    /// Result range: -1.0 (opposite) to 1.0 (identical).
    /// For normalised vectors this is equivalent to the dot product.
    ///
    /// - Parameters:
    ///   - a: First vector (should be L2-normalised).
    ///   - b: Second vector (should be L2-normalised).
    /// - Returns: Cosine similarity score in [-1, 1].
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        // Handle vector length mismatch gracefully by truncating to the shorter length.
        let length = min(a.count, b.count)
        guard length > 0 else { return 0 }

        let dot  = (0..<length).map { a[$0] * b[$0] }.reduce(0, +)
        let magA = sqrt((0..<length).map { a[$0] * a[$0] }.reduce(0, +))
        let magB = sqrt((0..<length).map { b[$0] * b[$0] }.reduce(0, +))

        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    /// Returns the current rolling average score for display in the menu.
    var currentAverageScore: Float? {
        guard !scoreBuffer.isEmpty else { return nil }
        return scoreBuffer.reduce(0, +) / Float(scoreBuffer.count)
    }
}

// MARK: - CustomDebugStringConvertible

extension MatchDecision: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .authorised(let score, let userSlot): return "authorised(score: \(String(format: "%.2f", score)), slot: \(userSlot))"
        case .unauthorised(let score):             return "unauthorised(\(String(format: "%.2f", score)))"
        case .noFace:                              return "noFace"
        }
    }
}
