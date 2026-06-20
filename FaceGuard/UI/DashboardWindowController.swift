// DashboardWindowController.swift
// FaceGuard — Hosts the IntruderDashboardView in a standalone NSWindow.

import AppKit
import SwiftUI

final class DashboardWindowController: NSWindowController {

    convenience init() {
        let view = IntruderDashboardView()
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title           = "FaceGuard — Security Dashboard"
        win.styleMask       = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 780, height: 600))
        win.minSize         = NSSize(width: 700, height: 500)
        win.center()
        win.isReleasedWhenClosed = false
        self.init(window: win)
    }

    func showDashboard() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
