import SwiftUI
import AVFoundation
import UIKit

/// Custom in-app camera chrome (viewfinder brackets, shutter, flash).
/// Stays open so the user can shoot multiple photos; dismiss with X or Done.
struct PopupCameraView: View {
    var onCapture: (UIImage) -> Void
    var onPickLibrary: (() -> Void)? = nil
    /// When set, shutter stops after this many shots in this session (then Done).
    var maxCaptures: Int? = nil

    @Environment(\.dismiss) private var dismiss

    @StateObject private var session = PopupCameraSession()
    @State private var flashOn = false
    @State private var shutterPulse = false
    @State private var captureFlash = false
    @State private var capturedThumbs: [UIImage] = []
    /// Index of the taken photo being previewed full screen.
    @State private var previewIndex: Int?

    private let accent = Color(red: 0.93, green: 0.18, blue: 0.42)

    private var remainingInSession: Int? {
        guard let maxCaptures else { return nil }
        return max(0, maxCaptures - capturedThumbs.count)
    }

    private var canCaptureMore: Bool {
        remainingInSession.map { $0 > 0 } ?? true
    }

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

            if let previewIndex, !capturedThumbs.isEmpty {
                capturedPreview(startAt: previewIndex)
                    .transition(.opacity)
                    .zIndex(2)
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

    /// Top stays clear apart from the wordmark; the controls sit down by the thumb.
    private var topBar: some View {
        HStack {
            Spacer()
            PopupWordmark(scale: .badge)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            Spacer()
        }
    }

    private var closeButton: some View {
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
        .accessibilityLabel("Close camera")
    }

    private var doneButton: some View {
        Button {
            Motion.haptic(.medium)
            dismiss()
        } label: {
            Text("Done")
                .font(Theme.syne(14, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.white)
                .clipShape(Capsule())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
        .accessibilityLabel("Done, \(capturedThumbs.count) photos")
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            if !capturedThumbs.isEmpty {
                capturedStrip
            }

            // Close and flash just above the shutter row, within thumb reach.
            HStack {
                closeButton
                Spacer()
                Button {
                    Motion.haptic(.light)
                    flashOn.toggle()
                } label: {
                    Image(systemName: flashOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(flashOn ? accent : .white)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.9))
                .accessibilityLabel(flashOn ? "Flash on" : "Flash off")
            }

            HStack(alignment: .center) {
                libraryButton
                    .opacity(onPickLibrary == nil ? 0.35 : 1)
                    .disabled(onPickLibrary == nil)
                    .frame(width: 80, alignment: .leading)

                Spacer()

                shutterButton

                Spacer()

                Group {
                    if capturedThumbs.isEmpty {
                        Color.clear.frame(width: 1, height: 1)
                    } else {
                        doneButton
                    }
                }
                .frame(width: 80, alignment: .trailing)
            }
        }
    }

    private var capturedStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(capturedThumbs.enumerated()), id: \.offset) { idx, thumb in
                        Button {
                            Motion.haptic(.light)
                            withAnimation(.easeOut(duration: 0.18)) { previewIndex = idx }
                        } label: {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
                        .accessibilityLabel("Preview photo \(idx + 1)")
                    }
                }
            }

            Text("\(capturedThumbs.count)")
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.16))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var shutterButton: some View {
        Button {
            guard !session.isCapturing, canCaptureMore else { return }
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
                    withAnimation(Motion.snappy) {
                        capturedThumbs.append(image)
                    }
                    onCapture(image)
                    if !canCaptureMore {
                        // Hit the listing/scanner photo limit — close so they can continue.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            dismiss()
                        }
                    }
                }
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(canCaptureMore ? 0.35 : 0.18), lineWidth: 3)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 70, height: 70)
                Circle()
                    .fill(Color.white.opacity(canCaptureMore ? 1 : 0.35))
                    .frame(width: shutterPulse ? 54 : 60, height: shutterPulse ? 54 : 60)
            }
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))
        .disabled(session.isCapturing || !session.cameraAvailable || !canCaptureMore)
        .accessibilityLabel("Take photo")
    }

    /// Photo library: one plain round button with a label so it reads at a glance.
    private var libraryButton: some View {
        Button {
            Motion.haptic(.light)
            let pick = onPickLibrary
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                pick?()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.white.opacity(0.16)))
                Text("Library")
                    .font(Theme.syne(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
        .accessibilityLabel("Choose from library")
    }

    /// Full-screen look at the photos taken so far; swipe between them.
    private func capturedPreview(startAt index: Int) -> some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: Binding(
                get: { min(previewIndex ?? index, capturedThumbs.count - 1) },
                set: { previewIndex = $0 }
            )) {
                ForEach(Array(capturedThumbs.enumerated()), id: \.offset) { idx, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: capturedThumbs.count > 1 ? .always : .never))
            .ignoresSafeArea()

            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { previewIndex = nil }
                } label: {
                    Label("Back to camera", systemImage: "chevron.left")
                        .font(Theme.syne(15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))

                Spacer()

                Text("\((previewIndex ?? index) + 1) of \(capturedThumbs.count)")
                    .font(Theme.syne(13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
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
