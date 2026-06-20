// IntruderDashboardView.swift
// FaceGuard — A beautiful analytics dashboard showing intrusion history, heatmap, and weekly report.

import SwiftUI
import AppKit

// MARK: - Dashboard View

struct IntruderDashboardView: View {

    @State private var events: [SecurityEvent]    = []
    @State private var hourlyData: [Int: Int]     = [:]
    @State private var selectedEvent: SecurityEvent? = nil
    @State private var weekSummary: WeekSummary   = .empty

    private let intruderDir = AppLogger.shared.intruderDirectoryURL

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "#0a0a1a"), Color(hex: "#0f0c29"), Color(hex: "#1a1030")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    // Header
                    dashboardHeader

                    // Summary cards row
                    summaryCardsRow

                    // Heatmap
                    heatmapSection

                    // Event list
                    eventListSection
                }
                .padding(28)
            }
        }
        .frame(width: 780, height: 600)
        .onAppear { refreshData() }
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Security Dashboard")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Intrusion history and threat analytics")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            Button(action: generateReport) {
                Label("Export Report", systemImage: "doc.text")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.35), in: Capsule())
                    .overlay(Capsule().stroke(Color.purple.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Summary Cards

    private var summaryCardsRow: some View {
        HStack(spacing: 16) {
            summaryCard(
                icon: "exclamationmark.shield.fill",
                title: "Intrusions This Week",
                value: "\(weekSummary.intrusions)",
                color: .red
            )
            summaryCard(
                icon: "eye.slash.fill",
                title: "Privacy Blurs",
                value: "\(weekSummary.blurs)",
                color: .purple
            )
            summaryCard(
                icon: "checkmark.shield.fill",
                title: "Authorized Accesses",
                value: "\(weekSummary.authorized)",
                color: .cyan
            )
            summaryCard(
                icon: "alarm.fill",
                title: "Alarms Triggered",
                value: "\(weekSummary.alarms)",
                color: .orange
            )
        }
    }

    private func summaryCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(2)
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Heatmap Section

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Risk Heatmap — By Hour of Day")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<24, id: \.self) { hour in
                    let count = hourlyData[hour] ?? 0
                    let maxCount = max(hourlyData.values.max() ?? 1, 1)
                    let barHeight = CGFloat(count) / CGFloat(maxCount) * 80 + 4

                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(heatColor(for: count, max: maxCount))
                            .frame(width: 22, height: barHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .animation(.spring(response: 0.5), value: count)

                        Text(hour % 6 == 0 ? "\(hour)h" : "")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 6) {
                Text("Low Risk")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                LinearGradient(colors: [.green.opacity(0.5), .yellow, .orange, .red],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 100, height: 6)
                    .clipShape(Capsule())
                Text("High Risk")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private func heatColor(for count: Int, max: Int) -> Color {
        guard max > 0 else { return .green.opacity(0.3) }
        let ratio = Double(count) / Double(max)
        if ratio < 0.33 { return .green.opacity(0.6) }
        if ratio < 0.66 { return .yellow.opacity(0.8) }
        return .red.opacity(0.9)
    }

    // MARK: - Event List

    private var eventListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Events")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            if events.isEmpty {
                Text("No security events recorded yet.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(events.reversed().prefix(50)) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: SecurityEvent) -> some View {
        HStack(spacing: 12) {
            // Icon
            Circle()
                .fill(event.type.color.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: event.type.iconName)
                        .font(.system(size: 14))
                        .foregroundColor(event.type.color)
                )

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            // Snapshot thumbnail if available
            if let filename = event.snapshotFilename {
                let url = intruderDir.appendingPathComponent(filename)
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(event.type.color.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Data Refresh

    private func refreshData() {
        events = EventLog.shared.events
        hourlyData = EventLog.shared.eventsGroupedByHour()
        let weekEvents = EventLog.shared.eventsForCurrentWeek()
        weekSummary = WeekSummary(
            intrusions: weekEvents.filter { $0.type == .unauthorizedFace || $0.type == .noFaceLock }.count,
            blurs:      weekEvents.filter { $0.type == .blurActivated }.count,
            authorized: weekEvents.filter { $0.type == .authorizedAccess }.count,
            alarms:     weekEvents.filter { $0.type == .alarmTriggered }.count
        )
    }

    // MARK: - Report Generation

    private func generateReport() {
        let report = ReportGenerator.shared.generateHTMLReport()
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let url = desktop.appendingPathComponent("FaceGuard_Security_Report.html")
        try? report.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Week Summary Model

struct WeekSummary {
    var intrusions: Int
    var blurs: Int
    var authorized: Int
    var alarms: Int
    static let empty = WeekSummary(intrusions: 0, blurs: 0, authorized: 0, alarms: 0)
}

// MARK: - SecurityEventType Extensions

extension SecurityEventType {
    var displayName: String {
        switch self {
        case .authorizedAccess:   return "Authorized Access"
        case .unauthorizedFace:   return "Unauthorized Face Detected"
        case .noFaceLock:         return "Screen Locked (No Face)"
        case .blurActivated:      return "Privacy Blur Activated"
        case .blurDeactivated:    return "Privacy Blur Deactivated"
        case .enrollmentComplete: return "Face Enrollment Completed"
        case .alarmTriggered:     return "Security Alarm Triggered"
        }
    }

    var iconName: String {
        switch self {
        case .authorizedAccess:   return "checkmark.shield.fill"
        case .unauthorizedFace:   return "person.fill.xmark"
        case .noFaceLock:         return "lock.fill"
        case .blurActivated:      return "eye.slash.fill"
        case .blurDeactivated:    return "eye.fill"
        case .enrollmentComplete: return "person.badge.plus"
        case .alarmTriggered:     return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .authorizedAccess:   return .cyan
        case .unauthorizedFace:   return .red
        case .noFaceLock:         return .orange
        case .blurActivated:      return .purple
        case .blurDeactivated:    return .green
        case .enrollmentComplete: return .blue
        case .alarmTriggered:     return .red
        }
    }
}


