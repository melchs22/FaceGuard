// Settings.swift
// FaceGuard — UserDefaults wrapper for all user-configurable preferences.
// Access settings via Settings.shared from anywhere in the app.

import Foundation
import Combine

// MARK: - Property Wrapper

/// A property wrapper that reads/writes a Codable value to UserDefaults.
@propertyWrapper
struct UserDefault<T: Codable> {
    let key: String
    let defaultValue: T
    let store: UserDefaults

    init(_ key: String, defaultValue: T, store: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.store = store
    }

    var wrappedValue: T {
        get {
            guard let data = store.data(forKey: key),
                  let value = try? JSONDecoder().decode(T.self, from: data) else {
                return defaultValue
            }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                store.set(data, forKey: key)
            }
        }
    }
}

// MARK: - Settings

/// Centralised settings store. All preferences are persisted to UserDefaults.
final class Settings {

    // Singleton
    static let shared = Settings()
    private init() {}

    // MARK: - Face Matching

    /// Cosine similarity threshold (0.60 – 0.90). Faces scoring above this are authorised.
    @UserDefault("similarity_threshold", defaultValue: 0.75)
    var similarityThreshold: Double

    /// Number of consecutive frames in the rolling average buffer.
    @UserDefault("rolling_buffer_size", defaultValue: 5)
    var rollingBufferSize: Int

    /// How many seconds an unauthorised face must be continuously visible before the screen locks.
    @UserDefault("stranger_cooldown_seconds", defaultValue: 2.0)
    var strangerCooldownSeconds: Double

    // MARK: - Lock Behaviour

    /// Grace period in seconds before locking when no face is detected (3 – 60).
    @UserDefault("no_face_lock_delay", defaultValue: 10.0)
    var noFaceLockDelay: Double

    /// Whether to show a countdown warning overlay before locking.
    @UserDefault("show_warning_before_lock", defaultValue: true)
    var showWarningBeforeLock: Bool

    /// Duration of the warning countdown (2, 3, or 5 seconds).
    @UserDefault("warning_countdown_duration", defaultValue: 3)
    var warningCountdownDuration: Int

    // MARK: - Privacy / Logging

    /// Whether to save a thumbnail snapshot of the detected intruder face.
    @UserDefault("save_intruder_snapshots", defaultValue: true)
    var saveIntruderSnapshots: Bool

    /// Whether to show the live match score in the menu bar.
    @UserDefault("show_match_score_in_menu", defaultValue: true)
    var showMatchScoreInMenu: Bool

    // MARK: - App Behaviour

    /// Whether the app should launch at login.
    @UserDefault("launch_at_login", defaultValue: false)
    var launchAtLogin: Bool

    /// Whether protection is currently paused.
    @UserDefault("is_paused", defaultValue: false)
    var isPaused: Bool

    /// The date/time when the pause expires. Nil if not paused or paused indefinitely.
    @UserDefault("pause_expires_at", defaultValue: nil as Date?)
    var pauseExpiresAt: Date?

    // MARK: - Enrollment State

    /// Whether the user has completed face enrollment at least once.
    @UserDefault("has_enrolled", defaultValue: false)
    var hasEnrolled: Bool

    // MARK: - Computed Helpers

    /// Returns true if protection is active (not paused or pause has expired).
    var isProtectionActive: Bool {
        guard isPaused else { return true }
        if let expires = pauseExpiresAt {
            if Date() >= expires {
                // Pause has expired — automatically un-pause
                isPaused = false
                pauseExpiresAt = nil
                return true
            }
        }
        return false
    }

    /// Pause protection for a given number of minutes. Pass nil for indefinite pause.
    func pauseProtection(forMinutes minutes: Int?) {
        isPaused = true
        if let minutes = minutes {
            pauseExpiresAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        } else {
            pauseExpiresAt = nil
        }
    }

    /// Resume protection immediately.
    func resumeProtection() {
        isPaused = false
        pauseExpiresAt = nil
    }

    // MARK: - New Feature Settings

    /// Night mode — boost camera sensitivity in low light.
    @UserDefault("night_mode_enabled", defaultValue: false)
    var nightModeEnabled: Bool

    /// Auto-pause music/video when user walks away.
    @UserDefault("auto_pause_media_enabled", defaultValue: true)
    var autoPauseMediaEnabled: Bool

    /// Meeting mode — disable protection during video calls.
    @UserDefault("meeting_mode_enabled", defaultValue: true)
    var meetingModeEnabled: Bool

    /// Number of authorized users enrolled (up to 2).
    @UserDefault("authorized_user_count", defaultValue: 1)
    var authorizedUserCount: Int
    
    // MARK: - Liveness Detection Settings

    @UserDefault("liveness_blink_enabled", defaultValue: true)
    var livenessBlinkEnabled: Bool

    @UserDefault("liveness_movement_enabled", defaultValue: true)
    var livenessMovementEnabled: Bool

    @UserDefault("liveness_texture_enabled", defaultValue: true)
    var livenessTextureEnabled: Bool

    @UserDefault("liveness_depth_enabled", defaultValue: true)
    var livenessDepthEnabled: Bool

    @UserDefault("liveness_sensitivity", defaultValue: 0.70)
    var livenessSensitivity: Double

    // MARK: - Adaptive Learning Settings

    @UserDefault("adaptive_learning_enabled", defaultValue: true)
    var adaptiveLearningEnabled: Bool

    /// Speed of learning (e.g., 0.05 slow, 0.10 normal, 0.20 fast)
    @UserDefault("learning_speed_rate", defaultValue: 0.10)
    var learningSpeedRate: Float


    // MARK: - Reset

    /// Resets all settings to their default values.
    func resetToDefaults() {
        similarityThreshold     = 0.75
        rollingBufferSize       = 5
        strangerCooldownSeconds = 2.0
        noFaceLockDelay         = 10.0
        showWarningBeforeLock   = true
        warningCountdownDuration = 3
        saveIntruderSnapshots   = true
        showMatchScoreInMenu    = true
        launchAtLogin           = false
        isPaused                = false
        pauseExpiresAt          = nil
        nightModeEnabled        = false
        autoPauseMediaEnabled   = true
        meetingModeEnabled      = true
        authorizedUserCount     = 1
    }
}
