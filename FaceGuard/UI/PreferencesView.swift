// PreferencesView.swift
// FaceGuard — SwiftUI preferences panel with all user-configurable settings.

import SwiftUI
import ServiceManagement

// MARK: - PreferencesView

struct PreferencesView: View {

    // MARK: - Observed Settings

    @State private var similarityThreshold: Double = Settings.shared.similarityThreshold
    @State private var noFaceLockDelay: Double     = Settings.shared.noFaceLockDelay
    @State private var strangerCooldown: Double    = Settings.shared.strangerCooldownSeconds
    @State private var showWarning: Bool           = Settings.shared.showWarningBeforeLock
    @State private var warningDuration: Int        = Settings.shared.warningCountdownDuration
    @State private var showMatchScore: Bool        = Settings.shared.showMatchScoreInMenu
    @State private var saveSnapshots: Bool         = Settings.shared.saveIntruderSnapshots
    @State private var launchAtLogin: Bool         = Settings.shared.launchAtLogin
    @State private var enrolledThumbnail: NSImage? = EmbeddingStore.shared.loadThumbnail()
    @State private var showResetConfirm: Bool      = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "#0f0c29"), Color(hex: "#1a1a2e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    prefHeader
                    Divider().background(Color.white.opacity(0.1)).padding(.horizontal, 24)

                    // ── Sections ──────────────────────────────────────────────
                    sectionCard("Face Matching", icon: "person.fill.viewfinder") {
                        faceMatchingSection
                    }
                    sectionCard("Lock Behaviour", icon: "lock.fill") {
                        lockBehaviourSection
                    }
                    sectionCard("Privacy & Logging", icon: "eye.slash.fill") {
                        privacySection
                    }
                    sectionCard("App Behaviour", icon: "gear") {
                        appBehaviourSection
                    }
                    sectionCard("Enrolled Face", icon: "faceid") {
                        enrolledFaceSection
                    }

                    // ── Footer Actions ────────────────────────────────────────
                    footerActions
                        .padding(.bottom, 32)
                }
            }
        }
        .frame(width: 520, height: 680)
    }

    // MARK: - Header

    private var prefHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 22))
                .foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing))
            Text("Preferences")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            Text("100% Local & Private")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.green.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.15), in: Capsule())
                .overlay(Capsule().stroke(Color.green.opacity(0.3), lineWidth: 1))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    // MARK: - Section Builder

    private func sectionCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.cyan.opacity(0.8))
            content()
        }
        .padding(20)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Face Matching Section

    private var faceMatchingSection: some View {
        VStack(spacing: 16) {
            prefSlider(
                label:  "Sensitivity Threshold",
                value:  $similarityThreshold,
                range:  0.60...0.90,
                format: "\(Int(similarityThreshold * 100))%",
                hint:   "Higher = stricter matching (fewer false passes)"
            ) { Settings.shared.similarityThreshold = similarityThreshold }

            prefSlider(
                label:  "Stranger Cooldown",
                value:  $strangerCooldown,
                range:  1...10,
                format: "\(Int(strangerCooldown))s",
                hint:   "How long an unauthorized face must persist before locking"
            ) { Settings.shared.strangerCooldownSeconds = strangerCooldown }
        }
    }

    // MARK: - Lock Behaviour Section

    private var lockBehaviourSection: some View {
        VStack(spacing: 16) {
            prefSlider(
                label:  "No-Face Lock Delay",
                value:  $noFaceLockDelay,
                range:  3...60,
                format: "\(Int(noFaceLockDelay))s",
                hint:   "Seconds before locking when no face is detected"
            ) { Settings.shared.noFaceLockDelay = noFaceLockDelay }

            prefToggle(label: "Show Warning Before Locking", value: $showWarning) {
                Settings.shared.showWarningBeforeLock = showWarning
            }

            if showWarning {
                HStack {
                    Text("Warning Countdown")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                    Picker("", selection: $warningDuration) {
                        Text("2s").tag(2)
                        Text("3s").tag(3)
                        Text("5s").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .colorMultiply(.cyan)
                    .onChange(of: warningDuration) { _ in
                        Settings.shared.warningCountdownDuration = warningDuration
                    }
                }
            }
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(spacing: 12) {
            prefToggle(label: "Show Match Score in Menu Bar", value: $showMatchScore) {
                Settings.shared.showMatchScoreInMenu = showMatchScore
            }
            prefToggle(label: "Save Intruder Snapshots", value: $saveSnapshots) {
                Settings.shared.saveIntruderSnapshots = saveSnapshots
            }
            Button {
                AppLogger.shared.openLogDirectoryInFinder()
            } label: {
                Label("Open Log Folder in Finder", systemImage: "folder.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.cyan)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - App Behaviour Section

    private var appBehaviourSection: some View {
        prefToggle(label: "Launch FaceGuard at Login", value: $launchAtLogin) {
            Settings.shared.launchAtLogin = launchAtLogin
            toggleLoginItem(enabled: launchAtLogin)
        }
    }

    // MARK: - Enrolled Face Section

    private var enrolledFaceSection: some View {
        HStack(spacing: 16) {
            if let thumb = enrolledThumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(LinearGradient(colors: [.cyan, .purple], startPoint: .top, endPoint: .bottom), lineWidth: 2))
            } else {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.3))
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(EmbeddingStore.shared.hasStoredEmbedding ? "Face Enrolled" : "Not Enrolled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                if let stored = EmbeddingStore.shared.loadPool() {
                    Text("Enrolled on \(stored.lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer()
            Button("Re-enroll") {
                NotificationCenter.default.post(name: .openEnrollmentWindow, object: nil)
            }
            .buttonStyle(FGSecondaryButtonStyle())
        }
    }

    // MARK: - Footer

    private var footerActions: some View {
        HStack {
            Button {
                showResetConfirm = true
            } label: {
                Label("Reset All Settings", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Reset all settings to defaults?", isPresented: $showResetConfirm) {
                Button("Reset", role: .destructive) { Settings.shared.resetToDefaults(); loadCurrentValues() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - Reusable Row Builders

    private func prefSlider(
        label: String, value: Binding<Double>,
        range: ClosedRange<Double>, format: String,
        hint: String, onChange: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(format)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .frame(width: 50, alignment: .trailing)
            }
            Slider(value: value, in: range) { _ in onChange() }
                .accentColor(.cyan)
            Text(hint)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private func prefToggle(label: String, value: Binding<Bool>, onChange: @escaping () -> Void) -> some View {
        Toggle(isOn: value) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
        }
        .toggleStyle(SwitchToggleStyle(tint: .cyan))
        .onChange(of: value.wrappedValue) { _ in onChange() }
    }

    // MARK: - Helpers

    private func loadCurrentValues() {
        similarityThreshold = Settings.shared.similarityThreshold
        noFaceLockDelay     = Settings.shared.noFaceLockDelay
        strangerCooldown    = Settings.shared.strangerCooldownSeconds
        showWarning         = Settings.shared.showWarningBeforeLock
        warningDuration     = Settings.shared.warningCountdownDuration
        showMatchScore      = Settings.shared.showMatchScoreInMenu
        saveSnapshots       = Settings.shared.saveIntruderSnapshots
        launchAtLogin       = Settings.shared.launchAtLogin
    }

    private func toggleLoginItem(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    AppLogger.shared.info("PreferencesView: Registered login item.")
                } else {
                    try SMAppService.mainApp.unregister()
                    AppLogger.shared.info("PreferencesView: Unregistered login item.")
                }
            } catch {
                AppLogger.shared.error("PreferencesView: SMAppService error — \(error)")
            }
        }
    }
}


