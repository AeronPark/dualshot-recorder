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
        uiView.updatePiPVisibility(show: cameraManager.isDualModeActive)
    }
}

class PreviewUIView: UIView {
    var cameraManager: CameraManager?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var pipContainerView: UIView?
    private var pipPreviewLayer: AVCaptureVideoPreviewLayer?
    
    // PiP dimensions (16:9 landscape aspect ratio)
    private let pipWidth: CGFloat = 140
    private let pipHeight: CGFloat = 79 // 140 * 9/16
    private let pipMargin: CGFloat = 16
    private let pipCornerRadius: CGFloat = 12
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        setupPiPContainer()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPiPContainer() {
        // Create container with border and shadow
        let container = UIView()
        container.backgroundColor = .black
        container.layer.cornerRadius = pipCornerRadius
        container.layer.borderWidth = 2
        container.layer.borderColor = UIColor.white.cgColor
        container.layer.masksToBounds = true
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOffset = CGSize(width: 0, height: 2)
        container.layer.shadowRadius = 4
        container.layer.shadowOpacity = 0.5
        container.isHidden = true
        addSubview(container)
        pipContainerView = container
        
        // Add "LANDSCAPE" label
        let label = UILabel()
        label.text = "16:9"
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.tag = 100 // For finding later
        container.addSubview(label)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        
        // Position PiP in top-right corner (below safe area)
        if let container = pipContainerView {
            let safeTop = safeAreaInsets.top + 60 // Below top bar
            container.frame = CGRect(
                x: bounds.width - pipWidth - pipMargin,
                y: safeTop,
                width: pipWidth,
                height: pipHeight
            )
            
            pipPreviewLayer?.frame = container.bounds
            
            // Position label at bottom of PiP
            if let label = container.viewWithTag(100) as? UILabel {
                label.frame = CGRect(x: 4, y: pipHeight - 18, width: 32, height: 14)
            }
        }
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
            updatePiPLayer()
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
        
        // Update PiP layer
        updatePiPLayer()
    }
    
    private func updatePiPLayer() {
        guard let cameraManager = cameraManager,
              let container = pipContainerView else { return }
        
        // Check if we have a landscape preview layer from the camera manager
        if let landscapeLayer = cameraManager.landscapePreviewLayer {
            // Remove existing pip layer if different
            if pipPreviewLayer !== landscapeLayer {
                pipPreviewLayer?.removeFromSuperlayer()
                
                landscapeLayer.frame = container.bounds
                landscapeLayer.videoGravity = .resizeAspectFill
                landscapeLayer.cornerRadius = pipCornerRadius
                container.layer.insertSublayer(landscapeLayer, at: 0)
                pipPreviewLayer = landscapeLayer
                
                print("PiP preview layer connected")
            }
        }
    }
    
    func updatePiPVisibility(show: Bool) {
        pipContainerView?.isHidden = !show
        if show {
            updatePiPLayer()
        }
    }
}
