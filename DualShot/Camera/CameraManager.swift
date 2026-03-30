import AVFoundation
import Photos
import SwiftUI
import Combine

// MARK: - Recording Mode
enum RecordingMode: CaseIterable {
    case dual       // Both cameras simultaneously
    case wideOnly   // Single wide camera
    case ultraWide  // Single ultra-wide camera
    case front      // Front camera
    
    var displayName: String {
        switch self {
        case .dual: return "Dual Camera"
        case .wideOnly: return "Wide"
        case .ultraWide: return "Ultra Wide"
        case .front: return "Front"
        }
    }
    
    var shortName: String {
        switch self {
        case .dual: return "DUAL"
        case .wideOnly: return "WIDE"
        case .ultraWide: return "0.5x"
        case .front: return "FRONT"
        }
    }
    
    var iconName: String {
        switch self {
        case .dual: return "camera.on.rectangle"
        case .wideOnly: return "camera"
        case .ultraWide: return "camera.aperture"
        case .front: return "camera.rotate"
        }
    }
}

// MARK: - Video Resolution
enum VideoResolution: CaseIterable {
    case hd1080p
    case uhd4k
    
    var displayName: String {
        switch self {
        case .hd1080p: return "1080p"
        case .uhd4k: return "4K"
        }
    }
    
    var portraitSize: CGSize {
        switch self {
        case .hd1080p: return CGSize(width: 1080, height: 1920)
        case .uhd4k: return CGSize(width: 2160, height: 3840)
        }
    }
    
    var landscapeSize: CGSize {
        switch self {
        case .hd1080p: return CGSize(width: 1920, height: 1080)
        case .uhd4k: return CGSize(width: 3840, height: 2160)
        }
    }
}

// MARK: - Frame Rate
enum FrameRate: Int, CaseIterable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60
    
    var displayName: String {
        return "\(rawValue) fps"
    }
}

// MARK: - File Format
enum VideoFileFormat: CaseIterable {
    case mov
    case mp4
    
    var displayName: String {
        switch self {
        case .mov: return "MOV"
        case .mp4: return "MP4"
        }
    }
    
    var fileExtension: String {
        switch self {
        case .mov: return "mov"
        case .mp4: return "mp4"
        }
    }
    
    var fileType: AVFileType {
        switch self {
        case .mov: return .mov
        case .mp4: return .mp4
        }
    }
}

// MARK: - Camera Manager
@MainActor
class CameraManager: NSObject, ObservableObject {
    // MARK: Published Properties
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var isTorchOn = false
    @Published var recordingMode: RecordingMode = .dual
    @Published var selectedResolution: VideoResolution = .hd1080p
    @Published var selectedFrameRate: FrameRate = .fps30
    @Published var selectedFileFormat: VideoFileFormat = .mov
    @Published var permissionGranted = false
    @Published var errorMessage: String?
    
    // MARK: Private Properties
    private var multiCamSession: AVCaptureMultiCamSession?
    private var singleCamSession: AVCaptureSession?
    
    private var wideCamera: AVCaptureDevice?
    private var ultraWideCamera: AVCaptureDevice?
    private var frontCamera: AVCaptureDevice?
    
    private var portraitMovieOutput: AVCaptureMovieFileOutput?
    private var landscapeMovieOutput: AVCaptureMovieFileOutput?
    private var singleMovieOutput: AVCaptureMovieFileOutput?
    
    private var portraitVideoURL: URL?
    private var landscapeVideoURL: URL?
    private var singleVideoURL: URL?
    
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    // MARK: Computed Properties
    var availableStorageString: String {
        let freeSpace = availableStorage()
        let gb = Double(freeSpace) / 1_000_000_000
        return String(format: "%.1f GB", gb)
    }
    
    var isMultiCamSupported: Bool {
        return AVCaptureMultiCamSession.isMultiCamSupported
    }
    
