import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    
    // --- MODE TOGGLES ---
    @State private var isCropMode: Bool = false
    @State private var isSmileDesignMode: Bool = false
    @State private var showGoldenRatio: Bool = false
    
    // --- CROP STATE ---
    @State private var isProcessingCrop: Bool = false
    @State private var minX: Float = -0.1; @State private var maxX: Float = 0.1
    @State private var minY: Float = -0.1; @State private var maxY: Float = 0.1
    @State private var minZ: Float = -0.1; @State private var maxZ: Float = 0.1
    @State private var rangeMin: Float = -0.5
    @State private var rangeMax: Float = 0.5
    
    // --- SMILE DESIGN STATE (Exocad-style) ---
    @State private var templateVisible: Bool = false
    // Position
    @State private var archPosX: Float = 0.0
    @State private var archPosY: Float = 0.0
    @State private var archPosZ: Float = 0.05
    // Shape
    @State private var archWidth: Float = 1.0
    @State private var archCurve: Float = 0.5
    @State private var toothLength: Float = 1.0
    @State private var toothRatio: Float = 0.8 // Width/Length ratio
    
    // Export
    @State private var isExporting = false
    @State private var selectedFormat: GeometryUtils.ExportFormat = .stl
    @State private var statusMessage = ""
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT PANEL (Tools)
            VStack(alignment: .leading, spacing: 20) {
                Text("Smile Studio")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Divider()
                
                if session.activeScanURL == nil {
                    ContentUnavailableView("No Scan Loaded", systemImage: "cube.transparent", description: Text("Process a scan in the first tab to begin."))
                } else {
                    // --- TOOL SELECTION ---
                    Picker("Mode", selection: Binding(
                        get: { isSmileDesignMode ? 1 : 0 },
                        set: { isSmileDesignMode = ($0 == 1); isCropMode = ($0 == 0) }
                    )) {
                        Text("Cleanup & Crop").tag(0)
                        Text("Smile Creator").tag(1)
                    }
                    .pickerStyle(.segmented)
                    
                    Divider()
                    
                    if isSmileDesignMode {
                        // --- SMILE CREATOR CONTROLS ---
                        ScrollView {
                            VStack(alignment: .leading, spacing: 15) {
                                Toggle("Show Template", isOn: $templateVisible)
                                    .toggleStyle(.switch)
                                
                                Toggle("Golden Ratio Grid", isOn: $showGoldenRatio)
                                    .toggleStyle(.switch)
                                
                                Group {
                                    Text("Position").font(.headline).padding(.top, 5)
                                    SliderRow(label: "Up/Down", value: $archPosY, range: -0.1...0.1)
                                    SliderRow(label: "Left/Right", value: $archPosX, range: -0.05...0.05)
                                    SliderRow(label: "Fwd/Back", value: $archPosZ, range: -0.1...0.2)
                                }
                                
                                Divider()
                                
                                Group {
                                    Text("Esthetics").font(.headline).padding(.top, 5)
                                    SliderRow(label: "Arch Width", value: $archWidth, range: 0.8...1.2)
                                    SliderRow(label: "Smile Curve", value: $archCurve, range: 0.0...1.0)
                                    SliderRow(label: "Tooth Length", value: $toothLength, range: 0.8...1.5)
                                    SliderRow(label: "W/L Ratio", value: $toothRatio, range: 0.6...1.0)
                                }
                            }
                            .padding(.horizontal, 5)
                        }
                    } else {
                        // --- CROP CONTROLS ---
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Bounding Box").font(.headline)
                                    Spacer()
                                    Button("Reset") {
                                        minX = rangeMin; maxX = rangeMax
                                        minY = rangeMin; maxY = rangeMax
                                        minZ = rangeMin; maxZ = rangeMax
                                    }.font(.caption)
                                }
                                CropSlider(label: "Width (X)", minVal: $minX, maxVal: $maxX, range: rangeMin...rangeMax)
                                CropSlider(label: "Height (Y)", minVal: $minY, maxVal: $maxY, range: rangeMin...rangeMax)
                                CropSlider(label: "Depth (Z)", minVal: $minZ, maxVal: $maxZ, range: rangeMin...rangeMax)
                                
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
                                .padding(.top)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // --- EXPORT ---
                    Divider()
                    HStack {
                        Picker("", selection: $selectedFormat) {
                            Text("STL").tag(GeometryUtils.ExportFormat.stl)
                            Text("OBJ").tag(GeometryUtils.ExportFormat.obj)
                            Text("USDZ").tag(GeometryUtils.ExportFormat.usdz)
                        }
                        .frame(width: 80)
                        
                        Button {
                            isExporting = true
                        } label: {
                            Text("Export Model")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(statusMessage.contains("Success") ? .green : .secondary)
                    }
                }
            }
            .frame(width: 300)
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // RIGHT PANEL (3D View)
            ZStack {
                Color.black
                if let scanURL = session.activeScanURL {
                    DesignSceneWrapper(
                        scanURL: scanURL,
                        // Crop Params
                        isCleanupMode: isCropMode && !isSmileDesignMode,
                        cropBox: (
                            min: SCNVector3(CGFloat(minX), CGFloat(minY), CGFloat(minZ)),
                            max: SCNVector3(CGFloat(maxX), CGFloat(maxY), CGFloat(maxZ))
                        ),
                        // Smile Design Params
                        showSmileTemplate: isSmileDesignMode && templateVisible,
                        smileParams: SmileTemplateParams(
                            posX: archPosX, posY: archPosY, posZ: archPosZ,
                            scale: archWidth, curve: archCurve,
                            length: toothLength, ratio: toothRatio
                        ),
                        showGrid: isSmileDesignMode && showGoldenRatio,
                        // Callbacks
                        onModelLoaded: { bounds in
                            self.rangeMin = Float(min(bounds.min.x, min(bounds.min.y, bounds.min.z))) * 1.5
                            self.rangeMax = Float(max(bounds.max.x, max(bounds.max.y, bounds.max.z))) * 1.5
                            self.minX = Float(bounds.min.x); self.maxX = Float(bounds.max.x)
                            self.minY = Float(bounds.min.y); self.maxY = Float(bounds.max.y)
                            self.minZ = Float(bounds.min.z); self.maxZ = Float(bounds.max.z)
                        }
                    )
                    .id(scanURL) // Reload on URL change
                } else {
                    Text("3D Workspace").foregroundStyle(.gray)
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: GenericFile(sourceURL: session.activeScanURL),
            contentType: UTType(filenameExtension: selectedFormat.rawValue) ?? .data,
            defaultFilename: "DentalProject"
        ) { result in
            handleExport(result)
        }
    }
    
    // MARK: - Logic
    
    func applyCrop() {
        guard let source = session.activeScanURL else { return }
        isProcessingCrop = true
        statusMessage = "Cropping geometry..."
        
        let bounds = GeometryUtils.CropBounds(
            min: SCNVector3(CGFloat(minX), CGFloat(minY), CGFloat(minZ)),
            max: SCNVector3(CGFloat(maxX), CGFloat(maxY), CGFloat(maxZ))
        )
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let newFileName = "Cropped_\(UUID().uuidString).usdz"
                let destURL = tempDir.appendingPathComponent(newFileName)
                try GeometryUtils.cropAndExport(sourceURL: source, destinationURL: destURL, bounds: bounds, format: .usdz)
                
                DispatchQueue.main.async {
                    session.activeScanURL = destURL
                    isProcessingCrop = false
                    statusMessage = "✅ Crop Applied"
                }
            } catch {
                DispatchQueue.main.async {
                    isProcessingCrop = false
                    statusMessage = "❌ Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let destURL):
            guard let source = session.activeScanURL else { return }
            statusMessage = "Exporting..."
            let fmt = selectedFormat
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Export current model (without visual crop box)
                    try GeometryUtils.cropAndExport(sourceURL: source, destinationURL: destURL, bounds: GeometryUtils.CropBounds(
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

// MARK: - Subviews

struct SliderRow: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    
    var body: some View {
        HStack {
            Text(label).font(.caption).frame(width: 70, alignment: .leading)
            Slider(value: $value, in: range)
        }
    }
}

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
