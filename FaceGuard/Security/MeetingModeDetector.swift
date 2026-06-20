// MeetingModeDetector.swift
// FaceGuard — Detects when a video-call app is running and suspends protection.

import Foundation
import AppKit

final class MeetingModeDetector {

    static let shared = MeetingModeDetector()
    private init() {}

    /// Bundle IDs of known video-call apps.
    private let meetingAppBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.google.meet",
        "com.apple.facetime",
        "com.cisco.webex.meetings",
        "com.skype.skype",
        "com.loom.desktop",
        "com.webex.meetingmanager",
        "com.bluejeans.BlueJeans"
    ]

    /// Returns true if a known meeting application is currently running and active.
    var isMeetingActive: Bool {
        guard Settings.shared.meetingModeEnabled else { return false }
        let running = NSWorkspace.shared.runningApplications
        return running.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return meetingAppBundleIDs.contains(bundleID) && app.isActive
        }
    }
}
