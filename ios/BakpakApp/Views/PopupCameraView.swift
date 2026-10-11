import SwiftUI
import AVFoundation
import UIKit

/// Custom in-app camera chrome (viewfinder brackets, shutter, flash).
struct PopupCameraView: View {
    var onCapture: (UIImage) -> Void
    var onPickLibrary: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @StateObject private var session = PopupCameraSession()
    @State private var flashOn = false
    @State private var shutterPulse = false
    @State private var captureFlash = false

    private let accent = Color(red: 0.93, green: 0.18, blue: 0.42)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if session.cameraAvailable {
                CameraPreviewRepresentable(session: session.captureSession)
                    .ignoresSafeArea()
            } else {
                simulatorPlaceholder
            }

            // Soft vignette so chrome reads against any scene.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.45),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.55),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            viewfinderBrackets
                .padding(.horizontal, 36)
                .padding(.vertical, 120)
                .allowsHitTesting(false)

            GeometryReader { geo in
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 18)
                        .padding(.top, max(geo.safeAreaInsets.top, 12))

                    Spacer()

                    bottomBar
                        .padding(.horizontal, 28)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 16) + 16)
                }
            }

            if captureFlash {
                Color.white.opacity(0.55)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            session.configure()
            session.start()
            session.setTorch(flashOn)
        }
        .onDisappear {
            session.stop()
        }
        .onChange(of: flashOn) { on in
            session.setTorch(on)
        }
        .alert("Camera error", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(alignment: .top) {
            Button {
                Motion.haptic(.light)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.9))

            Spacer()

            Text("popup")
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            chromeSquareButton(systemName: "photo.on.rectangle") {
                Motion.haptic(.light)
                let pick = onPickLibrary
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    pick?()
                }
            }
            .opacity(onPickLibrary == nil ? 0.35 : 1)
            .disabled(onPickLibrary == nil)

            Spacer()

            shutterButton

            Spacer()

            chromeSquareButton(
                systemName: flashOn ? "bolt.fill" : "bolt.slash.fill",
                accentBorder: flashOn
            ) {
                Motion.haptic(.light)
                flashOn.toggle()
            }
        }
    }

    private var shutterButton: some View {
        Button {
            guard !session.isCapturing else { return }
            Motion.haptic(.medium)
            withAnimation(.easeOut(duration: 0.12)) { shutterPulse = true }
            withAnimation(.easeOut(duration: 0.08)) { captureFlash = true }
            session.capturePhoto { image in
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        shutterPulse = false
                        captureFlash = false
                    }
                    guard let image else { return }
                    onCapture(image)
                    dismiss()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 3)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 70, height: 70)
                Circle()
                    .fill(Color.white)
                    .frame(width: shutterPulse ? 54 : 60, height: shutterPulse ? 54 : 60)
            }
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
        .disabled(session.isCapturing || !session.cameraAvailable)
        .accessibilityLabel("Take photo")
    }

    private func chromeSquareButton(
        systemName: String,
        accentBorder: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accentBorder ? accent : .white)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accentBorder ? accent.opacity(0.85) : Color.white.opacity(0.14), lineWidth: accentBorder ? 1.5 : 1)
                )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
    }

    private var viewfinderBrackets: some View {
        GeometryReader { geo in
            let length: CGFloat = 28
            let thickness: CGFloat = 2.5
            let color = Color.white.opacity(0.92)
            ZStack {
                // Top-left
                Path { p in
                    p.move(to: CGPoint(x: 0, y: length))
                    p.addLine(to: .zero)
                    p.addLine(to: CGPoint(x: length, y: 0))
                }
                .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))

                // Top-right
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width - length, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width, y: length))
                }
                .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))

                // Bottom-left
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height - length))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.addLine(to: CGPoint(x: length, y: geo.size.height))
                }
                .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))

                // Bottom-right
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width - length, y: geo.size.height))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - length))
                }
                .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var simulatorPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera preview")
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(.white)
            Text("Use a device for live capture, or pick from your library.")
                .font(Theme.syne(13))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Session

@MainActor
final class PopupCameraSession: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()
    @Published var cameraAvailable = false
    @Published var isCapturing = false
    @Published var errorMessage: String?

    private let sessionQueue = DispatchQueue(label: "com.popup.app.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var photoContinuation: ((UIImage?) -> Void)?
    private var configured = false

    func configure() {
        guard !configured else { return }
        configured = true

        #if targetEnvironment(simulator)
        cameraAvailable = false
        return
        #else
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAvailable = false
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .photo

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.captureSession.canAddInput(input)
            else {
                DispatchQueue.main.async {
                    self.cameraAvailable = false
                    self.errorMessage = "Couldn't start the camera."
                }
                self.captureSession.commitConfiguration()
                return
            }

            self.device = device
            self.captureSession.addInput(input)

            if self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
            }

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.cameraAvailable = true
            }
        }
        #endif
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning, !self.captureSession.inputs.isEmpty {
                self.captureSession.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
        setTorch(false)
    }

    func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let device = self?.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                if on, device.isTorchModeSupported(.on) {
                    try device.setTorchModeOn(level: 1.0)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        #if targetEnvironment(simulator)
        completion(nil)
        errorMessage = "Camera capture needs a physical iPhone."
        return
        #endif

        guard cameraAvailable, !isCapturing else { return }
        isCapturing = true
        photoContinuation = completion

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            if let device = self.device, device.hasFlash {
                settings.flashMode = device.torchMode == .on ? .off : .auto
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension PopupCameraSession: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        let image = data.flatMap { UIImage(data: $0) }
        Task { @MainActor in
            self.isCapturing = false
            let callback = self.photoContinuation
            self.photoContinuation = nil
            if let error {
                self.errorMessage = error.localizedDescription
                callback?(nil)
            } else {
                callback?(image)
            }
        }
    }
}

// MARK: - Preview layer

private struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
