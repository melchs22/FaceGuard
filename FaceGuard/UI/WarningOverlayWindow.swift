// WarningOverlayWindow.swift
// FaceGuard — Full-screen translucent red warning overlay shown before locking.
//
// Appears on all connected screens, counts down, then calls the completion handler
// which triggers the actual screen lock.

import AppKit
import SwiftUI

// MARK: - Warning Overlay Content (SwiftUI)

/// The SwiftUI view rendered inside the warning overlay window.
private struct WarningOverlayView: View {
    @Binding var countdown: Int

    var body: some View {
        ZStack {
            // Semi-transparent red background
            Color.red.opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                // Lock icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

                // Warning text
                Text("Unauthorized User Detected")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4)

                // Countdown
                Text("Locking in \(countdown)…")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(60)
        }
        .animation(.easeInOut, value: countdown)
    }
}

// MARK: - WarningOverlayWindow

/// Manages the full-screen warning overlay window(s).
final class WarningOverlayWindow {

    // MARK: - Singleton

    static let shared = WarningOverlayWindow()
    private init() {}

    // MARK: - State

    private var windows: [NSWindow] = []
    private var countdownValue: Int = 3
    private var countdownTimer: Timer?
    private var completion: (() -> Void)?
    private var hostingControllers: [NSHostingController<WarningOverlayView>] = []

    // MARK: - Public API

    /// Shows the warning overlay on all screens with a countdown.
    /// - Parameters:
    ///   - countdown: Number of seconds to count down before calling completion.
    ///   - completion: Called when the countdown reaches zero.
    func show(countdown: Int, completion: @escaping () -> Void) {
        guard windows.isEmpty else { return } // Already showing

        self.countdownValue = countdown
        self.completion     = completion

        DispatchQueue.main.async { [weak self] in
            self?.createOverlayWindows()
            self?.startCountdown()
        }
    }

    /// Hides and destroys all overlay windows immediately.
    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.cleanup()
        }
    }

    // MARK: - Private

    private func createOverlayWindows() {
        for screen in NSScreen.screens {
            let bindingValue = Binding<Int>(
                get:  { [weak self] in self?.countdownValue ?? 0 },
                set:  { [weak self] val in self?.countdownValue = val }
            )
            let hostingVC = NSHostingController(rootView: WarningOverlayView(countdown: bindingValue))

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask:   [.borderless],
                backing:     .buffered,
                defer:       false
            )
            window.level                = .screenSaver
            window.backgroundColor      = .clear
            window.isOpaque             = false
            window.collectionBehavior   = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentViewController = hostingVC
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)

            windows.append(window)
            hostingControllers.append(hostingVC)
        }
    }

    private func startCountdown() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            if self.countdownValue > 1 {
                self.countdownValue -= 1
                self.refreshViews()
            } else {
                timer.invalidate()
                self.cleanup()
                self.completion?()
            }
        }
        // Schedule on .common mode so it fires even when the RunLoop is in event-tracking mode.
        // Without this, the countdown stalls until the user moves the cursor.
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func refreshViews() {
        // Touch the hosting controllers to trigger SwiftUI redraw.
        for hvc in hostingControllers {
            hvc.rootView = WarningOverlayView(countdown: Binding<Int>(
                get:  { [weak self] in self?.countdownValue ?? 0 },
                set:  { [weak self] val in self?.countdownValue = val }
            ))
        }
    }

    private func cleanup() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        hostingControllers.removeAll()
    }
}
