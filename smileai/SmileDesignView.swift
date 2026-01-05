import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    
    // Crop Tools
    @State private var isCropMode: Bool = false
    @State private var isProcessingCrop: Bool = false
    
    // Bounds (Meters)
    @State private var minX: Float = -0.1; @State private var maxX: Float = 0.1
    @State private var minY: Float = -0.1; @State private var maxY: Float = 0.1
    @State private var minZ: Float = -0.1; @State private var maxZ: Float = 0.1
    
    // Auto-Ranges
    @State private var rangeMin: Float = -0.5
    @State private var rangeMax: Float = 0.5
    
    // Export
    @State private var isExporting = false
    @State private var selectedFormat: GeometryUtils.ExportFormat = .stl
    @State private var statusMessage = ""
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT PANEL
            VStack(alignment: .leading, spacing: 20) {
                Text("Smile Studio").font(.title2).fontWeight(.bold)
                Divider()
                
                if session.activeScanURL == nil {
                    Text("No Scan Loaded").foregroundStyle(.secondary)
                    Text("Process a scan in the first tab.").font(.caption)
                } else {
                    Toggle("Crop Tool", isOn: $isCropMode)
                        .toggleStyle(.switch)
                    
                    if isCropMode {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Crop Box").font(.headline)
                                    Spacer()
                                    Button("Reset") {
                                        minX = rangeMin; maxX = rangeMax
                                        minY = rangeMin; maxY = rangeMax
                                        minZ = rangeMin; maxZ = rangeMax
                                    }.font(.caption)
                                }
                                CropSlider(label: "Width", minVal: $minX, maxVal: $maxX, range: rangeMin...rangeMax)
                                CropSlider(label: "Height", minVal: $minY, maxVal: $maxY, range: rangeMin...rangeMax)
                                CropSlider(label: "Depth", minVal: $minZ, maxVal: $maxZ, range: rangeMin...rangeMax)
                            }
                        }
                        .frame(maxHeight: 250)
                        
                        // APPLY BUTTON
                        Button {
                            applyCrop()
                        } label: {
                            if isProcessingCrop {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Apply Crop", systemImage: "scissors")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(isProcessingCrop)
                        
                        Divider().padding(.vertical)
                    }
                    
                    // EXPORT CONTROLS
                    VStack(alignment: .leading) {
                        Text("Export Current Model").font(.caption).bold()
                        Picker("Format", selection: $selectedFormat) {
                            Text("STL").tag(GeometryUtils.ExportFormat.stl)
                            Text("OBJ").tag(GeometryUtils.ExportFormat.obj)
                            Text("PLY").tag(GeometryUtils.ExportFormat.ply)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    Button {
                        isExporting = true
                    } label: {
                        Label("Download", systemImage: "arrow.down.doc.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(statusMessage.contains("Success") ? .green : .secondary)
                            .padding(.top, 5)
                    }
                }
                Spacer()
            }
            .frame(width: 280).padding().background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // RIGHT PANEL
            ZStack {
                Color.black
                if let scanURL = session.activeScanURL {
                    DesignSceneWrapper(
                        scanURL: scanURL,
                        isCleanupMode: isCropMode,
                        cropBox: (
                            min: SCNVector3(CGFloat(minX), CGFloat(minY), CGFloat(minZ)),
                            max: SCNVector3(CGFloat(maxX), CGFloat(maxY), CGFloat(maxZ))
                        ),
                        onModelLoaded: { bounds in
                            // Auto-fit Logic
                            self.rangeMin = Float(min(bounds.min.x, min(bounds.min.y, bounds.min.z))) * 1.5
                            self.rangeMax = Float(max(bounds.max.x, max(bounds.max.y, bounds.max.z))) * 1.5
                            self.minX = Float(bounds.min.x); self.maxX = Float(bounds.max.x)
                            self.minY = Float(bounds.min.y); self.maxY = Float(bounds.max.y)
                            self.minZ = Float(bounds.min.z); self.maxZ = Float(bounds.max.z)
                        }
                    )
                    // Forces reload when URL changes (after crop)
                    .id(scanURL)
                } else {
                    Text("Ready").foregroundStyle(.gray)
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: GenericFile(sourceURL: session.activeScanURL),
            contentType: UTType(filenameExtension: selectedFormat.rawValue) ?? .data,
            defaultFilename: "DentalModel"
        ) { result in
            // Handle Export Result
            switch result {
            case .success(let destURL):
                guard let source = session.activeScanURL else { return }
                statusMessage = "Exporting..."
                let fmt = selectedFormat
                
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        // We re-export the CURRENT model to the requested format
                        // This handles conversion (e.g. USDZ -> STL)
                        try GeometryUtils.cropAndExport(sourceURL: source, destinationURL: destURL, bounds: GeometryUtils.CropBounds(
                            // Pass massive bounds to keep everything, just essentially converting format
                            min: SCNVector3(-100,-100,-100), max: SCNVector3(100,100,100)
                        ), format: fmt)
                        DispatchQueue.main.async { statusMessage = "✅ Export Success!" }
                    } catch {
                        DispatchQueue.main.async { statusMessage = "❌ Error: \(error.localizedDescription)" }
                    }
                }
            case .failure: break
            }
        }
    }
    
    func applyCrop() {
        guard let source = session.activeScanURL else { return }
        isProcessingCrop = true
        statusMessage = "Cropping..."
        
        let bounds = GeometryUtils.CropBounds(
            min: SCNVector3(CGFloat(minX), CGFloat(minY), CGFloat(minZ)),
            max: SCNVector3(CGFloat(maxX), CGFloat(maxY), CGFloat(maxZ))
        )
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let newFileName = "Cropped_\(UUID().uuidString).usdz"
                let destURL = tempDir.appendingPathComponent(newFileName)
                
                // Crop to USDZ for internal preview
                try GeometryUtils.cropAndExport(sourceURL: source, destinationURL: destURL, bounds: bounds, format: .usdz)
                
                DispatchQueue.main.async {
                    // Update Session -> Triggers View Reload
                    session.activeScanURL = destURL
                    isProcessingCrop = false
                    isCropMode = false // Exit tool
                    statusMessage = "✅ Crop Applied"
                }
            } catch {
                DispatchQueue.main.async {
                    isProcessingCrop = false
                    statusMessage = "❌ Crop Failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// Helpers
struct CropSlider: View {
    let label: String
    @Binding var minVal: Float
    @Binding var maxVal: Float
    let range: ClosedRange<Float>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).bold()
            HStack {
                Text("Min")
                Slider(value: Binding(get: { Double(minVal) }, set: { minVal = Float($0) }), in: Double(range.lowerBound)...Double(range.upperBound))
                Text("Max")
                Slider(value: Binding(get: { Double(maxVal) }, set: { maxVal = Float($0) }), in: Double(range.lowerBound)...Double(range.upperBound))
            }
        }
    }
}

struct GenericFile: FileDocument {
    static var readableContentTypes: [UTType] {
        [UTType(filenameExtension: "stl")!, UTType(filenameExtension: "obj")!, UTType(filenameExtension: "ply")!, UTType(filenameExtension: "usdz")!]
    }
    var sourceURL: URL?
    init(sourceURL: URL?) { self.sourceURL = sourceURL }
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: Data())
    }
}
