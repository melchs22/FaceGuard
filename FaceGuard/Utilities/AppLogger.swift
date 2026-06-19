// AppLogger.swift
// FaceGuard — Thread-safe file-based logger.
// Writes timestamped entries to ~/Library/Logs/FaceGuard/faceguard.log

import Foundation

/// Log severity levels.
enum LogLevel: String {
    case debug   = "DEBUG"
    case info    = "INFO "
    case warning = "WARN "
    case error   = "ERROR"
}

/// Singleton logger that writes to a local log file and optionally prints to console.
final class AppLogger {

    // MARK: - Singleton

    static let shared = AppLogger()
    private init() {
        setupLogDirectory()
    }

    // MARK: - Properties

    /// The URL of the active log file.
    private(set) var logFileURL: URL = {
        let logDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/FaceGuard", isDirectory: true)
        return logDir.appendingPathComponent("faceguard.log")
    }()

    /// Serial queue that serialises all file writes, preventing data races.
    private let queue = DispatchQueue(label: "com.faceguard.logger", qos: .utility)

    /// ISO8601 date formatter for timestamps.
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    // MARK: - Setup

    private func setupLogDirectory() {
        let dir = logFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)

        // Also create the intruders sub-directory used for snapshot images.
        let intruderDir = dir.appendingPathComponent("intruders", isDirectory: true)
        try? FileManager.default.createDirectory(at: intruderDir,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - Public Logging Interface

    func debug(_ message: String, file: String = #file, function: String = #function) {
        log(message, level: .debug, file: file, function: function)
    }

    func info(_ message: String, file: String = #file, function: String = #function) {
        log(message, level: .info, file: file, function: function)
    }

    func warning(_ message: String, file: String = #file, function: String = #function) {
        log(message, level: .warning, file: file, function: function)
    }

    func error(_ message: String, file: String = #file, function: String = #function) {
        log(message, level: .error, file: file, function: function)
    }

    // MARK: - Core Write

    private func log(_ message: String,
                     level: LogLevel,
                     file: String,
                     function: String) {
        let timestamp = dateFormatter.string(from: Date())
        let filename  = URL(fileURLWithPath: file).lastPathComponent
        let entry     = "[\(timestamp)] [\(level.rawValue)] [\(filename):\(function)] \(message)\n"

        // Mirror to console during development.
        print(entry, terminator: "")

        // Asynchronously append to log file.
        queue.async { [weak self] in
            guard let self = self else { return }
            if let data = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: self.logFileURL, options: .atomic)
                }
            }
        }
    }

    // MARK: - Convenience

    /// Returns the URL to the intruder snapshots directory.
    var intruderDirectoryURL: URL {
        logFileURL.deletingLastPathComponent().appendingPathComponent("intruders")
    }

    /// Opens the log directory in Finder.
    func openLogDirectoryInFinder() {
        NSWorkspace.shared.open(logFileURL.deletingLastPathComponent())
    }
}
