// CameraManager.swift
// FaceGuard — Sets up and manages the AVCaptureSession for the front camera.
//
// Delivers raw CMSampleBuffer frames to whoever sets the `onFrame` callback.
// The camera session runs on its own background serial queue.

import AVFoundation
import AppKit

// MARK: - CameraManager

/// Manages the AVCaptureSession lifecycle and delivers camera frames.
final class CameraManager: NSObject {

    // MARK: - Public Callback

    /// Called on the camera's output serial queue for every captured frame.
    /// The receiver is responsible for processing quickly or dispatching work elsewhere.
    var onFrame: ((CVPixelBuffer) -> Void)?

    // MARK: - AVFoundation Components

    let captureSession = AVCaptureSession()
    private var videoInput:  AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?

    /// Dedicated serial queue for AVCaptureVideoDataOutputSampleBufferDelegate callbacks.
    private let cameraQueue = DispatchQueue(label: "com.faceguard.camera", qos: .userInitiated)

    // MARK: - State

    private(set) var isRunning = false
    private(set) var hasCamera = false

    // MARK: - Initialisation

    override init() {
        super.init()
        AppLogger.shared.info("CameraManager: Initialised.")
    }

    // MARK: - Camera Setup

    /// Configures the capture session with the best available front camera.
    /// Must be called on the main thread after camera permission is granted.
    func setupCamera() {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        // Use medium quality — good enough for face detection while saving CPU.
        captureSession.sessionPreset = .medium

        // Find the front-facing camera (built-in FaceTime HD camera on MacBooks).
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .front)
               ?? AVCaptureDevice.default(for: .video) else {
            AppLogger.shared.error("CameraManager: No camera device found.")
            return
        }

        // Create and add the video input.
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input
            } else {
                AppLogger.shared.error("CameraManager: Cannot add video input.")
                return
            }
        } catch {
            AppLogger.shared.error("CameraManager: Failed to create video input — \(error)")
            return
        }

        // Create and add the video output.
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: cameraQueue)

        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            videoOutput = output
        } else {
            AppLogger.shared.error("CameraManager: Cannot add video output.")
            return
        }

        hasCamera = true
        AppLogger.shared.info("CameraManager: Session configured with device '\(device.localizedName)'.")
    }

    // MARK: - Session Control

    /// Starts the capture session on a background thread.
    func startCapture() {
        guard hasCamera, !isRunning else { return }
        cameraQueue.async { [weak self] in
            self?.captureSession.startRunning()
            self?.isRunning = true
            AppLogger.shared.info("CameraManager: Capture session started.")
        }
    }

    /// Stops the capture session.
    func stopCapture() {
        guard isRunning else { return }
        cameraQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            self?.isRunning = false
            AppLogger.shared.info("CameraManager: Capture session stopped.")
        }
    }

    // MARK: - Permission

    /// Requests camera permission and calls the completion handler on the main thread.
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { completion(true) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            DispatchQueue.main.async { completion(false) }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Receives every frame captured by the session.
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Extract the pixel buffer and forward it to whoever is listening.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didDrop sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Dropped frames are expected when processing is slow — not an error.
    }
}
