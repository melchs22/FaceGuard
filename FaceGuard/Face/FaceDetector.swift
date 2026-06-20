// FaceDetector.swift
// FaceGuard — Runs Vision face detection on a CVPixelBuffer and returns a
// normalised embedding vector based on facial landmark positions.
//
// Approach:
//  1. VNDetectFaceLandmarksRequest produces a VNFaceObservation with 76 landmarks.
//  2. The landmark points are already normalised to the face bounding box (0–1).
//  3. We flatten (x, y) pairs into a [Float] vector — the "embedding".
//  4. Cosine similarity on these vectors is used for identification.

import Vision
import CoreImage
import AppKit

// MARK: - Detection Result

/// The result of processing a single camera frame.
enum FaceDetectionResult {
    /// No face was found in the frame.
    case noFace
    /// A face was found but landmarks could not be extracted (low-quality frame).
    case faceFoundNoLandmarks
    /// A face was found and an embedding was successfully extracted.
    /// totalFaceCount includes all faces detected in the frame.
    case embedding([Float], boundingBox: CGRect, image: NSImage?, landmarks: VNFaceLandmarks2D?, totalFaceCount: Int)
}

// MARK: - FaceDetector

/// Performs Vision-based face detection and landmark extraction on individual frames.
final class FaceDetector {

    // MARK: - Private State

    /// Reusable Vision request for face rectangle detection (fast, lightweight).
    private let faceRectangleRequest = VNDetectFaceRectanglesRequest()

    /// Reusable Vision request for precise facial landmarks (76 points).
    private let landmarksRequest: VNDetectFaceLandmarksRequest = {
        let req = VNDetectFaceLandmarksRequest()
        req.revision = VNDetectFaceLandmarksRequestRevision3
        return req
    }()

    // MARK: - Public API

    /// Processes a pixel buffer and returns the detection result.
    /// Must be called on a background thread — Vision requests are synchronous.
    ///
    /// - Parameter pixelBuffer: A frame from the AVCaptureVideoDataOutput.
    /// - Returns: A FaceDetectionResult describing what was found.
    func detect(in pixelBuffer: CVPixelBuffer) -> FaceDetectionResult {
        // Step 1: Fast face-rectangle check. If no face, return early.
        let rectHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: .up,
                                                options: [:])
        do {
            try rectHandler.perform([faceRectangleRequest])
        } catch {
            AppLogger.shared.error("Face rectangle request failed: \(error)")
            return .noFace
        }

        guard let rectResults = faceRectangleRequest.results,
              !rectResults.isEmpty else {
            return .noFace
        }

        // Step 2: Landmark extraction on the largest (closest) face.
        let landmarkHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                     orientation: .up,
                                                     options: [:])
        do {
            try landmarkHandler.perform([landmarksRequest])
        } catch {
            AppLogger.shared.error("Landmark request failed: \(error)")
            return .faceFoundNoLandmarks
        }

        guard let landmarkResults = landmarksRequest.results,
              let observation = landmarkResults.max(by: { $0.boundingBox.area < $1.boundingBox.area })
        else {
            return .faceFoundNoLandmarks
        }

        // Step 3: Extract embedding from landmarks.
        guard let embedding = buildEmbedding(from: observation) else {
            return .faceFoundNoLandmarks
        }

        // Step 4: Optionally capture a face crop thumbnail for intruder logging.
        let faceImage = cropFaceImage(from: pixelBuffer, boundingBox: observation.boundingBox)

        let totalFaceCount = rectResults.count
        return .embedding(embedding, boundingBox: observation.boundingBox, image: faceImage, landmarks: observation.landmarks, totalFaceCount: totalFaceCount)
    }

    // MARK: - Embedding Construction

    /// Builds a normalised [Float] vector from a VNFaceObservation's landmarks.
    ///
    /// Uses VNFaceLandmarks2D.allPoints (76 points) → 152 floats (x, y alternating).
    /// Points are already normalised to [0,1] relative to the face bounding box,
    /// making the embedding scale- and position-invariant.
    private func buildEmbedding(from observation: VNFaceObservation) -> [Float]? {
        guard let landmarks = observation.landmarks else { return nil }

        // Collect all available landmark groups, filtering nils.
        let regions: [VNFaceLandmarkRegion2D?] = [
            landmarks.allPoints,
            landmarks.faceContour,
            landmarks.leftEye,
            landmarks.rightEye,
            landmarks.leftPupil,
            landmarks.rightPupil,
            landmarks.nose,
            landmarks.noseCrest,
            landmarks.medianLine,
            landmarks.outerLips,
            landmarks.innerLips,
            landmarks.leftEyebrow,
            landmarks.rightEyebrow
        ]

        // Prefer allPoints if available (most complete).
        if let allPoints = landmarks.allPoints,
           allPoints.pointCount > 0 {
            return flattenPoints(allPoints.normalizedPoints)
        }

        // Fallback: concatenate all available landmark groups.
        var combined: [CGPoint] = []
        for region in regions.compactMap({ $0 }) {
            combined.append(contentsOf: region.normalizedPoints)
        }

        guard !combined.isEmpty else { return nil }
        return flattenPoints(combined)
    }

    /// Flattens a [CGPoint] into an alternating [Float] x, y array, then L2-normalises it.
    private func flattenPoints(_ points: [CGPoint]) -> [Float] {
        var vector = points.flatMap { [Float($0.x), Float($0.y)] }
        // L2-normalise so cosine similarity works correctly.
        let magnitude = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        if magnitude > 0 { vector = vector.map { $0 / magnitude } }
        return vector
    }

    // MARK: - Face Crop Thumbnail

    /// Crops the face region from the pixel buffer and returns it as an NSImage.
    private func cropFaceImage(from pixelBuffer: CVPixelBuffer,
                                boundingBox: CGRect) -> NSImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let bufferWidth  = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // Vision bounding boxes use a bottom-left coordinate system.
        let x      = boundingBox.origin.x * bufferWidth
        let y      = boundingBox.origin.y * bufferHeight
        let width  = boundingBox.width  * bufferWidth
        let height = boundingBox.height * bufferHeight
        let cropRect = CGRect(x: x, y: y, width: width, height: height)
            .insetBy(dx: -20, dy: -20) // Add a small margin around the face.

        let cropped = ciImage.cropped(to: cropRect)
        let context = CIContext()
        guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else {
            return nil
        }
        let size  = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }
}

// MARK: - CGRect Extension

private extension CGRect {
    var area: CGFloat { width * height }
}
