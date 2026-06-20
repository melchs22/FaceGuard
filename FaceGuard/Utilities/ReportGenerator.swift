// ReportGenerator.swift
// FaceGuard — Generates a beautiful HTML security report from the event log.

import Foundation
import AppKit

final class ReportGenerator {

    static let shared = ReportGenerator()
    private init() {}

    func generateHTMLReport() -> String {
        let events   = EventLog.shared.events
        let weekEvents = EventLog.shared.eventsForCurrentWeek()
        let hourly   = EventLog.shared.eventsGroupedByHour()

        let intrusions = weekEvents.filter { $0.type == .unauthorizedFace || $0.type == .noFaceLock }.count
        let blurs      = weekEvents.filter { $0.type == .blurActivated }.count
        let authorized = weekEvents.filter { $0.type == .authorizedAccess }.count
        let alarms     = weekEvents.filter { $0.type == .alarmTriggered }.count

        let dateStr = Date().formatted(date: .long, time: .omitted)

        // Build heatmap bars
        let maxH = max(hourly.values.max() ?? 1, 1)
        let heatBars = (0..<24).map { h -> String in
            let count = hourly[h] ?? 0
            let height = Int(Double(count) / Double(maxH) * 80 + 4)
            let ratio  = Double(count) / Double(maxH)
            let color  = ratio < 0.33 ? "#22c55e" : (ratio < 0.66 ? "#eab308" : "#ef4444")
            return """
            <div style="display:flex;flex-direction:column;align-items:center;gap:3px;">
              <div style="width:22px;height:\(height)px;background:\(color);border-radius:4px;"></div>
              <span style="font-size:9px;color:#666;">\(h % 6 == 0 ? "\(h)h" : "")</span>
            </div>
            """
        }.joined()

        // Build event rows
        let eventRows = events.reversed().prefix(100).map { ev -> String in
            let icon: String
            switch ev.type {
            case .unauthorizedFace:   icon = "🚨"
            case .noFaceLock:         icon = "🔒"
            case .blurActivated:      icon = "🫥"
            case .alarmTriggered:     icon = "🔔"
            case .authorizedAccess:   icon = "✅"
            case .blurDeactivated:    icon = "👁"
            case .enrollmentComplete: icon = "📸"
            }
            let ts = ev.timestamp.formatted(date: .abbreviated, time: .standard)
            return """
            <tr>
              <td>\(icon)</td>
              <td>\(ev.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)</td>
              <td>\(ts)</td>
            </tr>
            """
        }.joined()

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <title>FaceGuard Security Report — \(dateStr)</title>
        <style>
          * { margin:0; padding:0; box-sizing:border-box; }
          body { background:#0a0a1a; color:#e5e7eb; font-family:-apple-system,BlinkMacSystemFont,sans-serif; padding:40px; }
          h1 { font-size:2rem; font-weight:800; background:linear-gradient(90deg,#06b6d4,#a855f7); -webkit-background-clip:text; -webkit-text-fill-color:transparent; }
          .subtitle { color:#6b7280; font-size:0.9rem; margin-top:4px; }
          .cards { display:grid; grid-template-columns:repeat(4,1fr); gap:16px; margin:28px 0; }
          .card { background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); border-radius:14px; padding:20px; }
          .card-val { font-size:2.5rem; font-weight:800; color:#fff; }
          .card-label { font-size:0.75rem; color:#9ca3af; margin-top:4px; }
          .section-title { font-size:1rem; font-weight:600; color:rgba(255,255,255,0.8); margin-bottom:12px; }
          .heatmap { display:flex; align-items:flex-end; gap:4px; background:rgba(255,255,255,0.04); border-radius:14px; padding:20px; }
          table { width:100%; border-collapse:collapse; margin-top:12px; }
          th { text-align:left; font-size:0.75rem; color:#6b7280; padding:8px 12px; border-bottom:1px solid rgba(255,255,255,0.08); }
          td { padding:10px 12px; font-size:0.85rem; border-bottom:1px solid rgba(255,255,255,0.04); }
          .footer { color:#4b5563; font-size:0.75rem; margin-top:40px; text-align:center; }
        </style>
        </head>
        <body>
          <h1>FaceGuard Security Report</h1>
          <p class="subtitle">Generated on \(dateStr)</p>

          <div class="cards">
            <div class="card"><div class="card-val">\(intrusions)</div><div class="card-label">Intrusions This Week</div></div>
            <div class="card"><div class="card-val">\(blurs)</div><div class="card-label">Privacy Blurs Activated</div></div>
            <div class="card"><div class="card-val">\(authorized)</div><div class="card-label">Authorized Accesses</div></div>
            <div class="card"><div class="card-val">\(alarms)</div><div class="card-label">Alarms Triggered</div></div>
          </div>

          <p class="section-title">Risk Heatmap — By Hour of Day</p>
          <div class="heatmap">\(heatBars)</div>

          <p class="section-title" style="margin-top:28px;">All Events (Last 100)</p>
          <table>
            <tr><th>Type</th><th>Event</th><th>Timestamp</th></tr>
            \(eventRows)
          </table>

          <div class="footer">FaceGuard · All face data stays 100% on-device.</div>
        </body>
        </html>
        """
    }
}
