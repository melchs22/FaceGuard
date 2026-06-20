// MediaController.swift
// FaceGuard — Pauses media playback when the user walks away, resumes when they return.

import Foundation
import AppKit

final class MediaController {

    static let shared = MediaController()
    private init() {}

    // MARK: - Public API

    /// Pause system media (music, podcasts, videos) using the media key event.
    func pauseMedia() {
        guard Settings.shared.autoPauseMediaEnabled else { return }
        sendMediaKey(.pause)
        AppLogger.shared.info("MediaController: Paused media playback.")
    }

    /// Resume system media.
    func resumeMedia() {
        guard Settings.shared.autoPauseMediaEnabled else { return }
        sendMediaKey(.play)
        AppLogger.shared.info("MediaController: Resumed media playback.")
    }

    // MARK: - Private

    private enum MediaKeyEvent {
        case play, pause
        var keyCode: Int {
            switch self {
            case .play:  return 16  // NX_KEYTYPE_PLAY
            case .pause: return 16  // same key — toggle
            }
        }
    }

    private func sendMediaKey(_ key: MediaKeyEvent) {
        let down = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: .init(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (key.keyCode << 16) | (0xa << 8),
            data2: -1
        )
        down?.cgEvent?.post(tap: .cghidEventTap)

        let up = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: .init(rawValue: 0xb00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (key.keyCode << 16) | (0xb << 8),
            data2: -1
        )
        up?.cgEvent?.post(tap: .cghidEventTap)
    }
}
