import SwiftUI
import SceneKit
import UniformTypeIdentifiers
import AVFoundation

// --- FIX: Define Missing UTType Members ---
extension UTType {
    static let stl = UTType(filenameExtension: "stl")!
    static let obj = UTType(filenameExtension: "obj")!
}

// --- DATA MODELS ---
enum DesignMode: Int, CaseIterable, Identifiable {
    case analysis = 0
    case design = 1
    var id: Int { rawValue }
    var title: String { switch self { case .analysis: return "Analysis"; case .design: return "Design" } }
}

enum LandmarkType: String, CaseIterable {
    // Reference Frame
    case rightPupil = "Right Pupil"
    case leftPupil = "Left Pupil"
    case glabella = "Glabella (Brows)"
    case subnasale = "Subnasale (Nose Base)"
    case menton = "Menton (Chin Tip)"
    
    // Smile Frame
    case rightCommissure = "Right Mouth Corner"
    case leftCommissure = "Left Mouth Corner"
    case upperLipCenter = "Upper Lip Center"
    case lowerLipCenter = "Lower Lip Center"
    
    // Dental Frame
    case midline = "Dental Midline"
    case leftCanine = "Left Canine Tip"
    case rightCanine = "Right Canine Tip"
}

struct ToothState: Equatable {
    var positionOffset: SIMD3<Float> = .zero
    var rotation: SIMD3<Float> = .zero
    var scale: Float = 1.0
}

struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    
    // --- STATE ---
    @State private var currentMode: DesignMode = .analysis
    
    // 3D Landmarks
    @State private var landmarks3D: [LandmarkType: SCNVector3] = [:]
    
    // 2D Photo & Landmarks
    @State private var facePhoto: NSImage?
    @State private var landmarks2D: [LandmarkType: CGPoint] = [:]
    
    // Interaction
    @State private var isPlacingLandmarks: Bool = false
    
    // Guided workflow
    var nextLandmark: LandmarkType? {
        let sequence: [LandmarkType] = [
            .rightPupil, .leftPupil,
            .glabella, .subnasale, .menton,
            .rightCommissure, .leftCommissure,
            .upperLipCenter, .lowerLipCenter,
            .midline, .rightCanine, .leftCanine
        ]
        // If photo exists, prioritize 2D landmarks, otherwise 3D
        if facePhoto != nil {
            return sequence.first(where: { landmarks2D[$0] == nil })
        } else {
            return sequence.first(where: { landmarks3D[$0] == nil })
        }
    }
    
    // Design Params
    @State private var showGoldenRatio: Bool = false
    @State private var templateVisible: Bool = true
    @State private var toothStates: [String: ToothState] = [:]
    @State private var selectedToothName: String? = nil
    @State private var archPosX: Float = 0.0; @State private var archPosY: Float = 0.0; @State private var archPosZ: Float = 0.05
    @State private var archWidth: Float = 1.0; @State private var archCurve: Float = 0.5
    @State private var toothLength: Float = 1.0; @State private var toothRatio: Float = 0.8
    
    // IO
    @State private var statusMessage: String = ""
    @State private var isExporting = false
    @State private var isImporting3D = false
    @State private var isImportingPhoto = false
    @State private var showDeleteConfirmation = false
    @State private var selectedFormat: GeometryUtils.ExportFormat = .stl
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT PANEL: Tools
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Smile Studio").font(.title2).fontWeight(.bold)
                    Spacer()
                    // Import 3D
                    Button(action: { isImporting3D = true }) { Image(systemName: "cube") }
                        .buttonStyle(.plain).font(.title2).help("Import 3D Model")
                    // Import 2D Photo
                    Button(action: { isImportingPhoto = true }) { Image(systemName: "photo") }
                        .buttonStyle(.plain).font(.title2).padding(.leading, 8).help("Import Face Photo")
                    
                    if session.activeScanURL != nil || facePhoto != nil {
                        Button(action: { showDeleteConfirmation = true }) { Image(systemName: "trash").foregroundStyle(.red) }
                            .buttonStyle(.plain).font(.title2).padding(.leading, 8)
                    }
                }.padding(.top)
                
                Divider()
                
                if session.activeScanURL == nil && facePhoto == nil {
                    ContentUnavailableView("Empty Workspace", systemImage: "macwindow", description: Text("Import a 3D Scan or 2D Photo to begin."))
                    HStack {
                        Button("Load 3D") { isImporting3D = true }.buttonStyle(.borderedProminent)
                        Button("Load Photo") { isImportingPhoto = true }.buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Picker("Mode", selection: $currentMode) { ForEach(DesignMode.allCases) { mode in Text(mode.title).tag(mode) } }.pickerStyle(.segmented)
                    Divider()
                    
                    switch currentMode {
                    case .analysis:
                        VStack(alignment: .leading, spacing: 15) {
                            Label("Esthetic Analysis", systemImage: "scope").font(.headline)
                            Toggle(isOn: $isPlacingLandmarks) {
                                Label(isPlacingLandmarks ? "Placing Points" : "View/Rotate", systemImage: isPlacingLandmarks ? "target" : "hand.draw")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(isPlacingLandmarks ? .red : .primary)
                            }.toggleStyle(.button).controlSize(.large).frame(maxWidth: .infinity)
                            
                            Divider()
                            
                            if let target = nextLandmark {
                                Text("Next Landmark:").font(.caption).foregroundStyle(.secondary)
                                Text(target.rawValue).font(.title3).fontWeight(.bold).foregroundStyle(.blue).padding(.vertical, 5).opacity(isPlacingLandmarks ? 1.0 : 0.5)
                            } else {
                                Text("✅ Analysis Complete").font(.headline).foregroundStyle(.green)
                                Button("Start Design") { currentMode = .design; templateVisible = true; isPlacingLandmarks = false }.buttonStyle(.borderedProminent)
                            }
                            
                            Divider()
                            Button("Reset All Landmarks") { landmarks3D.removeAll(); landmarks2D.removeAll() }.buttonStyle(.bordered).controlSize(.small)
                        }
                    case .design:
                        DesignToolsView(templateVisible: $templateVisible, showGoldenRatio: $showGoldenRatio, selectedToothName: $selectedToothName, toothStates: $toothStates, archPosX: $archPosX, archPosY: $archPosY, archPosZ: $archPosZ, archWidth: $archWidth, archCurve: $archCurve, toothLength: $toothLength, toothRatio: $toothRatio)
                    }
                }
                Spacer()
                if !statusMessage.isEmpty { Text(statusMessage).font(.caption) }
                Divider()
                ExportToolsView(isExporting: $isExporting, selectedFormat: $selectedFormat)
            }
            .frame(width: 280).padding().background(Color(nsColor: .windowBackgroundColor))
            
            // RIGHT PANEL: Split View
            GeometryReader { geo in
                HStack(spacing: 2) {
                    // 1. 2D Photo View (Visible if photo exists)
                    if let image = facePhoto {
                        PhotoAnalysisView(
                            image: image,
                            landmarks: $landmarks2D,
                            isPlacing: isPlacingLandmarks,
                            activeType: nextLandmark
                        )
                        .frame(width: session.activeScanURL != nil ? geo.size.width * 0.5 : geo.size.width)
                        .background(Color.black)
                    }
                    
                    // 2. 3D Model View (Visible if model exists)
                    if let url = session.activeScanURL {
                        DesignSceneWrapper(
                            scanURL: url,
                            mode: currentMode,
                            showSmileTemplate: (currentMode == .design && templateVisible),
                            smileParams: SmileTemplateParams(posX: archPosX, posY: archPosY, posZ: archPosZ, scale: archWidth, curve: archCurve, length: toothLength, ratio: toothRatio),
                            toothStates: toothStates,
                            onToothSelected: { selectedToothName = $0 },
                            onToothTransformChange: { toothStates[$0] = $1 },
                            landmarks: landmarks3D,
                            activeLandmarkType: nextLandmark,
                            isPlacingLandmarks: (isPlacingLandmarks && facePhoto == nil), // Only allow 3D click if no photo (or distinct toggle?) Let's prefer 2D if present
                            onLandmarkPicked: { pos in if let t = nextLandmark { landmarks3D[t] = pos } },
                            showGrid: (currentMode == .design && showGoldenRatio)
                        )
                        .id(url)
                        .frame(width: facePhoto != nil ? geo.size.width * 0.5 : geo.size.width)
                    }
                    
                    if facePhoto == nil && session.activeScanURL == nil {
                        ContentUnavailableView("No Content", systemImage: "square.dashed")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        // IMPORTERS
        .fileImporter(isPresented: $isImporting3D, allowedContentTypes: [UTType.usdz, UTType.stl, UTType.obj]) { res in
            handleImport3D(res)
        }
        .fileImporter(isPresented: $isImportingPhoto, allowedContentTypes: [UTType.jpeg, UTType.png, UTType.heic]) { res in
            handleImportPhoto(res)
        }
        .fileExporter(isPresented: $isExporting, document: GenericFile(sourceURL: session.activeScanURL), contentType: UTType.data, defaultFilename: "Project") { _ in }
        .alert("Clear Workspace?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) { session.activeScanURL = nil; facePhoto = nil; landmarks2D.removeAll(); landmarks3D.removeAll() }
        }
    }
    
    func handleImport3D(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: url, to: dst)
            DispatchQueue.main.async { session.activeScanURL = dst; statusMessage = "✅ 3D Model Loaded" }
        }
    }
    
    func handleImportPhoto(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let img = NSImage(contentsOf: url) {
                DispatchQueue.main.async { facePhoto = img; statusMessage = "✅ Photo Loaded" }
            }
        }
    }
}

