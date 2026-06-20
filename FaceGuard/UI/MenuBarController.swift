// MenuBarController.swift
// FaceGuard — Manages the NSStatusItem menu bar icon and drop-down menu.
//
// Icon states:
//  • eye.fill (green)  — Authorized user detected, protection active
//  • eye (yellow)      — Paused
//  • lock.fill (red)   — Unauthorized face / locking imminent
//  • eye.slash (gray)  — No face, counting down

import AppKit
import SwiftUI

// MARK: - MenuBarController

final class MenuBarController: NSObject {

    // MARK: - Status Item

    private let statusItem: NSStatusItem
    private var statusMenu: NSMenu = NSMenu()
    
    // Ensure the status item is retained
    private var statusItemRetainer: NSStatusItem?

    // MARK: - Dynamic Menu Items (updated on status change)

    private var statusLabelItem: NSMenuItem!
    private var matchScoreItem:  NSMenuItem!
    private var resumeItem:      NSMenuItem!
    private var pauseItem:       NSMenuItem!

    // MARK: - Callbacks (set by AppDelegate)

    var onReEnroll:   (() -> Void)?
    var onPause:      ((Int?) -> Void)?  // nil = indefinite
    var onResume:     (() -> Void)?
    var onQuit:       (() -> Void)?
    var onPreferences: (() -> Void)?
    var onViewLog:    (() -> Void)?

    // MARK: - Current State

    private var currentStatus: ProtectionStatus = .noFace(secondsRemaining: 0)

    // MARK: - Initialisation

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItemRetainer = statusItem  // Ensure strong reference
        super.init()
        // Ensure the button always shows something even before first status update
        if let button = statusItem.button {
            button.title = "FG"
            button.toolTip = "FaceGuard - Face Recognition Security"
        }
        buildMenu()
        statusItem.menu = statusMenu
        updateIcon(for: .noFace(secondsRemaining: 0))
        AppLogger.shared.info("MenuBarController: Initialised with status item.")
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        statusMenu = NSMenu()

        // ── Status Label (non-clickable header) ──────────────────────────
        statusLabelItem = NSMenuItem(title: "FaceGuard — Starting…", action: nil, keyEquivalent: "")
        statusLabelItem.isEnabled = false
        statusLabelItem.attributedTitle = styledMenuHeader("FaceGuard — Starting…")
        statusMenu.addItem(statusLabelItem)

        // Match score sub-label
        matchScoreItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        matchScoreItem.isEnabled = false
        matchScoreItem.isHidden  = true
        statusMenu.addItem(matchScoreItem)

        statusMenu.addItem(.separator())

        // ── Re-enroll ────────────────────────────────────────────────────
        let reEnrollItem = NSMenuItem(title: "📷  Re-enroll My Face",
                                       action: #selector(handleReEnroll),
                                       keyEquivalent: "")
        reEnrollItem.target = self
        statusMenu.addItem(reEnrollItem)

