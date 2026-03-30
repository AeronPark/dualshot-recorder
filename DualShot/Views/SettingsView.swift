import SwiftUI

struct SettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // Resolution Section
                Section("Resolution") {
                    ForEach(VideoResolution.allCases, id: \.self) { resolution in
                        Button(action: { cameraManager.selectedResolution = resolution }) {
                            HStack {
                                Text(resolution.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if cameraManager.selectedResolution == resolution {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                // Frame Rate Section
                Section("Frame Rate") {
                    ForEach(FrameRate.allCases, id: \.self) { frameRate in
                        Button(action: { cameraManager.selectedFrameRate = frameRate }) {
                            HStack {
                                Text(frameRate.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if cameraManager.selectedFrameRate == frameRate {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                // File Format Section
                Section("File Format") {
                    ForEach(VideoFileFormat.allCases, id: \.self) { format in
                        Button(action: { cameraManager.selectedFileFormat = format }) {
                            HStack {
                                Text(format.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if cameraManager.selectedFileFormat == format {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                // Recording Mode Section
                Section("Recording Mode") {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Button(action: { cameraManager.recordingMode = mode }) {
                            HStack {
                                Image(systemName: mode.iconName)
                                    .frame(width: 30)
                                Text(mode.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if cameraManager.recordingMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .disabled(mode == .dual && !cameraManager.isMultiCamSupported)
                    }
                }
                
                // Storage Info
                Section("Storage") {
                    HStack {
                        Text("Available Space")
                        Spacer()
                        Text(cameraManager.availableStorageString)
                            .foregroundColor(.secondary)
                    }
                    
                    // Estimated recording time
                    HStack {
                        Text("Est. Recording Time")
                        Spacer()
                        Text(estimatedRecordingTime())
                            .foregroundColor(.secondary)
                    }
                }
                
                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Multi-Cam Support")
                        Spacer()
                        Text(cameraManager.isMultiCamSupported ? "Yes" : "No")
                            .foregroundColor(cameraManager.isMultiCamSupported ? .green : .red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func estimatedRecordingTime() -> String {
        // Rough estimate: 1080p @ 30fps ≈ 130 MB/min, 4K @ 30fps ≈ 350 MB/min
        let mbPerMinute: Double
        switch (cameraManager.selectedResolution, cameraManager.selectedFrameRate) {
        case (.hd1080p, .fps24): mbPerMinute = 100
        case (.hd1080p, .fps30): mbPerMinute = 130
        case (.hd1080p, .fps60): mbPerMinute = 200
        case (.uhd4k, .fps24): mbPerMinute = 280
        case (.uhd4k, .fps30): mbPerMinute = 350
        case (.uhd4k, .fps60): mbPerMinute = 500
        }
        
        // Double for dual recording
        let totalMbPerMinute = cameraManager.recordingMode == .dual ? mbPerMinute * 2 : mbPerMinute
        
        let availableMB = Double(getAvailableStorage()) / 1_000_000
        let minutes = availableMB / totalMbPerMinute
        
        if minutes > 60 {
            let hours = Int(minutes / 60)
            let mins = Int(minutes.truncatingRemainder(dividingBy: 60))
            return "\(hours)h \(mins)m"
        } else {
            return "\(Int(minutes))m"
        }
    }
    
    private func getAvailableStorage() -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return attrs[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
}

#Preview {
    SettingsView(cameraManager: CameraManager())
}
