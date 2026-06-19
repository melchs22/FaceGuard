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
    /// The face belongs to the authorised user (score ≥ threshold).
    case authorised(score: Float)
    /// A face was detected but it doesn't match (score < threshold).
    case unauthorised(score: Float)
    /// No face was present in the frame; score is not applicable.
    case noFace
}

// MARK: - FaceMatcher

/// Evaluates whether a live face embedding matches the stored authorised embedding.
final class FaceMatcher {

    // MARK: - Properties

    /// The authorised face embedding, loaded from EmbeddingStore on startup.
    private(set) var authorisedEmbedding: [Float]?

    /// Circular buffer storing the last N similarity scores.
    private var scoreBuffer: [Float] = []

    /// Maximum number of scores to hold in the rolling buffer.
    private var bufferSize: Int { Settings.shared.rollingBufferSize }

    // MARK: - Initialisation

    init() {
        loadEmbedding()
    }

    // MARK: - Embedding Management

    /// Loads the authorised embedding from disk and resets the score buffer.
    func loadEmbedding() {
        if let stored = EmbeddingStore.shared.loadEmbedding() {
            authorisedEmbedding = stored.embedding
            scoreBuffer.removeAll()
            AppLogger.shared.info("FaceMatcher: Authorised embedding loaded (\(stored.embedding.count) floats).")
        } else {
            authorisedEmbedding = nil
            AppLogger.shared.warning("FaceMatcher: No authorised embedding available.")
        }
    }

    /// Updates the authorised embedding directly (e.g., after a fresh enrollment).
    func updateEmbedding(_ embedding: [Float]) {
        authorisedEmbedding = embedding
        scoreBuffer.removeAll()
        AppLogger.shared.info("FaceMatcher: Authorised embedding updated in memory.")
    }

    /// Clears the rolling buffer (e.g., when the app resumes after a pause).
    func resetBuffer() {
        scoreBuffer.removeAll()
    }

    // MARK: - Core Matching

    /// Evaluates a live embedding against the authorised one.
    ///
    /// The decision is based on the rolling average of the last `bufferSize` frames,
    /// not just the single current frame, to prevent single-frame false positives.
    ///
    /// - Parameter liveEmbedding: The embedding extracted from the current camera frame.
    /// - Returns: A MatchDecision representing the rolling-average outcome.
    func evaluate(liveEmbedding: [Float]) -> MatchDecision {
        guard let authorised = authorisedEmbedding else {
            AppLogger.shared.warning("FaceMatcher: evaluate() called but no authorised embedding is loaded.")
            return .noFace
        }

        // Compute cosine similarity for this frame.
        let score = cosineSimilarity(liveEmbedding, authorised)

        // Push to rolling buffer, capping at bufferSize.
        scoreBuffer.append(score)
        if scoreBuffer.count > bufferSize {
            scoreBuffer.removeFirst()
        }

        // Compute rolling average.
        let averageScore = scoreBuffer.reduce(0, +) / Float(scoreBuffer.count)
        let threshold    = Float(Settings.shared.similarityThreshold)

        let decision: MatchDecision
        if averageScore >= threshold {
            decision = .authorised(score: averageScore)
        } else {
            decision = .unauthorised(score: averageScore)
        }

        // Log every decision (verbose — consider removing for production).
        AppLogger.shared.debug("FaceMatcher: raw=\(String(format: "%.3f", score)) avg=\(String(format: "%.3f", averageScore)) → \(decision)")

        return decision
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
        case .authorised(let score):   return "authorised(\(String(format: "%.2f", score)))"
        case .unauthorised(let score): return "unauthorised(\(String(format: "%.2f", score)))"
        case .noFace:                  return "noFace"
        }
    }
}