        // ── Pause submenu ────────────────────────────────────────────────
        pauseItem = NSMenuItem(title: "⏸  Pause Protection", action: nil, keyEquivalent: "")
        let pauseSubmenu = NSMenu()
        for (label, minutes) in [("5 Minutes", 5), ("15 Minutes", 15), ("30 Minutes", 30)] {
            let item = NSMenuItem(title: label, action: #selector(handlePause(_:)), keyEquivalent: "")
            item.target = self
            item.tag    = minutes
            pauseSubmenu.addItem(item)
        }
        let indefiniteItem = NSMenuItem(title: "Until Re-enabled", action: #selector(handlePauseIndefinite), keyEquivalent: "")
        indefiniteItem.target = self
        pauseSubmenu.addItem(indefiniteItem)
        pauseItem.submenu = pauseSubmenu
        statusMenu.addItem(pauseItem)

        // ── Resume (only shown when paused) ─────────────────────────────
        resumeItem = NSMenuItem(title: "▶️  Resume Protection",
                                 action: #selector(handleResume),
                                 keyEquivalent: "")
        resumeItem.target    = self
        resumeItem.isHidden  = true
        statusMenu.addItem(resumeItem)

        statusMenu.addItem(.separator())

        // ── View Intruder Log ────────────────────────────────────────────
        let logItem = NSMenuItem(title: "🕒  View Intruder Log",
                                  action: #selector(handleViewLog),
                                  keyEquivalent: "")
        logItem.target = self
        statusMenu.addItem(logItem)

        // ── Security Dashboard ───────────────────────────────────────────
        let dashItem = NSMenuItem(title: "📊  Security Dashboard",
                                   action: #selector(handleDashboard),
                                   keyEquivalent: "d")
        dashItem.target = self
        statusMenu.addItem(dashItem)

        // ── Enroll Second User ───────────────────────────────────────────
        let secondUserItem = NSMenuItem(title: "👥  Enroll Second User",
                                         action: #selector(handleEnrollSecondUser),
                                         keyEquivalent: "")
        secondUserItem.target = self
        statusMenu.addItem(secondUserItem)

        // ── Preferences ──────────────────────────────────────────────────
        let prefsItem = NSMenuItem(title: "⚙️  Preferences…",
                                    action: #selector(handlePreferences),
                                    keyEquivalent: ",")
        prefsItem.target = self
        statusMenu.addItem(prefsItem)

        statusMenu.addItem(.separator())

        // ── Quit ─────────────────────────────────────────────────────────
        let quitItem = NSMenuItem(title: "❌  Quit FaceGuard",
                                   action: #selector(handleQuit),
                                   keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)

        statusItem.menu = statusMenu
    }

    // MARK: - Status Updates

    /// Call this whenever the protection status changes.
    func updateStatus(_ status: ProtectionStatus) {
        currentStatus = status
        DispatchQueue.main.async { [weak self] in
            self?.applyStatus(status)
        }
    }

    private func applyStatus(_ status: ProtectionStatus) {
        updateIcon(for: status)

        let isPaused = !Settings.shared.isProtectionActive

        // Pause/resume item visibility
        pauseItem.isHidden  = isPaused
        resumeItem.isHidden = !isPaused

        switch status {
        case .authorized(let score):
            statusLabelItem.attributedTitle = styledMenuHeader("FaceGuard — 🟢 Protected")
            if Settings.shared.showMatchScoreInMenu {
                matchScoreItem.title = "   Match: \(Int(score * 100))%"
                matchScoreItem.isHidden = false
            } else {
                matchScoreItem.isHidden = true
            }

        case .unauthorized(let score):
            statusLabelItem.attributedTitle = styledMenuHeader("FaceGuard — 🔴 Unauthorized")
            matchScoreItem.title = "   Match: \(Int(score * 100))% (below threshold)"
            matchScoreItem.isHidden = false

        case .noFace(let remaining):
            statusLabelItem.attributedTitle = styledMenuHeader("FaceGuard — ⚪ No Face (\(Int(remaining))s)")
            matchScoreItem.isHidden = true

        case .paused:
            statusLabelItem.attributedTitle = styledMenuHeader("FaceGuard — 🟡 Paused")
            matchScoreItem.isHidden = true

        case .enrolling:
            statusLabelItem.attributedTitle = styledMenuHeader("FaceGuard — 🔵 Enrolling…")
            matchScoreItem.isHidden = true

        case .blurActive:
            statusLabelItem.attributedTitle = styledMenuHeader("FaceGuard — 🟣 Privacy Blur Active")
            matchScoreItem.isHidden = true
        }
    }

    // MARK: - Icon Updates

    private func updateIcon(for status: ProtectionStatus) {
        guard let button = statusItem.button else { return }

        // Map each protection state to an SF Symbol + a status colour
        let (symbolName, tintColor): (String, NSColor) = {
            switch status {
            case .authorized:   return ("eye.fill",       NSColor(hex: "#34C759"))
            case .unauthorized: return ("lock.fill",      NSColor(hex: "#FF3B30"))
            case .noFace:       return ("eye.slash",      NSColor(hex: "#8E8E93"))
            case .paused:       return ("eye",            NSColor(hex: "#FFD60A"))
            case .enrolling:    return ("camera.fill",    NSColor(hex: "#0A84FF"))
            case .blurActive:   return ("eye.slash.fill", NSColor(hex: "#BF5AF2"))
            }
        }()

        // Try to load SF Symbol with color
        if let sfImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let sizeConf  = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let colorConf = NSImage.SymbolConfiguration(paletteColors: [tintColor])
            let combined  = sizeConf.applying(colorConf)
            
            if let coloredImage = sfImage.withSymbolConfiguration(combined) {
                coloredImage.isTemplate = false
                button.image = coloredImage
                button.imagePosition = .imageLeading
                button.title = "FG"  // Keep text as fallback
                AppLogger.shared.info("MenuBarController: Updated icon to \(symbolName)")
                return
            }
        }
        
        // Fallback to text-only
        button.image = nil
        button.title = "FG"
        AppLogger.shared.warning("MenuBarController: SF Symbol \(symbolName) failed, using text fallback")
    }

    // MARK: - Attributed Menu Header

    private func styledMenuHeader(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font:            NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ])
    }

    // MARK: - Action Handlers

    @objc private func handleReEnroll() {
        onReEnroll?()
    }

    @objc private func handlePause(_ sender: NSMenuItem) {
        onPause?(sender.tag)
    }

    @objc private func handlePauseIndefinite() {
        onPause?(nil)
    }

    @objc private func handleResume() {
        onResume?()
    }

    @objc private func handleViewLog() {
        onViewLog?()
    }

    @objc private func handleDashboard() {
        NotificationCenter.default.post(name: .openDashboardWindow, object: nil)
    }

    @objc private func handleEnrollSecondUser() {
        NotificationCenter.default.post(name: .enrollSecondUser, object: nil)
    }

    @objc private func handlePreferences() {
        onPreferences?()
    }

    @objc private func handleQuit() {
        onQuit?()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openEnrollmentWindow  = Notification.Name("FaceGuard.openEnrollmentWindow")
    static let openPreferencesWindow = Notification.Name("FaceGuard.openPreferencesWindow")
    static let openDashboardWindow   = Notification.Name("FaceGuard.openDashboardWindow")
    static let enrollSecondUser      = Notification.Name("FaceGuard.enrollSecondUser")
}

// MARK: - NSColor Hex Extension

extension NSColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8)  & 0xFF) / 255
        let b = CGFloat(rgb         & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
