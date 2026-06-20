// ScreenLocker.swift
// FaceGuard — Handles screen locking with an optional warning overlay.
//
// Lock sequence:
//  1. (Optional) Show WarningOverlayWindow with configurable countdown
//  2. Call CGSession -suspend to lock the screen
//  3. Fallback to pmset displaysleepnow if CGSession binary is unavailable

import Foundation
import AppKit

// MARK: - ScreenLocker

/// Locks the macOS screen, optionally preceded by a countdown warning overlay.
final class ScreenLocker {

    // MARK: - Singleton

    static let shared = ScreenLocker()
    private init() {}

    // MARK: - State

    /// Prevents multiple simultaneous lock sequences.
    private var isLocking = false

    // MARK: - Public API

    /// Initiates a lock sequence.
    ///
    /// - Parameters:
    ///   - reason: One of "unauthorized_face", "no_face_timeout", or "panic".
    ///   - showWarning: If true and the user has enabled warnings, shows the overlay first.
    func lock(reason: String, showWarning: Bool = true) {
        guard !isLocking else { return }
        isLocking = true

        AppLogger.shared.warning("ScreenLocker: Lock triggered — reason='\(reason)'")

        let shouldWarn = showWarning
            && Settings.shared.showWarningBeforeLock
            && reason != "panic"

        if shouldWarn {
            let duration = Settings.shared.warningCountdownDuration
            WarningOverlayWindow.shared.show(countdown: duration) { [weak self] in
                self?.performLock(reason: reason)
            }
        } else {
            performLock(reason: reason)
        }
    }

    /// Immediately locks the screen without any warning — panic shortcut.
    func panicLock() {
        AppLogger.shared.warning("ScreenLocker: PANIC LOCK triggered via keyboard shortcut.")
        WarningOverlayWindow.shared.hide()
        performLock(reason: "panic")
    }

    // MARK: - Lock Execution

    private func performLock(reason: String) {
        AppLogger.shared.info("ScreenLocker: Executing screen lock.")

        DispatchQueue.main.async { [weak self] in
            WarningOverlayWindow.shared.hide()

            // On modern macOS, CGSession no longer works for screen locking.
            // Using the undocumented SACLockScreenImmediate API from the login framework
            // which instantly locks the screen.
            let loginFramework = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
            guard let handle = dlopen(loginFramework, RTLD_LAZY) else {
                AppLogger.shared.error("ScreenLocker: Failed to load login.framework. Using pmset fallback.")
                self?.pmsetFallback()
                self?.resetLockingFlag()
                return
            }
            
            defer { dlclose(handle) }
            
            guard let sym = dlsym(handle, "SACLockScreenImmediate") else {
                AppLogger.shared.error("ScreenLocker: Failed to find SACLockScreenImmediate. Using pmset fallback.")
                self?.pmsetFallback()
                self?.resetLockingFlag()
                return
            }
            
            typealias SACLockScreenImmediateType = @convention(c) () -> Void
            let lockScreen = unsafeBitCast(sym, to: SACLockScreenImmediateType.self)
            
            lockScreen()
            AppLogger.shared.info("ScreenLocker: SACLockScreenImmediate executed.")
            
            self?.resetLockingFlag()
        }
    }

    private func resetLockingFlag() {
        // Reset the locking flag after a delay so we don't re-lock immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.isLocking = false
        }
    }

    /// Fallback: put the display to sleep using pmset.
    private func pmsetFallback() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
        AppLogger.shared.info("ScreenLocker: pmset displaysleepnow executed.")
    }
}
