// WarningOverlayWindow.swift
// FaceGuard — Full-screen warning overlay before locking.

import AppKit
import SwiftUI

private struct WarningOverlayView: View {
    @Binding var countdown: Int
    let reason: String

    private var isNoFace: Bool { reason == "no_face_timeout" }

    var body: some View {
        ZStack {
            (isNoFace ? Color.black.opacity(0.88) : Color.red.opacity(0.88))
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: isNoFace ? "person.slash.fill" : "lock.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(.white)

                Text(isNoFace ? "No User Detected" : "Unauthorized User Detected")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Locking in \(countdown)…")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))

                // Countdown ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(countdown) / 3.0)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: countdown)
                }
                .frame(width: 64, height: 64)
            }
            .padding(60)
        }
    }
}

final class WarningOverlayWindow {

    static let shared = WarningOverlayWindow()
    private init() {}

    private var windows:            [NSWindow] = []
    private var countdownValue:     Int = 3
    private var countdownTimer:     Timer?
    private var completion:         (() -> Void)?
    private var currentReason:      String = "no_face_timeout"
    private var hostingControllers: [NSHostingController<WarningOverlayView>] = []

    func show(countdown: Int, reason: String = "no_face_timeout", completion: @escaping () -> Void) {
        guard windows.isEmpty else { return }
        self.countdownValue = countdown
        self.currentReason  = reason
        self.completion     = completion
        DispatchQueue.main.async { [weak self] in
            self?.createWindows()
            self?.startCountdown()
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in self?.cleanup() }
    }

    private func createWindows() {
        for screen in NSScreen.screens {
            let hvc = NSHostingController(rootView: makeView())
            let win = NSWindow(contentRect: screen.frame,
                               styleMask: [.borderless],
                               backing: .buffered, defer: false)
            win.level              = .screenSaver
            win.backgroundColor    = .clear
            win.isOpaque           = false
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.contentViewController = hvc
            win.setFrame(screen.frame, display: true)
            win.makeKeyAndOrderFront(nil)
            windows.append(win)
            hostingControllers.append(hvc)
        }
    }

    private func makeView() -> WarningOverlayView {
        WarningOverlayView(
            countdown: Binding(get: { [weak self] in self?.countdownValue ?? 0 },
                               set: { [weak self] v in self?.countdownValue = v }),
            reason: currentReason
        )
    }

    private func startCountdown() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if self.countdownValue > 1 {
                self.countdownValue -= 1
                self.refreshViews()
            } else {
                t.invalidate()
                self.cleanup()
                self.completion?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func refreshViews() {
        for hvc in hostingControllers { hvc.rootView = makeView() }
    }

    private func cleanup() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        hostingControllers.removeAll()
    }
}
