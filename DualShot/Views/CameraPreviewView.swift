import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.cameraManager = cameraManager
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.updateSession()
    }
}

class PreviewUIView: UIView {
    var cameraManager: CameraManager?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    func updateSession() {
        guard let cameraManager = cameraManager else { return }
        
        // Get the active session
        guard let session = cameraManager.getActiveSession() else {
            // Session not ready yet, try again shortly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.updateSession()
            }
            return
        }
        
        // If we already have a preview layer with this session, just update frame
        if let existingLayer = previewLayer, existingLayer.session === session {
            existingLayer.frame = bounds
            return
        }
        
        // Remove old preview layer
        previewLayer?.removeFromSuperlayer()
        
        // Create new preview layer
        let newPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        newPreviewLayer.frame = bounds
        newPreviewLayer.videoGravity = .resizeAspectFill
        layer.insertSublayer(newPreviewLayer, at: 0)
        previewLayer = newPreviewLayer
        
        print("Preview layer connected to session: \(session)")
    }
}
