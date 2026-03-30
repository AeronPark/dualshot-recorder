import AVFoundation
import Photos
import SwiftUI
import Combine

// MARK: - Recording Mode
enum RecordingMode: CaseIterable {
    case dual       // Portrait + Landscape simultaneously
    case wideOnly   // Single wide camera
    case ultraWide  // Single ultra-wide camera
    case front      // Front camera
    
    var displayName: String {
        switch self {
        case .dual: return "Dual Output"
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
        case .dual: return "rectangle.portrait.and.arrow.right"
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
    @Published var isSessionRunning = false
    @Published var isDualModeActive = false
    
    // MARK: Private Properties
    private var captureSession: AVCaptureSession?
    
    private var wideCamera: AVCaptureDevice?
    private var ultraWideCamera: AVCaptureDevice?
    private var frontCamera: AVCaptureDevice?
    
    // For dual mode: video data output + asset writers
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    
    // Writer state - accessed from background queues, protected by writerLock
    private let writerLock = NSLock()
    private nonisolated(unsafe) var portraitAssetWriter: AVAssetWriter?
    private nonisolated(unsafe) var portraitVideoInput: AVAssetWriterInput?
    private nonisolated(unsafe) var portraitAudioInput: AVAssetWriterInput?
    
    private nonisolated(unsafe) var landscapeAssetWriter: AVAssetWriter?
    private nonisolated(unsafe) var landscapeVideoInput: AVAssetWriterInput?
    private nonisolated(unsafe) var landscapeAudioInput: AVAssetWriterInput?
    private nonisolated(unsafe) var landscapePixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private nonisolated(unsafe) var portraitVideoURL: URL?
    private nonisolated(unsafe) var landscapeVideoURL: URL?
    
    private nonisolated(unsafe) var isWritingStarted = false
    private nonisolated(unsafe) var sessionStartTime: CMTime?
    
    // For cropping
    private nonisolated(unsafe) var ciContext: CIContext?
    
    // For single mode: movie file output
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var singleVideoURL: URL?
    
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    // Processing queues
    private let videoWritingQueue = DispatchQueue(label: "com.dualshot.videoWriting")
    private let audioWritingQueue = DispatchQueue(label: "com.dualshot.audioWriting")
    
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
    var landscapePreviewLayer: AVCaptureVideoPreviewLayer?
    
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
        
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
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
        if recordingMode == .dual {
            setupDualOutputSession()
        } else {
            setupSingleCamSession()
        }
    }
    
    private func setupDualOutputSession() {
        guard let wideCamera = wideCamera else {
            print("Wide camera not available")
            errorMessage = "Wide camera not available"
            isDualModeActive = false
            recordingMode = .wideOnly
            setupSingleCamSession()
            return
        }
        
        print("Setting up dual output session (portrait + landscape)")
        print("📷 Wide camera: \(wideCamera.localizedName)")
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = selectedResolution == .uhd4k ? .hd4K3840x2160 : .hd1920x1080
        
        do {
            // Camera input
            let videoInput = try AVCaptureDeviceInput(device: wideCamera)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                print("✅ Wide camera input added")
            }
            
            // Audio input
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    print("✅ Audio input added")
                }
            }
            
