// PrivacyBlurWindow.swift
// FaceGuard — Overlays a full-screen blur when a second (unauthorized) face is detected nearby.
// The window sits above all content but can be dismissed by the authorized user returning alone.

import AppKit

final class PrivacyBlurWindow {

    static let shared = PrivacyBlurWindow()
    private init() {}

    private var window: NSWindow?
    private(set) var isVisible = false

    // MARK: - Show / Hide

    func show() {
        guard !isVisible else { return }
        isVisible = true

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask:   [.borderless],
                backing:     .buffered,
                defer:       false,
                screen:      screen
            )
            win.level                = .screenSaver
            win.backgroundColor      = .clear
            win.isOpaque             = false
            win.ignoresMouseEvents   = true
            win.collectionBehavior   = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.hasShadow            = false

            // Visual effect blur
            let blur = NSVisualEffectView(frame: screen.frame)
            blur.blendingMode    = .behindWindow
            blur.state           = .active
            blur.material        = .fullScreenUI
            blur.autoresizingMask = [.width, .height]

            // Warning label
            let label = NSTextField(labelWithString: "🔒  Privacy Shield Active")
            label.font        = NSFont.systemFont(ofSize: 28, weight: .semibold)
            label.textColor   = .white
            label.isBezeled   = false
            label.isEditable  = false
            label.backgroundColor = .clear
            label.sizeToFit()
            label.frame = CGRect(
                x: (screen.frame.width  - label.frame.width)  / 2,
                y: (screen.frame.height - label.frame.height) / 2,
                width:  label.frame.width,
                height: label.frame.height
            )

            let container = NSView(frame: screen.frame)
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            container.addSubview(blur)
            container.addSubview(label)

            win.contentView = container
            win.orderFront(nil)
            self.window = win

            AppLogger.shared.info("PrivacyBlurWindow: Blur overlay shown.")
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        DispatchQueue.main.async { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
            AppLogger.shared.info("PrivacyBlurWindow: Blur overlay hidden.")
        }
    }
}
