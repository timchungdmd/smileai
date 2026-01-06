import SwiftUI
import SceneKit
import UniformTypeIdentifiers

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
    case lipLine = "Lower Lip Center"
}

struct ToothState: Equatable {
    var positionOffset: SIMD3<Float> = .zero
    var rotation: SIMD3<Float> = .zero
    var scale: Float = 1.0
}

struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    @State private var currentMode: DesignMode = .analysis
    @State private var landmarks: [LandmarkType: SCNVector3] = [:]
    
    var nextLandmark: LandmarkType? {
        if landmarks[.midline] == nil { return .midline }
        if landmarks[.leftCanine] == nil { return .leftCanine }
        if landmarks[.rightCanine] == nil { return .rightCanine }
        if landmarks[.lipLine] == nil { return .lipLine }
        return nil
    }
    
    @State private var showGoldenRatio: Bool = false
    @State private var templateVisible: Bool = true
    @State private var toothStates: [String: ToothState] = [:]
    @State private var selectedToothName: String? = nil
    
    @State private var archPosX: Float = 0.0
    @State private var archPosY: Float = 0.0
    @State private var archPosZ: Float = 0.05
    @State private var archWidth: Float = 1.0
    @State private var archCurve: Float = 0.5
    @State private var toothLength: Float = 1.0
    @State private var toothRatio: Float = 0.8
    
    @State private var statusMessage: String = ""
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showDeleteConfirmation = false
    @State private var selectedFormat: GeometryUtils.ExportFormat = .stl
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Smile Studio").font(.title2).fontWeight(.bold)
                    Spacer()
                    Button(action: { isImporting = true }) { Image(systemName: "square.and.arrow.down") }.buttonStyle(.plain).font(.title2)
                    if session.activeScanURL != nil {
                        Button(action: { showDeleteConfirmation = true }) { Image(systemName: "trash").foregroundStyle(.red) }.buttonStyle(.plain).font(.title2).padding(.leading, 8)
                    }
                }.padding(.top)
                
                Divider()
                
                if session.activeScanURL == nil {
                    ContentUnavailableView("No Model", systemImage: "cube.transparent", description: Text("Scan a patient or import a file."))
                    Button("Import 3D Model") { isImporting = true }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                } else {
                    Picker("Mode", selection: $currentMode) {
                        ForEach(DesignMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }.pickerStyle(.segmented)
                    
                    Divider()
                    
                    switch currentMode {
                    case .analysis:
                        VStack(alignment: .leading, spacing: 15) {
                            Label("Locate Landmarks", systemImage: "scope").font(.headline)
                            if let target = nextLandmark {
                                Text("Click on the patient's:").font(.caption).foregroundStyle(.secondary)
                                Text(target.rawValue).font(.title3).fontWeight(.bold).foregroundStyle(.blue).padding(.vertical, 5)
                            } else {
                                VStack(alignment: .leading) {
                                    Text("✅ Analysis Complete").font(.headline).foregroundStyle(.green)
                                    Text("Model aligned to landmarks.").font(.caption)
                                }.padding(.bottom, 10)
                                Button("Go to Design Mode") { currentMode = .design; templateVisible = true }.buttonStyle(.borderedProminent)
                            }
                            Divider()
                            Button("Reset Landmarks") { landmarks.removeAll() }.buttonStyle(.bordered).controlSize(.small)
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
            .frame(width: 280).padding().background(Color(nsColor: .windowBackgroundColor))
            
            if let url = session.activeScanURL {
                DesignSceneWrapper(
                    scanURL: url,
                    mode: currentMode,
                    showSmileTemplate: (currentMode == .design && templateVisible),
                    smileParams: SmileTemplateParams(posX: archPosX, posY: archPosY, posZ: archPosZ, scale: archWidth, curve: archCurve, length: toothLength, ratio: toothRatio),
                    toothStates: toothStates,
                    onToothSelected: { selectedToothName = $0 },
                    onToothTransformChange: { toothStates[$0] = $1 },
                    landmarks: landmarks,
                    activeLandmarkType: nextLandmark,
                    onLandmarkPicked: { pos in if let t = nextLandmark { landmarks[t] = pos } },
                    showGrid: (currentMode == .design && showGoldenRatio)
                ).id(url)
            } else {
                ZStack { Color(nsColor: .black); Text("3D Workspace").foregroundStyle(.gray) }
            }
        }
        .fileExporter(isPresented: $isExporting, document: GenericFile(sourceURL: session.activeScanURL), contentType: UTType(filenameExtension: selectedFormat.rawValue) ?? .data, defaultFilename: "DentalProject") { _ in }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [UTType(filenameExtension: "usdz")!, UTType(filenameExtension: "stl")!]) { result in handleImport(result) }
        .alert("Remove Model?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) { session.activeScanURL = nil }
        }
    }
    
    func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let tempDir = FileManager.default.temporaryDirectory
            let dstURL = tempDir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dstURL)
            try? FileManager.default.copyItem(at: url, to: dstURL)
            DispatchQueue.main.async { session.activeScanURL = dstURL; statusMessage = "✅ Imported" }
        case .failure: statusMessage = "❌ Error"
        }
    }
}
