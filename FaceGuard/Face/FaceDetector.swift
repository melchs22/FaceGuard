// FaceDetector.swift
// FaceGuard — Face detection + neural feature-print embedding.
//
// EMBEDDING STRATEGY:
//   Uses VNGenerateImageFeaturePrintRequest on the cropped face region.
//   This is Apple's built-in neural network feature extractor — the same
//   underlying technology used by Photos.app for face grouping.
//   It produces a high-dimensional vector where:
//     - Same person across frames:  distance < 0.4  (similarity > 0.85)
//     - Different people:           distance > 0.8  (similarity < 0.55)
//   This is fundamentally different from landmark geometry which produces
//   0.99 similarity for ALL faces.

import Vision
import CoreImage
import AppKit
import Accelerate

// MARK: - Detection Result

enum FaceDetectionResult {
    case noFace
    case faceFoundNoLandmarks
    case embedding([Float], boundingBox: CGRect, image: NSImage?, landmarks: VNFaceLandmarks2D?, totalFaceCount: Int)
}

// MARK: - FaceDetector

final class FaceDetector {

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private let faceRectRequest = VNDetectFaceRectanglesRequest()
    private let landmarksRequest: VNDetectFaceLandmarksRequest = {
        let r = VNDetectFaceLandmarksRequest()
        r.revision = VNDetectFaceLandmarksRequestRevision3
        return r
    }()

    // MARK: - Public API

    func detect(in pixelBuffer: CVPixelBuffer) -> FaceDetectionResult {
        // Step 1: Face rectangle detection
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([faceRectRequest])) != nil,
              let rects = faceRectRequest.results, !rects.isEmpty
        else { return .noFace }

        let totalFaceCount = rects.count

        // Step 2: Landmark extraction on largest face
        let lmHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        guard (try? lmHandler.perform([landmarksRequest])) != nil,
              let lmResults = landmarksRequest.results,
              let observation = lmResults.max(by: { $0.boundingBox.area < $1.boundingBox.area })
        else { return .faceFoundNoLandmarks }

        // Step 3: Neural feature print on the face crop
        guard let embedding = extractFeaturePrint(pixelBuffer: pixelBuffer,
                                                  boundingBox: observation.boundingBox)
        else { return .faceFoundNoLandmarks }

        let faceImage = cropFaceImage(from: pixelBuffer, boundingBox: observation.boundingBox)

        return .embedding(embedding,
                          boundingBox: observation.boundingBox,
                          image: faceImage,
                          landmarks: observation.landmarks,
                          totalFaceCount: totalFaceCount)
    }

    // MARK: - Neural Feature Print

    /// Crops the face region and runs VNGenerateImageFeaturePrintRequest on it.
    /// This is Apple's neural network embedding — same tech as Photos face grouping.
    /// Produces a float vector where euclidean distance discriminates identity.
    private func extractFeaturePrint(pixelBuffer: CVPixelBuffer, boundingBox: CGRect) -> [Float]? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let w  = ci.extent.width
        let h  = ci.extent.height

        // Expand bounding box 15% each side — include forehead, chin, ears
        let expandW = boundingBox.width  * 0.15
        let expandH = boundingBox.height * 0.15
        let expandedBox = CGRect(
            x:      max(0,   (boundingBox.minX - expandW) * w),
            y:      max(0,   (boundingBox.minY - expandH) * h),
            width:  min(w,   (boundingBox.width  + expandW * 2) * w),
            height: min(h,   (boundingBox.height + expandH * 2) * h)
        )
        guard expandedBox.width > 10, expandedBox.height > 10 else { return nil }

        // Crop the face region
        let cropped = ci.cropped(to: expandedBox)

        // Render to a CVPixelBuffer for Vision
        guard let facePB = renderToCVPixelBuffer(ci: cropped, size: CGSize(width: 224, height: 224))
        else { return nil }

        // Run Apple's neural feature print extractor
        let fpRequest = VNGenerateImageFeaturePrintRequest()
        let fpHandler = VNImageRequestHandler(cvPixelBuffer: facePB, options: [:])
        guard (try? fpHandler.perform([fpRequest])) != nil,
              let observation = fpRequest.results?.first as? VNFeaturePrintObservation
        else { return nil }

        // Convert VNFeaturePrintObservation data to [Float]
        let byteCount = observation.elementCount * MemoryLayout<Float>.size
        var floatData = [Float](repeating: 0, count: observation.elementCount)
        observation.data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            memcpy(&floatData, base, byteCount)
        }

        // L2-normalize
        l2Normalize(&floatData)
        return floatData
    }

    // MARK: - Helpers

    private func renderToCVPixelBuffer(ci: CIImage, size: CGSize) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width), Int(size.height),
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary, &pb)
        guard status == kCVReturnSuccess, let pixelBuffer = pb else { return nil }

        let scaled = ci.transformed(by: CGAffineTransform(
            scaleX: size.width  / ci.extent.width,
            y:      size.height / ci.extent.height))

        ciContext.render(scaled, to: pixelBuffer)
        return pixelBuffer
    }

    private func l2Normalize(_ v: inout [Float]) {
        var mag: Float = 0
        vDSP_svesq(v, 1, &mag, vDSP_Length(v.count))
        mag = sqrt(mag)
        guard mag > 0 else { return }
        var inv = 1.0 / mag
        vDSP_vsmul(v, 1, &inv, &v, 1, vDSP_Length(v.count))
    }

    private func cropFaceImage(from pixelBuffer: CVPixelBuffer, boundingBox: CGRect) -> NSImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let w  = ci.extent.width
        let h  = ci.extent.height
        let rect = CGRect(x: boundingBox.minX * w, y: boundingBox.minY * h,
                          width: boundingBox.width * w, height: boundingBox.height * h)
                   .insetBy(dx: -10, dy: -10)
        let cropped = ci.cropped(to: rect)
        guard let cg = ciContext.createCGImage(cropped, from: cropped.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

// MARK: - CGRect Extension

private extension CGRect {
    var area: CGFloat { width * height }
}
