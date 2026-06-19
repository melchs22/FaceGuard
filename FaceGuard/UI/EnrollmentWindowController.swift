// EnrollmentWindowController.swift
// FaceGuard — NSWindowController that hosts the SwiftUI EnrollmentView.
// Manages the enrollment window's lifecycle and ties it to the CameraManager.

import AppKit
import SwiftUI

// MARK: - EnrollmentWindowController

final class EnrollmentWindowController: NSWindowController {

    // MARK: - Dependencies

    private let cameraManager: CameraManager
    private let viewModel: EnrollmentViewModel
    /// Called when enrollment completes successfully (so AppDelegate can load the new embedding).
    var onEnrollmentComplete: (() -> Void)?

    // MARK: - Initialisation

    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        self.viewModel     = EnrollmentViewModel()

        // Build the SwiftUI enrollment view.
        let contentView = EnrollmentView(
            viewModel:     viewModel,
            cameraSession: cameraManager.captureSession
        )
        let hostingVC = NSHostingController(rootView: contentView)

        // Configure the window.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
            styleMask:   [.titled, .closable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        window.title          = "FaceGuard — Face Enrollment"
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingVC
        window.center()
        window.level = .floating   // Stay on top during enrollment

        super.init(window: window)

        // Wire ViewModel back-references.
        viewModel.windowController = self

        // Observe enrollment state changes to start/stop the camera and call completion.
        viewModel.enroller.onStateChange = { [weak self] state in
            DispatchQueue.main.async { self?.handleStateChange(state) }
        }
        viewModel.enroller.onFaceDetected = { [weak self] rect in
            DispatchQueue.main.async { self?.viewModel.faceRect = rect }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Public API

    /// Shows the enrollment window and starts the camera if it isn't already running.
    func showAndBeginEnrollment(autoStart: Bool = false) {
        // Route camera frames to the enroller.
        cameraManager.onFrame = { [weak self] pixelBuffer in
            self?.viewModel.enroller.captureFrame(pixelBuffer)
        }

        if !cameraManager.isRunning { cameraManager.startCapture() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if autoStart {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.viewModel.startEnrollment()
            }
        }
    }

    // MARK: - State Handling

    private func handleStateChange(_ state: EnrollmentState) {
        viewModel.state = state

        switch state {
        case .success:
            AppLogger.shared.info("EnrollmentWindowController: Enrollment succeeded.")
            onEnrollmentComplete?()
            // Auto-close after 2 seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.close()
            }
        case .failed(let reason):
            AppLogger.shared.warning("EnrollmentWindowController: Enrollment failed — \(reason)")
        default:
            break
        }
    }

    // MARK: - Window Override

    override func close() {
        viewModel.enroller.cancelEnrollment()
        super.close()
        AppLogger.shared.info("EnrollmentWindowController: Window closed.")
    }
}
