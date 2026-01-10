//
//  Smile2DOverlaySheet.swift
//  smileai
//
//  2D Smile Overlay System - Main Integration Wrapper
//  Phase 5: Integration
//

import SwiftUI
import SceneKit

/// Main sheet view for 2D smile overlay functionality
struct Smile2DOverlaySheet: View {
    
    // MARK: - Properties
    
    /// Source intraoral photo
    let sourcePhoto: NSImage?
    
    /// Reference to tooth library manager
    let toothLibrary: ToothLibraryManager?
    
    /// Completion handler
    let onSave: (NSImage) -> Void
    
    // MARK: - State
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var state = SmileOverlayState()
    @State private var isLoadingLibrary = false
    @State private var projectionQuality: [ProjectionQuality] = []
    @State private var showQualityReport = false
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            headerToolbar
            
            Divider()
            
            // Main canvas
            SmileOverlayCanvas(state: state)
            
            // Status bar
            statusBar
        }
        .frame(minWidth: 1200, minHeight: 800)
        .onAppear {
            if let photo = sourcePhoto {
                state.loadPhoto(photo)
            }
        }
    }
    
    // MARK: - Header Toolbar
    
    private var headerToolbar: some View {
        HStack {
            // Title
            Text("2D Smile Design Overlay")
                .font(.headline)
            
            Spacer()
            
            // Load Library button
            Button(action: { loadTeethFromLibrary() }) {
                Label(
                    "Load Tooth Library",
                    systemImage: "tray.and.arrow.down"
                )
            }
            .disabled(toothLibrary == nil || isLoadingLibrary)
            
            // Quality report button
            if !projectionQuality.isEmpty {
                Button(action: { showQualityReport.toggle() }) {
                    Label(
                        "Quality Report",
                        systemImage: "checkmark.seal"
                    )
                }
                .popover(isPresented: $showQualityReport) {
                    qualityReportView
                }
            }
            
            Divider()
            
            // Export button
            Button(action: { exportAnnotatedImage() }) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!state.hasContent)
            
            // Done button
            Button("Done") {
                dismiss()
            }
        }
        .padding()
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            // Photo info
            if let photo = state.sourcePhoto {
                Label(
                    "\(Int(photo.size.width)) × \(Int(photo.size.height)) px",
                    systemImage: "photo"
                )
                .font(.caption)
                .foregroundColor(.secondary)
                
                Divider()
            }
            
            // Calibration info
            Label(
                "\(String(format: "%.1f", state.pixelsPerMM)) px/mm",
                systemImage: "ruler"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            
            Divider()
            
            // Tooth count
            Label(
                "\(state.toothOverlays.count) teeth",
                systemImage: "tooth"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            
            Spacer()
            
            // Loading indicator
            if isLoadingLibrary {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading teeth...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Quality Report View
    
    private var qualityReportView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Projection Quality Report")
                .font(.headline)
            
            ForEach(Array(zip(state.toothOverlays.indices, projectionQuality)), id: \.0) { index, quality in
                HStack {
                    // Tooth number
                    Text(state.toothOverlays[index].toothNumber)
                        .font(.caption.monospaced())
                        .frame(width: 40)
                    
                    // Quality indicator
                    qualityIndicator(for: quality.level)
                    
                    // Score
                    Text("\(Int(quality.score * 100))%")
                        .font(.caption)
                        .frame(width: 50)
                    
                    // Issues
                    if !quality.issues.isEmpty {
                        Text(quality.issues.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Close") {
                    showQualityReport = false
                }
            }
        }
        .padding()
        .frame(width: 500)
    }
    
    private func qualityIndicator(for level: ProjectionQuality.Level) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForQuality(level))
                .frame(width: 8, height: 8)
            
            Text(labelForQuality(level))
                .font(.caption)
                .foregroundColor(colorForQuality(level))
        }
        .frame(width: 80, alignment: .leading)
    }
    
    private func colorForQuality(_ level: ProjectionQuality.Level) -> Color {
        switch level {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .poor: return .red
        }
    }
    
    private func labelForQuality(_ level: ProjectionQuality.Level) -> String {
        switch level {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
    
    // MARK: - Actions
    
    private func loadTeethFromLibrary() {
        guard let library = toothLibrary,
              let photo = state.sourcePhoto else {
            return
        }
        
        isLoadingLibrary = true
        projectionQuality.removeAll()
        
        // Perform projection on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            // Create calibration
            let calibration = CameraCalibrationData.estimate(from: photo)
            let projector = LibraryProjector(calibration: calibration)
            
            var projectedTeeth: [ToothOverlay2D] = []
            var qualities: [ProjectionQuality] = []
            
            // Project each tooth type
            let toothTypes: [ToothType] = [.central, .lateral, .canine, .premolar]
            
            for toothType in toothTypes {
                // Instantiate tooth from library
                if let tooth3D = library.instantiateTooth(type: toothType) {
                    // Project to 2D
                    let tooth2D = projector.project(
                        tooth: tooth3D,
                        toPhotoSize: state.photoSize
                    )
                    
                    // Assess quality
                    let quality = projector.assessProjectionQuality(tooth: tooth2D)
                    
                    projectedTeeth.append(tooth2D)
                    qualities.append(quality)
                }
            }
            
            // Update state on main thread
            DispatchQueue.main.async {
                state.toothOverlays = projectedTeeth
                projectionQuality = qualities
                isLoadingLibrary = false
                
                // Position teeth in arch formation
                positionTeethInArch()
            }
        }
    }
    
    private func positionTeethInArch() {
        guard !state.toothOverlays.isEmpty else { return }
        
        let centerX = state.photoSize.width / 2
        let centerY = state.photoSize.height / 2
        
        let toothCount = state.toothOverlays.count
        let archWidth: CGFloat = 400 // Total arch width in pixels
        let spacing = archWidth / CGFloat(toothCount - 1)
        
        for i in 0..<toothCount {
            let x = centerX - archWidth/2 + CGFloat(i) * spacing
            let y = centerY
            
            state.toothOverlays[i].moveTo(CGPoint(x: x, y: y))
        }
    }
    
    private func exportAnnotatedImage() {
        // Render canvas to image
        let renderer = ImageRenderer(content: SmileOverlayCanvas(state: state))
        renderer.scale = 2.0 // High resolution
        
        guard let image = renderer.nsImage else {
            print("Failed to render image")
            return
        }
        
        // Save dialog
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.nameFieldStringValue = "smile_design_\(Date().timeIntervalSince1970).png"
        savePanel.message = "Export annotated smile design"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                return
            }
            
            // Save image
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                
                do {
                    try pngData.write(to: url)
                    onSave(image)
                    
                    // Success notification
                    let notification = NSUserNotification()
                    notification.title = "Export Complete"
                    notification.informativeText = "Smile design saved to \(url.lastPathComponent)"
                    NSUserNotificationCenter.default.deliver(notification)
                } catch {
                    print("Failed to save image: \(error)")
                }
            }
        }
    }
}

