import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    
    // --- MODE TOGGLES ---
    @State private var isCleanupMode: Bool = false
    @State private var isSmileDesignMode: Bool = false
    @State private var showGoldenRatio: Bool = false
    
    // --- SMILE DESIGN STATE ---
    @State private var templateVisible: Bool = false
    @State private var archPosX: Float = 0.0
    @State private var archPosY: Float = 0.0
    @State private var archPosZ: Float = 0.05
    @State private var archWidth: Float = 1.0
    @State private var archCurve: Float = 0.5
    @State private var toothLength: Float = 1.0
    @State private var toothRatio: Float = 0.8
    
    // --- ACTIONS ---
    @State private var triggerDeleteSignal: Bool = false
    @State private var isProcessing: Bool = false
    @State private var statusMessage: String = ""
    @State private var isExporting = false
    @State private var selectedFormat: GeometryUtils.ExportFormat = .stl
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT PANEL
            VStack(alignment: .leading, spacing: 20) {
                Text("Smile Studio").font(.title2).bold().padding(.top)
                
                if session.activeScanURL == nil {
                    ContentUnavailableView("No Scan", systemImage: "cube.transparent")
                } else {
                    Picker("Mode", selection: Binding(
                        get: { isSmileDesignMode ? 1 : 0 },
                        set: { isSmileDesignMode = ($0 == 1); isCleanupMode = ($0 == 0) }
                    )) {
                        Text("Cleanup").tag(0)
                        Text("Design").tag(1)
                    }
                    .pickerStyle(.segmented)
                    
                    Divider()
                    
                    if isCleanupMode {
                        // --- CLEANUP TOOLS ---
                        VStack(alignment: .leading, spacing: 15) {
                            Label("Paint Selection", systemImage: "paintbrush.fill").font(.headline)
                            
                            Group {
                                Text("Instructions:").bold()
                                Text("1. Click & Drag on model to paint RED.").font(.caption)
                                Text("2. Rotate view by switching to 'Design' mode temporarily if needed.").font(.caption).foregroundStyle(.secondary)
                            }
                            
                            Button(role: .destructive) {
                                triggerDeleteSignal = true
                            } label: {
                                if isProcessing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Delete Selected", systemImage: "trash")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isProcessing)
                            .padding(.top)
                        }
                    } else {
                        // --- DESIGN TOOLS ---
                        ScrollView {
                            VStack(alignment: .leading, spacing: 15) {
                                Toggle("Show Template", isOn: $templateVisible)
                                Toggle("Golden Ratio", isOn: $showGoldenRatio)
                                
                                Group {
                                    Text("Position").font(.headline)
                                    SliderRow(label: "Up/Down", value: $archPosY, range: -0.1...0.1)
                                    SliderRow(label: "Left/Right", value: $archPosX, range: -0.05...0.05)
                                    SliderRow(label: "Fwd/Back", value: $archPosZ, range: -0.1...0.2)
                                }
                                Divider()
                                Group {
                                    Text("Shape").font(.headline)
                                    SliderRow(label: "Width", value: $archWidth, range: 0.5...2.0)
                                    SliderRow(label: "Curve", value: $archCurve, range: 0.0...1.0)
                                    SliderRow(label: "Length", value: $toothLength, range: 0.5...2.0)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    if !statusMessage.isEmpty {
                        Text(statusMessage).font(.caption)
                    }
                    
                    Divider()
                    
                    HStack {
                        Picker("", selection: $selectedFormat) {
                            Text("STL").tag(GeometryUtils.ExportFormat.stl)
                            Text("USDZ").tag(GeometryUtils.ExportFormat.usdz)
                        }.frame(width: 80)
                        
                        Button("Export") { isExporting = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(width: 280)
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            // RIGHT PANEL
            if let url = session.activeScanURL {
                DesignSceneWrapper(
                    scanURL: url,
                    isCleanupMode: isCleanupMode,
                    triggerDelete: $triggerDeleteSignal,
                    onDelete: { indices in
                        performDeletion(indices: indices)
                    },
                    showSmileTemplate: isSmileDesignMode && templateVisible,
                    smileParams: SmileTemplateParams(posX: archPosX, posY: archPosY, posZ: archPosZ, scale: archWidth, curve: archCurve, length: toothLength, ratio: toothRatio),
                    showGrid: isSmileDesignMode && showGoldenRatio
                )
                .id(url)
            } else {
                Text("3D Workspace").foregroundStyle(.gray)
            }
        }
        .fileExporter(isPresented: $isExporting, document: GenericFile(sourceURL: session.activeScanURL), contentType: UTType(filenameExtension: selectedFormat.rawValue) ?? .data, defaultFilename: "DentalProject") { _ in }
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

// Helpers
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
