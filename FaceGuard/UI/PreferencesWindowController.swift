// PreferencesWindowController.swift
// FaceGuard — NSWindowController hosting the SwiftUI PreferencesView.

import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {

    // MARK: - Initialisation

    init() {
        let contentView = PreferencesView()
        let hostingVC   = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask:   [.titled, .closable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        window.title  = "FaceGuard — Preferences"
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingVC
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Show

    func showPreferences() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
