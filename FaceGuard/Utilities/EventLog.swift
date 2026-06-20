// EventLog.swift
// FaceGuard — Persists security events (lock triggers, intrusions, authorizations) for the dashboard.

import Foundation
import AppKit

// MARK: - Event Type

enum SecurityEventType: String, Codable {
    case authorizedAccess     = "authorized_access"
    case unauthorizedFace     = "unauthorized_face"
    case noFaceLock           = "no_face_lock"
    case blurActivated        = "blur_activated"
    case blurDeactivated      = "blur_deactivated"
    case enrollmentComplete   = "enrollment_complete"
    case alarmTriggered       = "alarm_triggered"
}

// MARK: - Security Event

struct SecurityEvent: Codable, Identifiable {
    let id: UUID
    let type: SecurityEventType
    let timestamp: Date
    let details: String
    /// Relative path (within intruders dir) to the snapshot image, if any.
    var snapshotFilename: String?

    init(type: SecurityEventType, details: String = "", snapshotFilename: String? = nil) {
        self.id               = UUID()
        self.type             = type
        self.timestamp        = Date()
        self.details          = details
        self.snapshotFilename = snapshotFilename
    }
}

// MARK: - EventLog

/// Thread-safe log of all security events. Written to disk as a JSON file.
final class EventLog {

    static let shared = EventLog()
    private init() { load() }

    private let queue = DispatchQueue(label: "com.faceguard.eventlog", qos: .utility)
    private(set) var events: [SecurityEvent] = []

    private var logFileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FaceGuard/event_log.json")
    }

    // MARK: - Public API

    func record(_ event: SecurityEvent) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.events.append(event)
            // Keep last 1000 events
            if self.events.count > 1000 { self.events.removeFirst(self.events.count - 1000) }
            self.persist()
        }
    }

    func eventsForCurrentWeek() -> [SecurityEvent] {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        return events.filter { $0.timestamp >= startOfWeek }
    }

    func eventsGroupedByHour() -> [Int: Int] {
        var counts = [Int: Int]()
        for event in events where event.type == .unauthorizedFace || event.type == .noFaceLock {
            let hour = Calendar.current.component(.hour, from: event.timestamp)
            counts[hour, default: 0] += 1
        }
        return counts
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: logFileURL),
              let decoded = try? JSONDecoder().decode([SecurityEvent].self, from: data) else { return }
        events = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: logFileURL, options: .atomic)
    }
}
