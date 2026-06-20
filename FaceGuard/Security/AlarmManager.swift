// AlarmManager.swift
// FaceGuard — Plays an alarm sound after 3+ consecutive unauthorized access attempts.

import Foundation
import AppKit
import UserNotifications

final class AlarmManager {

    static let shared = AlarmManager()
    private init() {}

    private var consecutiveFailures = 0
    private let threshold = 3
    private var isAlarming = false

    /// Call this whenever an unauthorized face triggers a lock.
    func recordUnauthorizedAttempt() {
        consecutiveFailures += 1
        AppLogger.shared.warning("AlarmManager: Unauthorized attempt #\(consecutiveFailures)")
        if consecutiveFailures >= threshold && !isAlarming {
            triggerAlarm()
        }
    }

    /// Call this when the authorized user is recognized.
    func resetFailures() {
        consecutiveFailures = 0
        stopAlarm()
    }

    private func triggerAlarm() {
        isAlarming = true
        AppLogger.shared.warning("AlarmManager: ALARM triggered after \(threshold) consecutive unauthorized attempts!")
        EventLog.shared.record(SecurityEvent(type: .alarmTriggered, details: "3+ consecutive unauthorized attempts"))

        DispatchQueue.main.async {
            // Play a repeating system alert sound
            NSSound.beep()
            // Also play a more prominent sound if available
            if let sound = NSSound(named: "Sosumi") {
                sound.loops = false
                sound.play()
            }
            // Show a prominent notification
            self.showAlarmNotification()
        }

        // Auto-stop after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopAlarm()
        }
    }

    private func stopAlarm() {
        isAlarming = false
        NSSound(named: "Sosumi")?.stop()
    }

    private func showAlarmNotification() {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ FaceGuard Alarm"
        content.body = "Multiple unauthorized access attempts detected on your Mac!"
        content.sound = UNNotificationSound.defaultCritical

        let request = UNNotificationRequest(
            identifier: "faceguard.alarm.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