            // Video data output (for capturing frames)
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: videoWritingQueue)
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
                videoDataOutput = videoOutput
                // Capture in PORTRAIT - frames will be 1080x1920
                if let connection = videoOutput.connection(with: .video) {
                    connection.videoOrientation = .portrait
                    print("📷 Video capture orientation: PORTRAIT")
                }
                print("✅ Video data output added")
            }
            
            // Audio data output
            let audioOutput = AVCaptureAudioDataOutput()
            audioOutput.setSampleBufferDelegate(self, queue: audioWritingQueue)
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
                audioDataOutput = audioOutput
                print("✅ Audio data output added")
            }
            
        } catch {
            errorMessage = "Failed to setup camera: \(error.localizedDescription)"
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
        captureSession = session
        isDualModeActive = true
        
        // Create landscape preview layer (shows 16:9 framing for landscape output)
        let landscapePreview = AVCaptureVideoPreviewLayer(session: session)
        landscapePreview.videoGravity = .resizeAspectFill
        // Set landscape orientation for PiP preview
        if let connection = landscapePreview.connection {
            connection.videoOrientation = .landscapeRight
            print("✅ Landscape PiP preview created with landscapeRight orientation")
        } else {
            print("⚠️ Landscape preview has no connection yet")
        }
        self.landscapePreviewLayer = landscapePreview
        
        print("Dual output session configured")
        
        // Start on background thread AFTER commit is complete
        let sessionToStart = session
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            sessionToStart.startRunning()
            print("Session running: \(sessionToStart.isRunning)")
            DispatchQueue.main.async {
                self?.isSessionRunning = sessionToStart.isRunning
            }
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
            movieFileOutput = movieOutput
            
        } catch {
            errorMessage = "Failed to setup camera: \(error.localizedDescription)"
        }
        
        session.commitConfiguration()
        captureSession = session
        isDualModeActive = false
        
        print("Single cam session configured, starting...")
        
        // Start on background thread AFTER commit is complete
        let sessionToStart = session
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            sessionToStart.startRunning()
            print("Single cam session running: \(sessionToStart.isRunning)")
            DispatchQueue.main.async {
                self?.isSessionRunning = sessionToStart.isRunning
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
        
        if recordingMode == .dual && isDualModeActive {
            startDualRecording(tempDir: tempDir, timestamp: timestamp)
        } else {
            startSingleRecording(tempDir: tempDir, timestamp: timestamp)
        }
        
        isRecording = true
        recordingStartTime = Date()
        startRecordingTimer()
    }
    
    private func startDualRecording(tempDir: URL, timestamp: Int) {
        portraitVideoURL = tempDir.appendingPathComponent("portrait_\(timestamp).\(selectedFileFormat.fileExtension)")
        landscapeVideoURL = tempDir.appendingPathComponent("landscape_\(timestamp).\(selectedFileFormat.fileExtension)")
        
        print("Starting dual recording...")
        print("Portrait: \(portraitVideoURL!.lastPathComponent)")
        print("Landscape: \(landscapeVideoURL!.lastPathComponent)")
        
        // Setup asset writers
        do {
            // Capturing in PORTRAIT orientation, so frames are 9:16 (e.g., 1080x1920)
            // Landscape will be a CENTER CROP of portrait to get 16:9
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2
            ]
            
            // PORTRAIT writer - full frame, no crop
            portraitAssetWriter = try AVAssetWriter(url: portraitVideoURL!, fileType: selectedFileFormat.fileType)
            
            let portraitVideoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: selectedResolution.portraitSize.width,
                AVVideoHeightKey: selectedResolution.portraitSize.height
            ]
            portraitVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: portraitVideoSettings)
            portraitVideoInput?.expectsMediaDataInRealTime = true
            
            portraitAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            portraitAudioInput?.expectsMediaDataInRealTime = true
            
            if let writer = portraitAssetWriter {
                if let videoInput = portraitVideoInput, writer.canAdd(videoInput) {
                    writer.add(videoInput)
                }
                if let audioInput = portraitAudioInput, writer.canAdd(audioInput) {
                    writer.add(audioInput)
                }
            }
            print("✅ Portrait writer configured (full frame)")
            
            // LANDSCAPE writer - center crop of portrait to 16:9
            // For 1080x1920 portrait, landscape crop is 1080x608 (center strip)
            // We'll scale that up to 1920x1080 for proper landscape video
            landscapeAssetWriter = try AVAssetWriter(url: landscapeVideoURL!, fileType: selectedFileFormat.fileType)
            
            let landscapeVideoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: selectedResolution.landscapeSize.width,
                AVVideoHeightKey: selectedResolution.landscapeSize.height
            ]
            landscapeVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: landscapeVideoSettings)
            landscapeVideoInput?.expectsMediaDataInRealTime = true
            
            landscapeAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            landscapeAudioInput?.expectsMediaDataInRealTime = true
            
            // Create pixel buffer adaptor for landscape (to write cropped frames)
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: selectedResolution.landscapeSize.width,
                kCVPixelBufferHeightKey as String: selectedResolution.landscapeSize.height
            ]
            landscapePixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: landscapeVideoInput!,
                sourcePixelBufferAttributes: pixelBufferAttributes
            )
            
            if let writer = landscapeAssetWriter {
                if let videoInput = landscapeVideoInput, writer.canAdd(videoInput) {
                    writer.add(videoInput)
                }
                if let audioInput = landscapeAudioInput, writer.canAdd(audioInput) {
                    writer.add(audioInput)
                }
            }
            
            // Create CIContext for cropping
            ciContext = CIContext(options: [.useSoftwareRenderer: false])
            
            print("✅ Landscape writer configured with pixel buffer adaptor for cropping")
            
            isWritingStarted = false
            sessionStartTime = nil
            
            print("✅ Asset writers configured")
            
        } catch {
            print("❌ Failed to create asset writers: \(error)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    private func startSingleRecording(tempDir: URL, timestamp: Int) {
        singleVideoURL = tempDir.appendingPathComponent("video_\(timestamp).\(selectedFileFormat.fileExtension)")
        
        if let output = movieFileOutput, let url = singleVideoURL {
            output.startRecording(to: url, recordingDelegate: self)
        }
    }
    
    private func stopRecording() {
        print("Stopping recording...")
        
        if recordingMode == .dual && isDualModeActive {
            stopDualRecording()
        } else {
            if let output = movieFileOutput, output.isRecording {
                output.stopRecording()
            }
        }
        
        isRecording = false
        stopRecordingTimer()
    }
    
    private func stopDualRecording() {
        videoWritingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.writerLock.lock()
            
            self.portraitVideoInput?.markAsFinished()
            self.portraitAudioInput?.markAsFinished()
            self.landscapeVideoInput?.markAsFinished()
            self.landscapeAudioInput?.markAsFinished()
            
            let portraitWriter = self.portraitAssetWriter
            let landscapeWriter = self.landscapeAssetWriter
            let portraitURL = self.portraitVideoURL
            let landscapeURL = self.landscapeVideoURL
            
            self.writerLock.unlock()
            
            let group = DispatchGroup()
            
            if let writer = portraitWriter, writer.status == .writing {
                group.enter()
                writer.finishWriting {
                    print("🎬 Portrait recording finished")
                    group.leave()
                }
            }
            
            if let writer = landscapeWriter, writer.status == .writing {
                group.enter()
                writer.finishWriting {
                    print("🎬 Landscape recording finished")
                    group.leave()
                }
            }
            
            group.notify(queue: .main) { [weak self] in
                if let url = portraitURL {
                    self?.saveVideoToPhotos(url: url, name: "Portrait")
                }
                if let url = landscapeURL {
                    self?.saveVideoToPhotos(url: url, name: "Landscape")
                }
                self?.cleanupWriters()
            }
        }
    }
    
    private func saveVideoToPhotos(url: URL, name: String) {
        // Check file exists and has content
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ \(name) file doesn't exist")
            return
        }
        
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attrs[.size] as? Int64 ?? 0
            print("📁 \(name) file size: \(fileSize) bytes")
            
            if fileSize == 0 {
                print("❌ \(name) file is empty")
                return
            }
        } catch {
            print("❌ Cannot read \(name) file attributes: \(error)")
            return
        }
        
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { success, error in
            if success {
                print("✅ \(name) video saved to Photos")
            } else if let error = error {
                print("❌ Failed to save \(name) video: \(error.localizedDescription)")
            }
            
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func cleanupWriters() {
        writerLock.lock()
        portraitAssetWriter = nil
        portraitVideoInput = nil
        portraitAudioInput = nil
        landscapeAssetWriter = nil
        landscapeVideoInput = nil
        landscapeAudioInput = nil
        landscapePixelBufferAdaptor = nil
        portraitVideoURL = nil
        landscapeVideoURL = nil
        isWritingStarted = false
        sessionStartTime = nil
        ciContext = nil
        writerLock.unlock()
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
        guard !isRecording else { return }
        
        let allModes = RecordingMode.allCases
        if let currentIndex = allModes.firstIndex(of: recordingMode) {
            let nextIndex = (currentIndex + 1) % allModes.count
            recordingMode = allModes[nextIndex]
            
            // Restart session with new mode
            stopSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.setupSession()
            }
        }
    }
    
    private func stopSession() {
        captureSession?.stopRunning()
        captureSession = nil
        videoDataOutput = nil
        audioDataOutput = nil
        movieFileOutput = nil
        landscapePreviewLayer = nil
        isDualModeActive = false
        isSessionRunning = false
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
        return captureSession
    }
    
    func startSession() {
        guard let session = captureSession else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if !session.isRunning {
                session.startRunning()
            }
            DispatchQueue.main.async {
                self?.isSessionRunning = session.isRunning
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if output is AVCaptureVideoDataOutput {
            processVideoSampleBuffer(sampleBuffer, timestamp: timestamp)
        } else if output is AVCaptureAudioDataOutput {
            processAudioSampleBuffer(sampleBuffer, timestamp: timestamp)
        }
    }
    
    nonisolated private func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer, timestamp: CMTime) {
        writerLock.lock()
        defer { writerLock.unlock() }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let frameWidth = CVPixelBufferGetWidth(imageBuffer)
        let frameHeight = CVPixelBufferGetHeight(imageBuffer)
        
        // Start writers on first frame
        if !isWritingStarted {
            isWritingStarted = true
            sessionStartTime = timestamp
            
            print("📐 Actual frame dimensions: \(frameWidth) x \(frameHeight)")
            
            portraitAssetWriter?.startWriting()
            portraitAssetWriter?.startSession(atSourceTime: timestamp)
            
            landscapeAssetWriter?.startWriting()
            landscapeAssetWriter?.startSession(atSourceTime: timestamp)
            
            print("✅ Started writing at \(timestamp.seconds)")
        }
        
        // Write full frame to portrait
        if let input = portraitVideoInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
        
        // Crop center for landscape and write
        if let input = landscapeVideoInput, input.isReadyForMoreMediaData,
           let adaptor = landscapePixelBufferAdaptor,
           let context = ciContext {
            
            // Calculate crop rect for 16:9 from portrait (9:16)
            // Portrait is 1080x1920, we need center strip that's 16:9
            // Height of crop = width * 9/16 = 1080 * 9/16 = 607.5 ≈ 608
            let cropHeight = CGFloat(frameWidth) * 9.0 / 16.0
            let cropY = (CGFloat(frameHeight) - cropHeight) / 2.0
            
            // Create CIImage and crop
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let cropRect = CGRect(x: 0, y: cropY, width: CGFloat(frameWidth), height: cropHeight)
            let croppedImage = ciImage.cropped(to: cropRect)
            
            // Scale to landscape dimensions (1920x1080)
            let scaleX = CGFloat(1920) / CGFloat(frameWidth)
            let scaleY = CGFloat(1080) / cropHeight
            let scaledImage = croppedImage
                .transformed(by: CGAffineTransform(translationX: 0, y: -cropY))
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            // Get pixel buffer from pool
            if let pixelBufferPool = adaptor.pixelBufferPool {
                var newPixelBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &newPixelBuffer)
                
                if let outputBuffer = newPixelBuffer {
                    context.render(scaledImage, to: outputBuffer)
                    adaptor.append(outputBuffer, withPresentationTime: timestamp)
                }
            }
        }
    }
    
    nonisolated private func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer, timestamp: CMTime) {
        writerLock.lock()
        defer { writerLock.unlock() }
        
        guard isWritingStarted else { return }
        
        // Write to portrait
        if let input = portraitAudioInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
        
        // Write to landscape
        if let input = landscapeAudioInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("✅ Recording STARTED to: \(fileURL.lastPathComponent)")
    }
    
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        print("🎬 Recording FINISHED: \(outputFileURL.lastPathComponent)")
        
        if let error = error {
            print("❌ Recording error: \(error.localizedDescription)")
            return
        }
        
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        } completionHandler: { success, error in
            if success {
                print("✅ Video saved to Photos")
            } else if let error = error {
                print("❌ Failed to save video: \(error.localizedDescription)")
            }
            
            try? FileManager.default.removeItem(at: outputFileURL)
        }
    }
}