// MARK: - Integration Helper

extension Smile2DOverlaySheet {
    
    /// Create sheet from existing photo
    static func fromPhoto(
        _ photo: NSImage,
        toothLibrary: ToothLibraryManager?,
        onSave: @escaping (NSImage) -> Void
    ) -> some View {
        return Smile2DOverlaySheet(
            sourcePhoto: photo,
            toothLibrary: toothLibrary,
            onSave: onSave
        )
    }
    
    /// Create sheet with photo picker
    static func withPhotoPicker(
        toothLibrary: ToothLibraryManager?,
        onSave: @escaping (NSImage) -> Void
    ) -> some View {
        return Smile2DOverlaySheet(
            sourcePhoto: nil,
            toothLibrary: toothLibrary,
            onSave: onSave
        )
    }
}

// MARK: - Usage Example

/*
 
 // In your main SmileDesignView.swift:
 
 import SwiftUI
 
 struct SmileDesignView: View {
     @State private var show2DOverlay = false
     @State private var overlayPhoto: NSImage? = nil
     
     var body: some View {
         VStack {
             // Your existing UI
             
             Button("2D Smile Overlay") {
                 show2DOverlay = true
             }
         }
         .sheet(isPresented: $show2DOverlay) {
             Smile2DOverlaySheet(
                 sourcePhoto: overlayPhoto,
                 toothLibrary: yourToothLibraryManager,
                 onSave: { image in
                     print("Saved overlay: \(image)")
                 }
             )
         }
     }
 }
 
 */

// MARK: - Preview

#if DEBUG
struct Smile2DOverlaySheet_Previews: PreviewProvider {
    static var previews: some View {
        Smile2DOverlaySheet(
            sourcePhoto: nil,
            toothLibrary: nil,
            onSave: { _ in }
        )
    }
}
#endif
