import SwiftUI
import SceneKit
import UniformTypeIdentifiers

// --- DATA MODELS ---
enum DesignMode: Int, CaseIterable, Identifiable {
    case analysis = 0
    case design = 1
    
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .analysis: return "Analysis"
        case .design: return "Design"
        }
    }
}

enum LandmarkType: String, CaseIterable {
    case midline = "Facial Midline"
    case leftCanine = "Left Canine Tip"
    case rightCanine = "Right Canine Tip"
    case lipLine = "Lower Lip Center" // NEW: Helps defining vertical smile position
}

// Data model for tooth offsets
struct ToothState: Equatable {
    var positionOffset: SIMD3<Float> = .zero
    var rotation: SIMD3<Float> = .zero
    var scale: Float = 1.0
}

struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    
    // --- STATE ---
    @State private var currentMode: DesignMode = .analysis
    
    // Analysis / Landmarks
    @State private var landmarks: [LandmarkType: SCNVector3] = [:]
    
    var nextLandmark: LandmarkType? {
        // Enforce a specific order for user guidance
        if landmarks[.midline] == nil { return .midline }
        if landmarks[.leftCanine] == nil { return .leftCanine }
        if landmarks[.rightCanine] == nil { return .rightCanine }
        if landmarks[.lipLine] == nil { return .lipLine }
        return nil
    }
    
    // Design
    @State private var showGoldenRatio: Bool = false
    @State private var templateVisible: Bool = true // Default to true so user sees it immediately
    @State private var toothStates: [String: ToothState] = [:]
    @State private var selectedToothName: String? = nil
    
    // Global Params
    @State private var archPosX: Float = 0.0
    @State private var archPosY: Float = 0.0
    @State private var archPosZ: Float = 0.05
    @State private var archWidth: Float = 1.0
    @State private var archCurve: Float = 0.5
    @State private var toothLength: Float = 1.0
    @State private var toothRatio: Float = 0.8
    
    // Actions
    @State private var statusMessage: String = ""
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showDeleteConfirmation = false
    @State private var selectedFormat: GeometryUtils.ExportFormat = .stl
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT PANEL
            VStack(alignment: .leading, spacing: 20) {
                
                // HEADER
                HStack {
                    Text("Smile Studio").font(.title2).fontWeight(.bold)
                    Spacer()
                    Button(action: { isImporting = true }) { Image(systemName: "square.and.arrow.down") }
                        .buttonStyle(.plain).font(.title2)
                    if session.activeScanURL != nil {
                        Button(action: { showDeleteConfirmation = true }) { Image(systemName: "trash").foregroundStyle(.red) }
                            .buttonStyle(.plain).font(.title2).padding(.leading, 8)
                    }
                }.padding(.top)
                
                Divider()
                
                if session.activeScanURL == nil {
                    ContentUnavailableView("No Model", systemImage: "cube.transparent", description: Text("Scan a patient or import a file."))
                    Button("Import 3D Model") { isImporting = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                } else {
                    
                    // --- MODE PICKER ---
                    Picker("Mode", selection: $currentMode) {
                        ForEach(DesignMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Divider()
                    
                    // --- CONTEXTUAL TOOLS ---
                    switch currentMode {
                    case .analysis:
                        VStack(alignment: .leading, spacing: 15) {
                            Label("Locate Landmarks", systemImage: "scope").font(.headline)
                            
                            if let target = nextLandmark {
                                Text("Click on the patient's:")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(target.rawValue)
                                    .font(.title3).fontWeight(.bold).foregroundStyle(.blue)
                                    .padding(.vertical, 5)
                            } else {
                                VStack(alignment: .leading) {
                                    Text("✅ Analysis Complete").font(.headline).foregroundStyle(.green)
                                    Text("Template has been auto-aligned.").font(.caption)
                                }
                                .padding(.bottom, 10)
                                
                                Button("Go to Design Mode") {
                                    currentMode = .design
                                    templateVisible = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            
                            Divider()
                            Button("Reset Landmarks") { landmarks.removeAll() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        
                    case .design:
                        DesignToolsView(
                            templateVisible: $templateVisible,
                            showGoldenRatio: $showGoldenRatio,
                            selectedToothName: $selectedToothName,
                            toothStates: $toothStates,
                            archPosX: $archPosX, archPosY: $archPosY, archPosZ: $archPosZ,
                            archWidth: $archWidth, archCurve: $archCurve, toothLength: $toothLength, toothRatio: $toothRatio
                        )
                    }
                }
                Spacer()
                if !statusMessage.isEmpty { Text(statusMessage).font(.caption) }
                Divider()
                ExportToolsView(isExporting: $isExporting, selectedFormat: $selectedFormat)
            }
            .frame(width: 280)
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            // RIGHT PANEL
            if let url = session.activeScanURL {
                DesignSceneWrapper(
                    scanURL: url,
                    mode: currentMode,
                    
                    // Smile Design Props
                    showSmileTemplate: (currentMode == .design && templateVisible),
                    smileParams: SmileTemplateParams(
                        posX: archPosX, posY: archPosY, posZ: archPosZ,
                        scale: archWidth, curve: archCurve, length: toothLength, ratio: toothRatio
                    ),
                    toothStates: toothStates,
                    onToothSelected: { name in selectedToothName = name },
                    onToothTransformChange: { name, state in toothStates[name] = state },
                    
                    // Landmarks Props
                    landmarks: landmarks,
                    activeLandmarkType: nextLandmark,
                    onLandmarkPicked: { pos in
                        if let target = nextLandmark {
                            landmarks[target] = pos
                        }
                    },
                    
                    showGrid: (currentMode == .design && showGoldenRatio)
                )
                .id(url)
            } else {
                ZStack {
                    Color(nsColor: .black)
                    Text("3D Workspace").foregroundStyle(.gray)
                }
            }
        }
        .fileExporter(isPresented: $isExporting, document: GenericFile(sourceURL: session.activeScanURL), contentType: UTType(filenameExtension: selectedFormat.rawValue) ?? .data, defaultFilename: "DentalProject") { _ in }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [UTType(filenameExtension: "usdz")!, UTType(filenameExtension: "stl")!]) { result in handleImport(result) }
        .alert("Remove Model?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) { session.activeScanURL = nil }
        } message: {
            Text("This will remove the current model from the scene.")
        }
    }
    
    // (Import Logic remains the same...)
    func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let dstURL = tempDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: dstURL)
                try FileManager.default.copyItem(at: url, to: dstURL)
                DispatchQueue.main.async { session.activeScanURL = dstURL; statusMessage = "✅ Imported" }
            } catch { statusMessage = "❌ Import Failed" }
        case .failure: statusMessage = "❌ Error"
        }
    }
}

