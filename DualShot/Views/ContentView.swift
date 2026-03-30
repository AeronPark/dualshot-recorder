import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreviewView(cameraManager: cameraManager)
                .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top bar
                TopBarView(
                    cameraManager: cameraManager,
                    showSettings: $showSettings
                )
                
                Spacer()
                
                // Recording indicator
                if cameraManager.isRecording {
                    RecordingIndicatorView(duration: cameraManager.recordingDuration)
                        .padding(.bottom, 20)
                }
                
                // Mode status indicator
                if cameraManager.recordingMode == .dual {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(cameraManager.isDualModeActive ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(cameraManager.isDualModeActive ? "Dual Cameras Active" : "Dual Mode Unavailable")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6))
                    .cornerRadius(12)
                }
                
                // Bottom controls
                BottomControlsView(cameraManager: cameraManager)
                    .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(cameraManager: cameraManager)
        }
        .onAppear {
            cameraManager.checkPermissions()
        }
        .onChange(of: cameraManager.permissionGranted) { _, granted in
            if granted {
                // Give session time to setup, then start
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    cameraManager.startSession()
                }
            }
        }
    }
}

// MARK: - Top Bar
struct TopBarView: View {
    @ObservedObject var cameraManager: CameraManager
    @Binding var showSettings: Bool
    
    var body: some View {
        HStack {
            // Torch button
            Button(action: { cameraManager.toggleTorch() }) {
                Image(systemName: cameraManager.isTorchOn ? "bolt.fill" : "bolt.slash")
                    .font(.title2)
                    .foregroundColor(cameraManager.isTorchOn ? .yellow : .white)
                    .frame(width: 44, height: 44)
            }
            .disabled(cameraManager.isRecording)
            
            Spacer()
            
            // Resolution badge
            Text(cameraManager.selectedResolution.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            
            Spacer()
            
            // Settings button
            Button(action: { showSettings = true }) {
                Image(systemName: "gear")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .disabled(cameraManager.isRecording)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

// MARK: - Recording Indicator
struct RecordingIndicatorView: View {
    let duration: TimeInterval
    @State private var isBlinking = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .opacity(isBlinking ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: isBlinking)
            
            Text(formatDuration(duration))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.red.opacity(0.8))
        .cornerRadius(20)
        .onAppear { isBlinking = true }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Bottom Controls
struct BottomControlsView: View {
    @ObservedObject var cameraManager: CameraManager
    
    var body: some View {
        HStack(spacing: 60) {
            // Mode selector
            Button(action: { cameraManager.cycleMode() }) {
                VStack(spacing: 4) {
                    Image(systemName: cameraManager.recordingMode.iconName)
                        .font(.title2)
                    Text(cameraManager.recordingMode.shortName)
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
            }
            .disabled(cameraManager.isRecording)
            
            // Record button
            Button(action: { cameraManager.toggleRecording() }) {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    if cameraManager.isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.red)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 64, height: 64)
                    }
                }
            }
            
            // Storage indicator
            VStack(spacing: 4) {
                Image(systemName: "internaldrive")
                    .font(.title2)
                Text(cameraManager.availableStorageString)
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .frame(width: 60, height: 60)
        }
    }
}

#Preview {
    ContentView()
}
