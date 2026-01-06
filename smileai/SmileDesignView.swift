import SwiftUI
import SceneKit
import UniformTypeIdentifiers

// --- NEW: Data Models ---
enum DesignMode: Int, CaseIterable, Identifiable {
    case cleanup = 0
    case analysis = 1
    case design = 2
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .cleanup: return "Cleanup"
        case .analysis: return "Analysis"
        case .design: return "Design"
        }
    }
}

enum LandmarkType: String, CaseIterable {
    case midline = "Facial Midline"
    case leftCanine = "Left Canine Tip"
    case rightCanine = "Right Canine Tip"
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
    @State private var currentMode: DesignMode = .cleanup // Replaces bool toggles
    
    // Analysis / Landmarks
    @State private var landmarks: [LandmarkType: SCNVector3] = [:]
    // Helper to determine which landmark to click next
    var nextLandmark: LandmarkType? {
        if landmarks[.midline] == nil { return .midline }
        if landmarks[.leftCanine] == nil { return .leftCanine }
        if landmarks[.rightCanine] == nil { return .rightCanine }
        return nil
    }
    
    // Design
    @State private var showGoldenRatio: Bool = false
    @State private var templateVisible: Bool = false
    @State private var toothStates: [String: ToothState] = [:]
    @State private var selectedToothName: String? = nil
    
    // Global Params (Legacy/Fallback)
    @State private var archPosX: Float = 0.0
    @State private var archPosY: Float = 0.0
    @State private var archPosZ: Float = 0.05
    @State private var archWidth: Float = 1.0
    @State private var archCurve: Float = 0.5
    @State private var toothLength: Float = 1.0
    @State private var toothRatio: Float = 0.8
    
    // Actions
    @State private var triggerDeleteSignal: Bool = false
    @State private var isProcessing: Bool = false
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
                    // Import Button
                    Button(action: { isImporting = true }) { Image(systemName: "square.and.arrow.down") }
                        .buttonStyle(.plain).font(.title2)
                    // Delete Button
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
                    
                    // --- MODE PICKER (Updated) ---
                    Picker("Mode", selection: $currentMode) {
                        ForEach(DesignMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Divider()
                    
                    // --- CONTEXTUAL TOOLS ---
                    switch currentMode {
                    case .cleanup:
                        CleanupToolsView(triggerDeleteSignal: $triggerDeleteSignal, isProcessing: isProcessing)
                        
                    case .analysis:
                        // --- ANALYSIS UI ---
                        VStack(alignment: .leading, spacing: 15) {
                            Label("Locate Landmarks", systemImage: "scope").font(.headline)
                            
                            if let target = nextLandmark {
                                Text("Click on the patient's:")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(target.rawValue)
                                    .font(.title3).fontWeight(.bold).foregroundStyle(.blue)
                                    .padding(.vertical, 5)
                            } else {
                                Text("✅ Analysis Complete").font(.headline).foregroundStyle(.green)
                                Text("Switch to Design Mode to see the aligned template.").font(.caption)
                            }
                            
                            Divider()
                            
                            Button("Reset Landmarks") {
                                landmarks.removeAll()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
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
                    mode: currentMode, // Pass Enum
                    triggerDelete: $triggerDeleteSignal,
                    onDelete: { indices in performDeletion(indices: indices) },
                    
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
                    activeLandmarkType: nextLandmark, // Tell Scene which one we are looking for
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
            Text("This will remove the current model from the scene. Unsaved changes will be lost.")
        }
    }
    
    // MARK: - Logic (Retained from original file)
    
    func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                statusMessage = "❌ Permission denied."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let dstURL = tempDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: dstURL)
                try FileManager.default.copyItem(at: url, to: dstURL)
                
                DispatchQueue.main.async {
                    session.activeScanURL = dstURL
                    statusMessage = "✅ Imported: \(url.lastPathComponent)"
                }
            } catch {
                statusMessage = "❌ Import Failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            statusMessage = "❌ Import Error: \(error.localizedDescription)"
        }
    }
    
    func performDeletion(indices: Set<Int>) {
        guard let source = session.activeScanURL else { return }
        isProcessing = true
        statusMessage = "Processing..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let newFile = tempDir.appendingPathComponent("Cleaned_\(UUID().uuidString).usdz")
                
                try GeometryUtils.deleteVertices(
                    sourceURL: source,
                    destinationURL: newFile,
                    indicesToDelete: indices,
                    format: .usdz
                )
                
                DispatchQueue.main.async {
                    session.activeScanURL = newFile
                    isProcessing = false
                    statusMessage = "✅ Area Deleted"
                }
            } catch {
                DispatchQueue.main.async {
                    isProcessing = false
                    statusMessage = "❌ Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Subviews for Cleaner UI

struct CleanupToolsView: View {
    @Binding var triggerDeleteSignal: Bool
    var isProcessing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Paint Selection", systemImage: "paintbrush.fill").font(.headline)
            Group {
                Text("Instructions:").bold()
                Text("1. Click & Drag on model to paint RED.").font(.caption)
                Text("2. Rotate view by switching to 'Design' mode temporarily if needed.").font(.caption).foregroundStyle(.secondary)
            }
            Button(role: .destructive) { triggerDeleteSignal = true } label: {
                if isProcessing { ProgressView().controlSize(.small) } else {
                    Label("Delete Selected", systemImage: "trash").frame(maxWidth: .infinity)
                }
            }.buttonStyle(.borderedProminent).disabled(isProcessing).padding(.top)
        }
    }
}

struct DesignToolsView: View {
    @Binding var templateVisible: Bool
    @Binding var showGoldenRatio: Bool
    @Binding var selectedToothName: String?
    @Binding var toothStates: [String: ToothState]
    // Global Bindings
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

// Helpers (Retained)
struct SliderRow: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var body: some View {
        HStack { Text(label).font(.caption).frame(width: 60, alignment: .leading); Slider(value: $value, in: range) }
    }
}
struct GenericFile: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "stl")!, UTType(filenameExtension: "usdz")!] }
    var sourceURL: URL?
    init(sourceURL: URL?) { self.sourceURL = sourceURL }
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: try! Data(contentsOf: sourceURL!))
    }
}
