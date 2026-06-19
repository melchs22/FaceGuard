// EnrollmentView.swift
// FaceGuard — SwiftUI enrollment UI with live camera preview, face guide overlay,
// countdown, and progress bar.

import SwiftUI
import AVFoundation
import AppKit

// MARK: - Camera Preview (NSViewRepresentable)

/// Wraps an AVCaptureVideoPreviewLayer inside a SwiftUI-compatible NSView.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view  = NSView()
        view.wantsLayer = true

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(previewLayer)

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let previewLayer = nsView.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = nsView.bounds
        }
    }
}

// MARK: - Enrollment ViewModel

/// Observable state object that drives the enrollment UI.
final class EnrollmentViewModel: ObservableObject {
    @Published var state: EnrollmentState = .idle
    @Published var faceRect: CGRect?        // Normalised face bounding box (0-1, Vision coords)

    let enroller = FaceEnroller()
    weak var windowController: EnrollmentWindowController?

    init() {
        enroller.onStateChange = { [weak self] newState in
            DispatchQueue.main.async { self?.state = newState }
        }
        enroller.onFaceDetected = { [weak self] rect in
            DispatchQueue.main.async { self?.faceRect = rect }
        }
    }

    func startEnrollment() {
        enroller.startEnrollment()
    }

    func cancel() {
        enroller.cancelEnrollment()
        windowController?.close()
    }
}

// MARK: - EnrollmentView

struct EnrollmentView: View {
    @ObservedObject var viewModel: EnrollmentViewModel
    let cameraSession: AVCaptureSession

    // MARK: Body

    var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────────────────
            LinearGradient(
                colors: [Color(hex: "#0f0c29"), Color(hex: "#302b63"), Color(hex: "#24243e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────────────────
                headerSection

                // ── Camera Preview + Guide ───────────────────────────────────
                cameraSection
                    .frame(height: 300)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)

                // ── Status / Controls ────────────────────────────────────────
                statusSection
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)
            }
        }
        .frame(width: 520, height: 580)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "eye.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                Text("FaceGuard")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.top, 28)

            Text("Face Enrollment")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    // MARK: - Camera Section

    private var cameraSection: some View {
        GeometryReader { geo in
            ZStack {
                // Live camera feed
                CameraPreviewView(session: cameraSession)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Circular face guide overlay
                Circle()
                    .stroke(
                        LinearGradient(colors: [.cyan, .purple], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 3, dash: [8, 4])
                    )
                    .frame(width: geo.size.height * 0.72, height: geo.size.height * 0.72)
                    .opacity(0.8)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isEnrolling)

                // Corner scan lines
                ForEach(0..<4) { i in
                    cornerBracket(for: i, size: geo.size)
                }

                // Instructions overlay
                instructionsLabel(size: geo.size)
            }
        }
    }

    private var isEnrolling: Bool {
        if case .enrolling = viewModel.state { return true }
        return false
    }

    private func cornerBracket(for index: Int, size: CGSize) -> some View {
        let w: CGFloat = 24, t: CGFloat = 3
        let xSigns: [CGFloat] = [-1,  1,  1, -1]
        let ySigns: [CGFloat] = [-1, -1,  1,  1]
        let xs = xSigns[index]
        let ys = ySigns[index]
        let inset: CGFloat = 12

        return ZStack {
            Rectangle()
                .fill(Color.cyan.opacity(0.9))
                .frame(width: w, height: t)
                .offset(x: xs * (size.width/2 - inset - w/2),
                        y: ys * (size.height/2 - inset))
            Rectangle()
                .fill(Color.cyan.opacity(0.9))
                .frame(width: t, height: w)
                .offset(x: xs * (size.width/2 - inset),
                        y: ys * (size.height/2 - inset - w/2))
        }
    }

    private func instructionsLabel(size: CGSize) -> some View {
        Text("Centre your face in the circle")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .offset(y: size.height / 2 - 20)
    }

    // MARK: - Status Section

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.state {
        case .idle:
            idleControls
        case .enrolling(let progress, let countdown):
            enrollingUI(progress: progress, countdown: countdown)
        case .success:
            successUI
        case .failed(let reason):
            failedUI(reason: reason)
        }
    }

    private var idleControls: some View {
        VStack(spacing: 16) {
            Text("Look directly at the camera and press Start.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Cancel") { viewModel.cancel() }
                    .buttonStyle(FGSecondaryButtonStyle())

                Button("Start Enrollment") { viewModel.startEnrollment() }
                    .buttonStyle(FGPrimaryButtonStyle())
            }
        }
    }

    private func enrollingUI(progress: Double, countdown: Int) -> some View {
        VStack(spacing: 16) {
            // Countdown
            Text("Hold still… capturing in \(countdown)…")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 8)
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(progress), height: 8)
                        .animation(.linear(duration: 0.3), value: progress)
                }
            }
            .frame(height: 8)

            Text("\(Int(progress * 100))% captured")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private var successUI: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.green)
                Text("Face enrolled successfully. FaceGuard is now active.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(16)
            .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

            Button("Done") { viewModel.windowController?.close() }
                .buttonStyle(FGPrimaryButtonStyle())
        }
    }

    private func failedUI(reason: String) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.red)
                Text(reason)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
            }
            .padding(16)
            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 16) {
                Button("Cancel") { viewModel.cancel() }
                    .buttonStyle(FGSecondaryButtonStyle())
                Button("Try Again") { viewModel.startEnrollment() }
                    .buttonStyle(FGPrimaryButtonStyle())
            }
        }
    }
}

// MARK: - Custom Button Styles

struct FGPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}

struct FGSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