// MARK: - 2D ANALYSIS VIEW
struct PhotoAnalysisView: View {
    let image: NSImage
    @Binding var landmarks: [LandmarkType: CGPoint]
    var isPlacing: Bool
    var activeType: LandmarkType?
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .gesture(DragGesture(minimumDistance: 0).onEnded { val in
                        if isPlacing, let type = activeType {
                            // Normalize coordinates (0-1)
                            let imageFrame = AVMakeRect(aspectRatio: image.size, insideRect: CGRect(origin: .zero, size: geo.size))
                            if imageFrame.contains(val.location) {
                                let normX = (val.location.x - imageFrame.minX) / imageFrame.width
                                let normY = (val.location.y - imageFrame.minY) / imageFrame.height
                                landmarks[type] = CGPoint(x: normX, y: normY)
                            }
                        }
                    })
                
                // Draw Landmarks
                ForEach(LandmarkType.allCases, id: \.self) { type in
                    if let norm = landmarks[type] {
                        let imageFrame = AVMakeRect(aspectRatio: image.size, insideRect: CGRect(origin: .zero, size: geo.size))
                        let x = imageFrame.minX + norm.x * imageFrame.width
                        let y = imageFrame.minY + norm.y * imageFrame.height
                        
                        Circle()
                            .fill(colorFor(type))
                            .frame(width: 8, height: 8)
                            .position(x: x, y: y)
                        
                        if isPlacing {
                            Text(type.rawValue).font(.caption2).position(x: x, y: y - 10).foregroundStyle(.white).shadow(radius: 1)
                        }
                    }
                }
                
                // Draw Esthetic Lines
                EstheticLines2D(landmarks: landmarks, rect: AVMakeRect(aspectRatio: image.size, insideRect: CGRect(origin: .zero, size: geo.size)))
            }
            .clipped()
        }
    }
    
    func colorFor(_ type: LandmarkType) -> Color {
        switch type {
        case .rightPupil, .leftPupil: return .yellow
        case .midline: return .cyan
        case .rightCommissure, .leftCommissure: return .green
        default: return .blue
        }
    }
}

// MARK: - 2D LINES OVERLAY
struct EstheticLines2D: View {
    var landmarks: [LandmarkType: CGPoint]
    var rect: CGRect
    
    func pt(_ type: LandmarkType) -> CGPoint? {
        guard let norm = landmarks[type] else { return nil }
        return CGPoint(x: rect.minX + norm.x * rect.width, y: rect.minY + norm.y * rect.height)
    }
    
    var body: some View {
        Path { path in
            // Horizon
            if let l = pt(.leftPupil), let r = pt(.rightPupil) {
                path.move(to: l); path.addLine(to: r)
                // Midline
                let mid = CGPoint(x: (l.x+r.x)/2, y: (l.y+r.y)/2)
                path.move(to: mid); path.addLine(to: CGPoint(x: mid.x, y: rect.maxY))
            }
            // Commissures
            if let l = pt(.leftCommissure), let r = pt(.rightCommissure) {
                path.move(to: l); path.addLine(to: r)
            }
            // Thirds
            if let g = pt(.glabella) { path.move(to: CGPoint(x: rect.minX, y: g.y)); path.addLine(to: CGPoint(x: rect.maxX, y: g.y)) }
            if let s = pt(.subnasale) { path.move(to: CGPoint(x: rect.minX, y: s.y)); path.addLine(to: CGPoint(x: rect.maxX, y: s.y)) }
            if let m = pt(.menton) { path.move(to: CGPoint(x: rect.minX, y: m.y)); path.addLine(to: CGPoint(x: rect.maxX, y: m.y)) }
        }
        .stroke(Color.white.opacity(0.6), lineWidth: 1)
    }
}

// Helpers
struct DesignToolsView: View {
    @Binding var templateVisible: Bool
    @Binding var showGoldenRatio: Bool
    @Binding var selectedToothName: String?
    @Binding var toothStates: [String: ToothState]
    @Binding var archPosX: Float; @Binding var archPosY: Float; @Binding var archPosZ: Float
    @Binding var archWidth: Float; @Binding var archCurve: Float; @Binding var toothLength: Float; @Binding var toothRatio: Float
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 15) {
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
    }}}
}

struct ExportToolsView: View {
    @Binding var isExporting: Bool
    @Binding var selectedFormat: GeometryUtils.ExportFormat
    var body: some View { HStack { Picker("", selection: $selectedFormat) { Text("STL").tag(GeometryUtils.ExportFormat.stl); Text("USDZ").tag(GeometryUtils.ExportFormat.usdz) }.frame(width: 80); Button("Export") { isExporting = true }.buttonStyle(.borderedProminent) } }
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
