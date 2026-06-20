// EmbeddingPool.swift
// FaceGuard — Manages multiple face embeddings (master + supplementals) for adaptive learning.

import Foundation

// MARK: - Embedding Source
enum EmbeddingSource: Equatable {
    case master
    case supplemental(index: Int)
}

// MARK: - Adaptation Type
enum AdaptationType: String, Codable {
    case masterUpdated
    case supplementalAdded
    case supplementalPromoted
}

// MARK: - Adaptation Event
struct AdaptationEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    let type: AdaptationType
    let similarityAtTime: Float

    init(type: AdaptationType, similarity: Float) {
        self.id = UUID()
        self.date = Date()
        self.type = type
        self.similarityAtTime = similarity
    }
}

// MARK: - Embedding Pool
struct EmbeddingPool: Codable {
    var master: [Float]
    var supplementals: [[Float]] = []
    var supplementalWinCounts: [Int] = []
    var lastUpdated: Date = Date()
    var totalAuthCount: Int = 0
    var adaptationCount: Int = 0
    var adaptationHistory: [AdaptationEvent] = []

    static let maxSupplementals = 5
    static let maxAdaptations = 500

    // MARK: - Core Functions

    /// Finds the minimum euclidean distance against master and all supplementals.
    /// Lower distance = better match. Returns the best (lowest) distance.
    mutating func bestDistance(for liveEmbedding: [Float]) -> Float {
        var bestDist = euclideanDistance(master, liveEmbedding)
        var bestSource = EmbeddingSource.master

        for (index, supplemental) in supplementals.enumerated() {
            let dist = euclideanDistance(supplemental, liveEmbedding)
            if dist < bestDist {
                bestDist = dist
                bestSource = .supplemental(index: index)
            }
        }

        totalAuthCount += 1
        return bestDist
    }

    /// Legacy cosine similarity entry point — kept for AdaptiveLearner compatibility.
    mutating func bestMatch(for liveEmbedding: [Float]) -> (score: Float, source: EmbeddingSource) {
        // Convert distance to a similarity-like score for legacy callers
        let dist = bestDistance(for: liveEmbedding)
        return (1.0 - min(dist, 1.0), .master)
    }

    /// Adds a new supplemental embedding, evicting the oldest if at capacity.
    mutating func addSupplemental(_ embedding: [Float], scoreAtCapture: Float) {
        if supplementals.count >= Self.maxSupplementals {
            supplementals.removeFirst()
            supplementalWinCounts.removeFirst()
        }
        supplementals.append(embedding)
        supplementalWinCounts.append(0)
        lastUpdated = Date()
        adaptationCount += 1
        adaptationHistory.append(AdaptationEvent(type: .supplementalAdded, similarity: scoreAtCapture))
    }

    /// Promotes a supplemental to master, pushing the old master into supplementals.
    mutating func promote(supplementalAt index: Int, scoreAtCapture: Float) {
        let newMaster = supplementals[index]
        let oldMaster = master

        master = newMaster
        supplementals[index] = oldMaster
        supplementalWinCounts[index] = 0 // Reset win count for demoted master

        lastUpdated = Date()
        adaptationCount += 1
        adaptationHistory.append(AdaptationEvent(type: .supplementalPromoted, similarity: scoreAtCapture))
    }

    /// Blends a new candidate embedding into the master using a weighted average.
    mutating func adaptMaster(with candidate: [Float], rate: Float, scoreAtCapture: Float) {
        // vDSP equivalent: blend arrays
        let count = min(master.count, candidate.count)
        var newMaster = [Float](repeating: 0, count: count)
        for i in 0..<count {
            newMaster[i] = (master[i] * (1 - rate)) + (candidate[i] * rate)
        }
        master = newMaster
        lastUpdated = Date()
        adaptationCount += 1
        adaptationHistory.append(AdaptationEvent(type: .masterUpdated, similarity: scoreAtCapture))
    }

    // MARK: - Distance / Similarity Helpers

    func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        let len = min(a.count, b.count)
        guard len > 0 else { return Float.greatestFiniteMagnitude }
        var sum: Float = 0
        for i in 0..<len { let d = a[i] - b[i]; sum += d * d }
        return sqrt(sum)
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let length = min(a.count, b.count)
        guard length > 0 else { return 0 }

        let dot  = (0..<length).map { a[$0] * b[$0] }.reduce(0, +)
        let magA = sqrt((0..<length).map { a[$0] * a[$0] }.reduce(0, +))
        let magB = sqrt((0..<length).map { b[$0] * b[$0] }.reduce(0, +))

        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }
}
