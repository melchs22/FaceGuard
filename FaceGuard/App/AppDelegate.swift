// AppDelegate.swift
// FaceGuard — Application entry point.
//
// Wires together all subsystems:
//   CameraManager → FrameProcessor → FaceMatcher → MenuBarController / ScreenLocker
//
// Startup sequence:
//   1. Set activation policy to .accessory (no dock icon)
//   2. Request camera permission
//   3. If not enrolled → open enrollment window
//   4. If enrolled → start protection immediately

import AppKit
import AVFoundation
import ServiceManagement

// MARK: - AppDelegate

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Core Subsystems

    private let cameraManager   = CameraManager()
    private let faceMatcher     = FaceMatcher()
    private lazy var frameProcessor = FrameProcessor(faceMatcher: faceMatcher)

    // MARK: - UI Controllers

    private var menuBarController:        MenuBarController!
    private var enrollmentWindowController: EnrollmentWindowController!
    private var preferencesWindowController: PreferencesWindowController!

    // MARK: - Global Event Monitor (panic shortcut)

    private var globalEventMonitor: Any?

    // MARK: - Pause Timer

    private var pauseCheckTimer: Timer?

    // MARK: - applicationDidFinishLaunching

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — we're a menu bar-only app.
        NSApp.setActivationPolicy(.accessory)

        AppLogger.shared.info("FaceGuard: Application launched.")

        // Set up subsystems
        setupMenuBar()
        setupPreferencesWindow()
        setupNotificationObservers()
        setupPanicShortcut()
        startPauseCheckTimer()

        // Request camera permission, then continue startup.
        CameraManager.requestPermission { [weak self] granted in
            guard let self = self else { return }
            if granted {
                AppLogger.shared.info("AppDelegate: Camera permission granted.")
                self.cameraManager.setupCamera()
                self.proceedAfterPermission()
            } else {
                AppLogger.shared.error("AppDelegate: Camera permission denied.")
                self.showPermissionDeniedAlert()
            }
        }
    }

    // MARK: - Post-Permission Startup

    private func proceedAfterPermission() {
        if Settings.shared.hasEnrolled && EmbeddingStore.shared.hasStoredEmbedding {
            // Existing user — load embedding and start protection.
            AppLogger.shared.info("AppDelegate: Existing enrollment found. Starting protection.")
            startProtection()
        } else {
            // First launch — run enrollment.
            AppLogger.shared.info("AppDelegate: No enrollment found. Opening enrollment window.")
            openEnrollmentWindow(autoStart: true)
        }
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        menuBarController = MenuBarController()

        menuBarController.onReEnroll = { [weak self] in
            self?.openEnrollmentWindow(autoStart: false)
        }
        menuBarController.onPause = { [weak self] minutes in
            guard let self = self else { return }
            Settings.shared.pauseProtection(forMinutes: minutes)
            self.frameProcessor.reset()
            self.menuBarController.updateStatus(.paused)
            let label = minutes.map { "\($0) min" } ?? "indefinitely"
            AppLogger.shared.info("AppDelegate: Protection paused \(label).")
        }
        menuBarController.onResume = { [weak self] in
            guard let self = self else { return }
            Settings.shared.resumeProtection()
            self.frameProcessor.reset()
            AppLogger.shared.info("AppDelegate: Protection resumed.")
        }
        menuBarController.onViewLog = {
            AppLogger.shared.openLogDirectoryInFinder()
        }
        menuBarController.onPreferences = { [weak self] in
            self?.preferencesWindowController.showPreferences()
        }
        menuBarController.onQuit = {
            AppLogger.shared.info("AppDelegate: User requested quit.")
            NSApp.terminate(nil)
        }
    }

    // MARK: - Preferences Window

    private func setupPreferencesWindow() {
        preferencesWindowController = PreferencesWindowController()
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenEnrollment),
            name:     .openEnrollmentWindow,
            object:   nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenPreferences),
            name:     .openPreferencesWindow,
            object:   nil
        )
    }

    @objc private func handleOpenEnrollment() {
        openEnrollmentWindow(autoStart: false)
    }

    @objc private func handleOpenPreferences() {
        preferencesWindowController.showPreferences()
    }

    // MARK: - Panic Shortcut (⌘ + Shift + L)

    private func setupPanicShortcut() {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // ⌘ + Shift + L
            if event.modifierFlags.contains([.command, .shift]),
               event.charactersIgnoringModifiers?.lowercased() == "l" {
                ScreenLocker.shared.panicLock()
            }
        }
    }

    // MARK: - Protection Flow

    private func startProtection() {
        // Load the authorised embedding into the matcher.
        faceMatcher.loadEmbedding()

        // Route camera frames to FrameProcessor.
        cameraManager.onFrame = { [weak self] pixelBuffer in
            self?.frameProcessor.processFrame(pixelBuffer)
        }

        // FrameProcessor tells us what it sees.
        frameProcessor.onStatusChange = { [weak self] status in
            self?.menuBarController.updateStatus(status)
        }

        // FrameProcessor triggers a lock when needed.
        frameProcessor.onLockRequired = { [weak self] reason in
            guard let self = self else { return }
            // Only lock if protection is still active (not paused).
            guard Settings.shared.isProtectionActive else { return }
            ScreenLocker.shared.lock(reason: reason)
        }

        cameraManager.startCapture()
        menuBarController.updateStatus(.noFace(secondsRemaining: Settings.shared.noFaceLockDelay))
        AppLogger.shared.info("AppDelegate: Protection started.")
    }

    // MARK: - Enrollment Window

    private func openEnrollmentWindow(autoStart: Bool) {
        // Pause protection during enrollment so the frame callback is taken over.
        frameProcessor.onStatusChange = nil
        frameProcessor.onLockRequired = nil

        menuBarController.updateStatus(.enrolling)

        if enrollmentWindowController == nil {
            enrollmentWindowController = EnrollmentWindowController(cameraManager: cameraManager)
        }

        enrollmentWindowController.onEnrollmentComplete = { [weak self] in
            guard let self = self else { return }
            AppLogger.shared.info("AppDelegate: Enrollment complete. Starting protection.")
            // Small delay so the user sees the success banner.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.startProtection()
            }
        }

        enrollmentWindowController.showAndBeginEnrollment(autoStart: autoStart)
    }

    // MARK: - Pause Check Timer

    /// Periodically checks whether a timed pause has expired.
    private func startPauseCheckTimer() {
        pauseCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            // Accessing isProtectionActive has the side-effect of clearing an expired pause.
            _ = Settings.shared.isProtectionActive
        }
    }

    // MARK: - Permission Denied Alert

    private func showPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText     = "Camera Access Required"
        alert.informativeText = "FaceGuard needs camera access to detect faces.\n\nPlease go to System Settings → Privacy & Security → Camera and enable FaceGuard."
        alert.alertStyle      = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
        } else {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Login Item Registration

    private func registerLoginItemIfNeeded() {
        guard Settings.shared.launchAtLogin else { return }
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
    }

    // MARK: - applicationWillTerminate

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up global event monitor to avoid leaks.
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        cameraManager.stopCapture()
        pauseCheckTimer?.invalidate()
        AppLogger.shared.info("FaceGuard: Application terminating.")
    }
}
