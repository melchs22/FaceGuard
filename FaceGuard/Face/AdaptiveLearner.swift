// AdaptiveLearner.swift
// FaceGuard — Silently updates the authorized face profile when a successful match occurs.

import Foundation

final class AdaptiveLearner {

    static let shared = AdaptiveLearner()

    // MARK: - Configuration
    var isEnabled: Bool { Settings.shared.adaptiveLearningEnabled }
    var adaptationRate: Float { Settings.shared.learningSpeedRate }
    let minimumSimilarityToAdapt: Float = 0.75
    let maximumSimilarityToAdapt: Float = 0.88
    let minimumConsecutiveFrames: Int = 10
    let minimumTimeBetweenUpdates: TimeInterval = 1800 // 30 mins

    // MARK: - State
    private var consecutiveSuccessCount: Int = 0
    private var lastAdaptationDate: Date?
    private var pendingEmbeddings: [[Float]] = []
    private let queue = DispatchQueue(label: "com.faceguard.adaptivelearner")

    private init() {}

    // MARK: - Public API

    /// Called on every verified frame. If conditions are met, it adapts the embedding pool.
    func recordSuccessfulFrame(similarity: Float, embedding: [Float], livenessConfirmed: Bool, pool: EmbeddingPool, completion: @escaping (EmbeddingPool?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // 1. Must be enabled and liveness confirmed
            guard self.isEnabled, livenessConfirmed else {
                self.reset()
                completion(nil)
                return
            }

            // 2. Similarity must be in the "sweet spot"
            guard similarity >= self.minimumSimilarityToAdapt && similarity <= self.maximumSimilarityToAdapt else {
                if similarity > self.maximumSimilarityToAdapt {
                    // Perfect match, count it towards consecutive frames but don't save the embedding
                    self.consecutiveSuccessCount += 1
                } else {
                    self.reset()
                }
                completion(nil)
                return
            }

            // 3. Accumulate valid embeddings
            self.consecutiveSuccessCount += 1
            self.pendingEmbeddings.append(embedding)

            // 4. Trigger adaptation if enough consecutive frames are seen
            if self.consecutiveSuccessCount >= self.minimumConsecutiveFrames {
                var modifiedPool = pool
                self.attemptAdaptation(pool: &modifiedPool, avgSimilarity: similarity)
                completion(modifiedPool)
            } else {
                completion(nil)
            }
        }
    }

    func reset() {
        queue.async {
            self.consecutiveSuccessCount = 0
            self.pendingEmbeddings.removeAll()
        }
    }

    // MARK: - Internal Adaptation

    private func attemptAdaptation(pool: inout EmbeddingPool, avgSimilarity: Float) {
        // Prevent adapting too frequently
        if let lastDate = lastAdaptationDate, Date().timeIntervalSince(lastDate) < minimumTimeBetweenUpdates {
            reset()
            return
        }

        // Cap lifetime adaptations
        guard pool.adaptationCount < EmbeddingPool.maxAdaptations else {
            AppLogger.shared.warning("AdaptiveLearner: Reached max lifetime adaptations (500). Please re-enroll.")
            reset()
            return
        }

        // Compute the average of the pending embeddings to get a stable candidate
        guard let candidate = averageEmbeddings(pendingEmbeddings) else {
            reset()
            return
        }

        // Determine if we should add a supplemental or blend with master
        evaluatePromotion(pool: &pool, candidate: candidate, similarity: avgSimilarity)

        lastAdaptationDate = Date()
        AppLogger.shared.info("AdaptiveLearner: Successfully adapted face profile.")
        reset()
    }

    private func evaluatePromotion(pool: inout EmbeddingPool, candidate: [Float], similarity: Float) {
        // If the pool has room, or if the candidate doesn't match the master well enough to blend, add it as a supplemental
        if pool.supplementals.count < EmbeddingPool.maxSupplementals {
            pool.addSupplemental(candidate, scoreAtCapture: similarity)
            AppLogger.shared.info("AdaptiveLearner: Added new supplemental profile.")
        } else {
            // Otherwise, blend it into the master
            pool.adaptMaster(with: candidate, rate: adaptationRate, scoreAtCapture: similarity)
            AppLogger.shared.info("AdaptiveLearner: Blended candidate into master profile.")
        }
    }

    private func averageEmbeddings(_ embeddings: [[Float]]) -> [Float]? {
        guard let first = embeddings.first else { return nil }
        var result = [Float](repeating: 0, count: first.count)
        for emb in embeddings {
            for i in 0..<first.count {
                result[i] += emb[i]
            }
        }
        let countFloat = Float(embeddings.count)
        for i in 0..<result.count {
            result[i] /= countFloat
        }
        return result
    }
}