// (Keep Subviews DesignToolsView, ExportToolsView, SliderRow etc. as they were)
struct DesignToolsView: View {
    @Binding var templateVisible: Bool
    @Binding var showGoldenRatio: Bool
    @Binding var selectedToothName: String?
    @Binding var toothStates: [String: ToothState]
    @Binding var archPosX: Float; @Binding var archPosY: Float; @Binding var archPosZ: Float
    @Binding var archWidth: Float; @Binding var archCurve: Float; @Binding var toothLength: Float; @Binding var toothRatio: Float
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Toggle("Show Template", isOn: $templateVisible)
                Toggle("Golden Ratio", isOn: $showGoldenRatio)
                Divider()
                if let selected = selectedToothName {
                    Text("Selected: \(selected)").font(.headline).foregroundStyle(.blue)
                    let binding = Binding(get: { toothStates[selected] ?? ToothState() }, set: { toothStates[selected] = $0 })
                    SliderRow(label: "Rotate", value: Binding(get: { binding.wrappedValue.rotation.z }, set: { var n = binding.wrappedValue; n.rotation.z = $0; binding.wrappedValue = n }), range: -1.0...1.0)
                    SliderRow(label: "Scale", value: Binding(get: { binding.wrappedValue.scale }, set: { var n = binding.wrappedValue; n.scale = $0; binding.wrappedValue = n }), range: 0.5...2.0)
                    Button("Deselect") { selectedToothName = nil }.font(.caption)
                } else {
                    Group {
                        Text("Global Position").font(.headline)
                        SliderRow(label: "Up/Down", value: $archPosY, range: -0.1...0.1)
                        SliderRow(label: "Left/Right", value: $archPosX, range: -0.05...0.05)
                        SliderRow(label: "Fwd/Back", value: $archPosZ, range: -0.1...0.2)
                    }
                    Divider()
                    Group {
                        Text("Global Shape").font(.headline)
                        SliderRow(label: "Width", value: $archWidth, range: 0.5...2.0)
                        SliderRow(label: "Curve", value: $archCurve, range: 0.0...1.0)
                        SliderRow(label: "Length", value: $toothLength, range: 0.5...2.0)
                        SliderRow(label: "Ratio", value: $toothRatio, range: 0.5...1.0)
                    }
                }
            }
        }
    }
}

struct ExportToolsView: View {
    @Binding var isExporting: Bool
    @Binding var selectedFormat: GeometryUtils.ExportFormat
    var body: some View {
        HStack {
            Picker("", selection: $selectedFormat) {
                Text("STL").tag(GeometryUtils.ExportFormat.stl)
                Text("USDZ").tag(GeometryUtils.ExportFormat.usdz)
            }.frame(width: 80)
            Button("Export") { isExporting = true }.buttonStyle(.borderedProminent)
        }
    }
}

struct SliderRow: View {
    let label: String; @Binding var value: Float; let range: ClosedRange<Float>
    var body: some View { HStack { Text(label).font(.caption).frame(width: 60, alignment: .leading); Slider(value: $value, in: range) } }
}

struct GenericFile: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "stl")!, UTType(filenameExtension: "usdz")!] }
    var sourceURL: URL?; init(sourceURL: URL?) { self.sourceURL = sourceURL }
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { return FileWrapper(regularFileWithContents: try! Data(contentsOf: sourceURL!)) }
}