    // MARK: Preview Layer
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    // MARK: Initialization
    override init() {
        super.init()
        setupCameras()
    }
    
    // MARK: Permission Check
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.permissionGranted = granted
                    if granted {
                        self?.setupSession()
                    }
                }
            }
        default:
            permissionGranted = false
            errorMessage = "Camera access denied. Please enable in Settings."
        }
        
        // Also request microphone access
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        
        // Request photo library access for saving
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
    }
    
    // MARK: Camera Setup
    private func setupCameras() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
            mediaType: .video,
            position: .back
        )
        
        for device in discoverySession.devices {
            switch device.deviceType {
            case .builtInWideAngleCamera:
                wideCamera = device
            case .builtInUltraWideCamera:
                ultraWideCamera = device
            default:
                break
            }
        }
        
        frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }
    
    // MARK: Session Setup
    private func setupSession() {
        if recordingMode == .dual && isMultiCamSupported {
            setupMultiCamSession()
        } else {
            setupSingleCamSession()
        }
    }
    
    private func setupMultiCamSession() {
        guard isMultiCamSupported else {
            errorMessage = "Multi-cam not supported on this device"
            recordingMode = .wideOnly
            setupSingleCamSession()
            return
        }
        
        guard let wideCamera = wideCamera, let ultraWideCamera = ultraWideCamera else {
            errorMessage = "Dual cameras not available"
            recordingMode = .wideOnly
            setupSingleCamSession()
            return
        }
        
        let session = AVCaptureMultiCamSession()
        
        session.beginConfiguration()
        
        do {
            // Wide camera input (for landscape)
            let wideInput = try AVCaptureDeviceInput(device: wideCamera)
            if session.canAddInput(wideInput) {
                session.addInputWithNoConnections(wideInput)
            }
            
            // Ultra-wide camera input (for portrait)
            let ultraWideInput = try AVCaptureDeviceInput(device: ultraWideCamera)
            if session.canAddInput(ultraWideInput) {
                session.addInputWithNoConnections(ultraWideInput)
            }
            
            // Audio input
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
                if session.canAddInput(audioInput) {
                    session.addInputWithNoConnections(audioInput)
                }
            }
            
            // Portrait output (from ultra-wide)
            let portraitOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(portraitOutput) {
                session.addOutputWithNoConnections(portraitOutput)
                
                // Connect ultra-wide video
                if let ultraWidePort = ultraWideInput.ports(for: .video, sourceDeviceType: .builtInUltraWideCamera, sourceDevicePosition: .back).first {
                    let connection = AVCaptureConnection(inputPorts: [ultraWidePort], output: portraitOutput)
                    connection.videoOrientation = .portrait
                    if session.canAddConnection(connection) {
                        session.addConnection(connection)
                    }
                }
            }
            portraitMovieOutput = portraitOutput
            
            // Landscape output (from wide)
            let landscapeOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(landscapeOutput) {
                session.addOutputWithNoConnections(landscapeOutput)
                
                // Connect wide video
                if let widePort = wideInput.ports(for: .video, sourceDeviceType: .builtInWideAngleCamera, sourceDevicePosition: .back).first {
                    let connection = AVCaptureConnection(inputPorts: [widePort], output: landscapeOutput)
                    connection.videoOrientation = .landscapeRight
                    if session.canAddConnection(connection) {
                        session.addConnection(connection)
                    }
                }
            }
            landscapeMovieOutput = landscapeOutput
            
        } catch {
            errorMessage = "Failed to setup multi-cam: \(error.localizedDescription)"
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
        multiCamSession = session
        
        // Start session on background thread
        Task.detached { [weak session] in
            session?.startRunning()
        }
    }
    
    private func setupSingleCamSession() {
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = selectedResolution == .uhd4k ? .hd4K3840x2160 : .hd1920x1080
        
        let camera: AVCaptureDevice?
        switch recordingMode {
        case .dual, .wideOnly:
            camera = wideCamera
        case .ultraWide:
            camera = ultraWideCamera
        case .front:
            camera = frontCamera
        }
        
        guard let camera = camera else {
            errorMessage = "Camera not available"
            session.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // Audio input
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            }
            
            let movieOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            singleMovieOutput = movieOutput
            
        } catch {
            errorMessage = "Failed to setup camera: \(error.localizedDescription)"
        }
        
        session.commitConfiguration()
        singleCamSession = session
        
        print("Single cam session configured, starting...")
        Task.detached { [weak self, weak session] in
            session?.startRunning()
            print("Single cam session running: \(session?.isRunning ?? false)")
            await MainActor.run {
                self?.isSessionRunning = session?.isRunning ?? false
            }
        }
    }
    
    // MARK: Recording Control
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        
        if recordingMode == .dual && multiCamSession != nil {
            // Dual recording
            portraitVideoURL = tempDir.appendingPathComponent("portrait_\(timestamp).\(selectedFileFormat.fileExtension)")
            landscapeVideoURL = tempDir.appendingPathComponent("landscape_\(timestamp).\(selectedFileFormat.fileExtension)")
            
            portraitMovieOutput?.startRecording(to: portraitVideoURL!, recordingDelegate: self)
            landscapeMovieOutput?.startRecording(to: landscapeVideoURL!, recordingDelegate: self)
        } else {
            // Single camera recording
            singleVideoURL = tempDir.appendingPathComponent("video_\(timestamp).\(selectedFileFormat.fileExtension)")
            singleMovieOutput?.startRecording(to: singleVideoURL!, recordingDelegate: self)
        }
        
        isRecording = true
        recordingStartTime = Date()
        startRecordingTimer()
    }
    
    private func stopRecording() {
        portraitMovieOutput?.stopRecording()
        landscapeMovieOutput?.stopRecording()
        singleMovieOutput?.stopRecording()
        
        isRecording = false
        stopRecordingTimer()
    }
    
    // MARK: Timer
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
        recordingStartTime = nil
    }
    
    // MARK: Torch Control
    func toggleTorch() {
        guard let device = wideCamera, device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = isTorchOn ? .off : .on
            device.unlockForConfiguration()
            isTorchOn.toggle()
        } catch {
            errorMessage = "Failed to toggle torch"
        }
    }
    
    // MARK: Mode Cycling
    func cycleMode() {
        let allModes = RecordingMode.allCases
        if let currentIndex = allModes.firstIndex(of: recordingMode) {
            let nextIndex = (currentIndex + 1) % allModes.count
            recordingMode = allModes[nextIndex]
            
            // Restart session with new mode
            stopSession()
            setupSession()
        }
    }
    
    private func stopSession() {
        multiCamSession?.stopRunning()
        singleCamSession?.stopRunning()
        multiCamSession = nil
        singleCamSession = nil
    }
    
    // MARK: Storage
    private func availableStorage() -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSpace = attrs[.systemFreeSize] as? Int64 {
                return freeSpace
            }
        } catch {
            print("Error getting storage: \(error)")
        }
        return 0
    }
    
    // MARK: Get Active Session
    func getActiveSession() -> AVCaptureSession? {
        if recordingMode == .dual && multiCamSession != nil {
            return multiCamSession
        } else {
            return singleCamSession
        }
    }
    
    // MARK: Session Running State
    @Published var isSessionRunning = false
    
    func startSession() {
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            if let session = await self.getActiveSession() {
                if !session.isRunning {
                    session.startRunning()
                    print("Session started running")
                }
                await MainActor.run {
                    self.isSessionRunning = session.isRunning
                }
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Recording error: \(error.localizedDescription)")
            return
        }
        
        // Save to Photos library
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        } completionHandler: { success, error in
            if success {
                print("Video saved to Photos: \(outputFileURL.lastPathComponent)")
            } else if let error = error {
                print("Failed to save video: \(error.localizedDescription)")
            }
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: outputFileURL)
        }
    }
}
