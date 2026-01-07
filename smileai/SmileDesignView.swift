import SwiftUI
import SceneKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - EXTENSIONS
extension UTType {
    static let stl = UTType(filenameExtension: "stl")!
    static let obj = UTType(filenameExtension: "obj")!
}

// MARK: - DATA MODELS
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

struct GoldenRulerState {
    var start: CGPoint = .zero
    var end: CGPoint = .zero
    var isVisible: Bool = false
}

// MARK: - MAIN VIEW
struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    
    // --- STATE ---
    @State private var currentMode: DesignMode = .analysis
    
    // Landmarks
    @State private var landmarks3D: [LandmarkType: SCNVector3] = [:]
    @State private var landmarks2D: [LandmarkType: CGPoint] = [:]
    @State private var facePhoto: NSImage?
    
    // Interaction
    @State private var isPlacingLandmarks: Bool = false
    @State private var landmarksLocked: Bool = false
    @State private var triggerSnapshot: Bool = false
    
    // Ruler Tool
    @State private var isRulerToolActive: Bool = false
    @State private var ruler2D = GoldenRulerState()
    @State private var ruler3D = GoldenRulerState()
    
    // Tooth Library
    @State private var isImportingLibrary: Bool = false
    @State private var toothLibrary: [String: URL] = [:] // Maps "Central", "Lateral", "Canine" to file URLs
    
    // Guided Workflow
    var nextLandmark: LandmarkType? {
        let sequence: [LandmarkType] = [
            .rightPupil, .leftPupil, .glabella, .subnasale, .menton,
            .rightCommissure, .leftCommissure, .upperLipCenter, .lowerLipCenter,
            .midline, .rightCanine, .leftCanine
        ]
        if facePhoto != nil {
            return sequence.first(where: { landmarks2D[$0] == nil })
        } else {
            return sequence.first(where: { landmarks3D[$0] == nil })
        }
    }
    
    // Design Parameters
    @State private var showGoldenRatio: Bool = false
    @State private var templateVisible: Bool = true
    @State private var toothStates: [String: ToothState] = [:]
    @State private var selectedToothName: String? = nil
    @State private var archPosX: Float = 0.0; @State private var archPosY: Float = 0.0; @State private var archPosZ: Float = 0.05
    @State private var archWidth: Float = 1.0; @State private var archCurve: Float = 0.5
    @State private var toothLength: Float = 1.0; @State private var toothRatio: Float = 0.8
    
    // File IO
    @State private var statusMessage: String = ""
    @State private var isExporting = false
    @State private var isExporting2D = false
    @State private var isImporting3D = false
    @State private var isImportingPhoto = false
    @State private var showDeleteConfirmation = false
    @State private var selectedFormat: GeometryUtils.ExportFormat = .stl
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT SIDEBAR
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Smile Studio").font(.title2).fontWeight(.bold)
                    Spacer()
                    Button(action: { isImporting3D = true }) { Image(systemName: "cube") }
                        .buttonStyle(.plain).font(.title2).help("Import 3D Model")
                    Button(action: { isImportingPhoto = true }) { Image(systemName: "photo") }
                        .buttonStyle(.plain).font(.title2).padding(.leading, 8).help("Import Face Photo")
                    
                    if session.activeScanURL != nil || facePhoto != nil {
                        Button(action: { showDeleteConfirmation = true }) { Image(systemName: "trash").foregroundStyle(.red) }
                            .buttonStyle(.plain).font(.title2).padding(.leading, 8)
                    }
                }.padding(.top)
                
                Divider()
                
                // MAIN CONTENT SWITCHER
                if session.activeScanURL == nil && facePhoto == nil {
                    ContentUnavailableView("Empty Workspace", systemImage: "macwindow", description: Text("Import a 3D Scan or 2D Photo to begin."))
                    HStack {
                        Button("Load 3D") { isImporting3D = true }.buttonStyle(.borderedProminent)
                        Button("Load Photo") { isImportingPhoto = true }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity)
                } else {
                    Picker("Mode", selection: $currentMode) { ForEach(DesignMode.allCases) { mode in Text(mode.title).tag(mode) } }.pickerStyle(.segmented)
                    Divider()
                    
                    switch currentMode {
                    case .analysis:
                        VStack(alignment: .leading, spacing: 15) {
                            Label("Esthetic Analysis", systemImage: "scope").font(.headline)
                            
                            // Interaction Controls
                            HStack {
                                Toggle(isOn: $isPlacingLandmarks) { Label("Place", systemImage: "target") }
                                    .toggleStyle(.button).disabled(landmarksLocked)
                                Toggle(isOn: $landmarksLocked) { Label(landmarksLocked ? "Locked" : "Unlocked", systemImage: landmarksLocked ? "lock.fill" : "lock.open.fill") }
                                    .toggleStyle(.button).tint(landmarksLocked ? .orange : .green)
                            }.controlSize(.large).frame(maxWidth: .infinity)
                            
                            // Golden Ruler Tool
                            Toggle(isOn: $isRulerToolActive) {
                                Label("Golden Percentage", systemImage: "ruler.fill")
                                    .foregroundStyle(isRulerToolActive ? .yellow : .primary)
                            }
                            .toggleStyle(.button).frame(maxWidth: .infinity).tint(.yellow).padding(.top, 5)
                            
                            Divider()
                            
                            // Status / Instructions
                            if isRulerToolActive {
                                Text("Click & Drag to measure (23% - 15% - 12%)").font(.caption).foregroundStyle(.yellow)
                            } else if landmarksLocked {
                                Text("Unlock to edit. Drag to Pan/Zoom.").font(.caption2).foregroundStyle(.secondary)
                            } else if isPlacingLandmarks {
                                Text("Tap to place points. Drag to adjust.").font(.caption2).foregroundStyle(.blue)
                            } else {
                                Text("View mode. Drag to Pan. Pinch to Zoom.").font(.caption2).foregroundStyle(.secondary)
                            }
                            
                            if !isRulerToolActive, let target = nextLandmark {
                                Text("Next: \(target.rawValue)").font(.title3).fontWeight(.bold).foregroundStyle(.blue).padding(.vertical, 5)
                            } else if !isRulerToolActive {
                                Text("✅ Analysis Complete").font(.headline).foregroundStyle(.green)
                                Button("Start Design") { currentMode = .design; templateVisible = true; isPlacingLandmarks = false }.buttonStyle(.borderedProminent)
                            }
                            
                            Divider()
                            Button("Reset All Landmarks") {
                                landmarks3D.removeAll(); landmarks2D.removeAll()
                                landmarksLocked = false; ruler2D = GoldenRulerState(); ruler3D = GoldenRulerState()
                            }.buttonStyle(.bordered).controlSize(.small)
                        }
                    case .design:
                        VStack(alignment: .leading, spacing: 10) {
                            Button(action: { isImportingLibrary = true }) {
                                Label(toothLibrary.isEmpty ? "Import Tooth Library" : "Update Library", systemImage: "folder.badge.gearshape")
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 5)
                            
                            if !toothLibrary.isEmpty {
                                Text("✅ Using Custom Library").font(.caption).foregroundStyle(.green)
                            }
                            
                            DesignToolsView(templateVisible: $templateVisible, showGoldenRatio: $showGoldenRatio, selectedToothName: $selectedToothName, toothStates: $toothStates, archPosX: $archPosX, archPosY: $archPosY, archPosZ: $archPosZ, archWidth: $archWidth, archCurve: $archCurve, toothLength: $toothLength, toothRatio: $toothRatio)
                        }
                    }
                }
                Spacer()
                
                // EXPORT
                if facePhoto != nil {
                    HStack { Button("Download Analysis") { isExporting2D = true }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity) }
                }
                Divider()
                ExportToolsView(isExporting: $isExporting, selectedFormat: $selectedFormat)
            }
            .frame(width: 280).padding().background(Color(nsColor: .windowBackgroundColor))
            
            // RIGHT SPLIT VIEW
            GeometryReader { geo in
                HStack(spacing: 2) {
                    // 1. 2D PHOTO VIEW
                    if let image = facePhoto {
                        ZStack(alignment: .topTrailing) {
                            PhotoAnalysisView(
                                image: image,
                                landmarks: $landmarks2D,
                                isPlacing: isPlacingLandmarks,
                                isLocked: landmarksLocked,
                                activeType: nextLandmark
                            )
                            .overlay(
                                GoldenRulerOverlay(isActive: isRulerToolActive, state: $ruler2D)
                            )
                            .background(Color.black)
                            
                            // Delete Button
                            Button(action: { facePhoto = nil; landmarks2D.removeAll(); ruler2D = GoldenRulerState() }) {
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white, .red)
                                    .shadow(radius: 2)
                            }
                            .buttonStyle(.plain).padding(10).help("Delete Photo")
                        }
                        .frame(width: session.activeScanURL != nil ? geo.size.width * 0.5 : geo.size.width)
                    }
                    
                    // 2. 3D MODEL VIEW
                    if let url = session.activeScanURL {
                        ZStack(alignment: .bottomTrailing) {
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
                                isPlacingLandmarks: (isPlacingLandmarks && facePhoto == nil && !landmarksLocked),
                                onLandmarkPicked: { pos in if let t = nextLandmark { landmarks3D[t] = pos } },
                                triggerSnapshot: $triggerSnapshot,
                                onSnapshotTaken: { img in self.facePhoto = img; self.statusMessage = "📸 Snapshot Taken" },
                                showGrid: (currentMode == .design && showGoldenRatio),
                                toothLibrary: toothLibrary // Pass library
                            )
                            .id(url)
                            .overlay(
                                GoldenRulerOverlay(isActive: isRulerToolActive, state: $ruler3D)
                            )
                            
                            // Snap Button
                            Button(action: { triggerSnapshot = true }) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.largeTitle)
                                    .padding()
                                    .background(Circle().fill(Color.white.opacity(0.8)))
                            }
                            .buttonStyle(.plain).padding().help("Take High-Res Snapshot")
                        }
                        .frame(width: facePhoto != nil ? geo.size.width * 0.5 : geo.size.width)
                    }
                    
                    if facePhoto == nil && session.activeScanURL == nil {
                        ContentUnavailableView("No Content", systemImage: "square.dashed")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        // MODIFIERS
        .fileImporter(isPresented: $isImporting3D, allowedContentTypes: [UTType.usdz, UTType.stl, UTType.obj]) { res in handleImport3D(res) }
        .fileImporter(isPresented: $isImportingPhoto, allowedContentTypes: [UTType.jpeg, UTType.png, UTType.heic]) { res in handleImportPhoto(res) }
        
        // TOOTH LIBRARY IMPORTER (Supports Files & Folders)
        .fileImporter(isPresented: $isImportingLibrary, allowedContentTypes: [UTType.obj, UTType.folder], allowsMultipleSelection: true) { res in
            handleImportLibrary(res)
        }
        
        .fileExporter(isPresented: $isExporting, document: GenericFile(sourceURL: session.activeScanURL), contentType: UTType.data, defaultFilename: "Project3D") { _ in }
        .fileExporter(isPresented: $isExporting2D, document: ImageFile(image: render2DAnalysis()), contentType: .png, defaultFilename: "Analysis_Snapshot") { _ in }
        .alert("Clear Workspace?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) { session.activeScanURL = nil; facePhoto = nil; landmarks2D.removeAll(); landmarks3D.removeAll(); toothLibrary.removeAll() }
        }
    }
    
    // Handlers
    @MainActor func render2DAnalysis() -> NSImage? {
        guard let image = facePhoto else { return nil }
        let renderer = ImageRenderer(content:
            PhotoAnalysisView(image: image, landmarks: $landmarks2D, isPlacing: false, isLocked: true, activeType: nil)
                .overlay(GoldenRulerOverlay(isActive: false, state: $ruler2D)) // Include ruler if visible
                .frame(width: image.size.width, height: image.size.height)
        )
        renderer.scale = 2.0
        return renderer.nsImage
    }
    
    func handleImport3D(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dst); try? FileManager.default.copyItem(at: url, to: dst)
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
    
    // SMART LIBRARY IMPORTER
    func handleImportLibrary(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            var newLib: [String: URL] = [:]
            
            func processURL(_ url: URL) {
                guard url.startAccessingSecurityScopedResource() else { return }
                
                // If directory, recurse
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                        for content in contents { processURL(content) }
                    }
                } else if url.pathExtension.lowercased() == "obj" {
                    // Match Filename
                    let name = url.lastPathComponent.lowercased()
                    if name.contains("central") || name.contains("11") || name.contains("21") {
                        newLib["Central"] = url
                    } else if name.contains("lateral") || name.contains("12") || name.contains("22") {
                        newLib["Lateral"] = url
                    } else if name.contains("canine") || name.contains("13") || name.contains("23") {
                        newLib["Canine"] = url
                    }
                }
            }
            
            for url in urls { processURL(url) }
            
            if !newLib.isEmpty {
                DispatchQueue.main.async {
                    self.toothLibrary = newLib
                    self.statusMessage = "✅ Imported \(newLib.count) custom teeth"
                }
            } else {
                statusMessage = "⚠️ No valid tooth meshes found in selection."
            }
        }
    }
}

// ... [Include all Subviews: GoldenRulerOverlay, RulerHandle, RulerGraphic, PhotoAnalysisView, EstheticLines2D, DesignToolsView, ExportToolsView, SliderRow, GenericFile, ImageFile from previous turn. Code is identical, just ensured they are present in the file.]
// (Omitting full copy-paste of subviews for brevity, they are assumed to be appended below as in previous correct output)
// MARK: - GOLDEN RULER COMPONENT
struct GoldenRulerOverlay: View {
    var isActive: Bool
    @Binding var state: GoldenRulerState
    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle()).allowsHitTesting(isActive && !state.isVisible)
                .gesture(DragGesture(minimumDistance: 0).onChanged { val in if !state.isVisible { state.start = val.startLocation; state.end = val.location } }.onEnded { val in state.end = val.location; if hypot(state.end.x - state.start.x, state.end.y - state.start.y) > 20 { state.isVisible = true } })
            if state.isVisible { RulerGraphic(start: state.start, end: state.end); RulerHandle(pos: $state.start); RulerHandle(pos: $state.end) }
        }
    }
}
struct RulerHandle: View {
    @Binding var pos: CGPoint
    var body: some View { Circle().fill(Color.yellow).frame(width: 8, height: 8).shadow(radius: 1).position(pos).gesture(DragGesture().onChanged { val in pos = val.location }) }
}
struct RulerGraphic: View {
    var start: CGPoint; var end: CGPoint
    var body: some View { Canvas { context, size in
        var path = Path(); path.move(to: start); path.addLine(to: end)
        context.stroke(path, with: .color(.yellow), lineWidth: 2)
        let dx = end.x - start.x; let dy = end.y - start.y; let len = sqrt(dx*dx + dy*dy); let px = -dy / len * 15; let py = dx / len * 15
        let caps = [0.0, 1.0]
        for p in caps { let tx = start.x + dx * p; let ty = start.y + dy * p; var cap = Path(); cap.move(to: CGPoint(x: tx - px, y: ty - py)); cap.addLine(to: CGPoint(x: tx + px, y: ty + py)); context.stroke(cap, with: .color(.yellow), lineWidth: 2) }
        let percentages: [CGFloat] = [0.12, 0.27, 0.50, 0.73, 0.88]
        for p in percentages { let tx = start.x + dx * p; let ty = start.y + dy * p; var tick = Path(); tick.move(to: CGPoint(x: tx - px, y: ty - py)); tick.addLine(to: CGPoint(x: tx + px, y: ty + py)); context.stroke(tick, with: .color(.yellow), lineWidth: (p == 0.5 ? 3 : 1.5)) }
        let midX = start.x + dx * 0.5; let midY = start.y + dy * 0.5; context.draw(Text("23-15-12 %").font(.caption2).bold().foregroundColor(.yellow), at: CGPoint(x: midX, y: midY - 20))
    }.allowsHitTesting(false) }
}
// [Include PhotoAnalysisView, EstheticLines2D, DesignToolsView, ExportToolsView, SliderRow, GenericFile, ImageFile here]
struct PhotoAnalysisView: View {
    let image: NSImage; @Binding var landmarks: [LandmarkType: CGPoint]; var isPlacing: Bool; var isLocked: Bool; var activeType: LandmarkType?
    @State private var scale: CGFloat = 1.0; @State private var lastScale: CGFloat = 1.0; @State private var offset: CGSize = .zero; @State private var lastOffset: CGSize = .zero
    var body: some View { GeometryReader { geo in ZStack {
        ZStack {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: geo.size.width, height: geo.size.height).coordinateSpace(name: "AnalysisSpace")
                .onTapGesture(count: 1, coordinateSpace: .named("AnalysisSpace")) { loc in
                    if !isLocked && isPlacing, let type = activeType {
                        let r = AVMakeRect(aspectRatio: image.size, insideRect: CGRect(origin: .zero, size: geo.size))
                        if r.contains(loc) { landmarks[type] = CGPoint(x: (loc.x-r.minX)/r.width, y: (loc.y-r.minY)/r.height) }
                    }
                }
            EstheticLines2D(landmarks: landmarks, rect: AVMakeRect(aspectRatio: image.size, insideRect: CGRect(origin: .zero, size: geo.size)))
            ForEach(LandmarkType.allCases, id: \.self) { type in
                if let norm = landmarks[type] {
                    let r = AVMakeRect(aspectRatio: image.size, insideRect: CGRect(origin: .zero, size: geo.size)); let x = r.minX + norm.x*r.width; let y = r.minY + norm.y*r.height
                    Circle().fill(type == .midline ? .cyan : .yellow).frame(width: 12/scale, height: 12/scale).position(x: x, y: y)
                        .gesture(DragGesture(coordinateSpace: .named("AnalysisSpace")).onChanged { val in if !isLocked { landmarks[type] = CGPoint(x: (min(max(val.location.x, r.minX), r.maxX)-r.minX)/r.width, y: (min(max(val.location.y, r.minY), r.maxY)-r.minY)/r.height) } })
                    if isPlacing { Text(type.rawValue).font(.system(size: 10)).padding(4).background(.black.opacity(0.6)).cornerRadius(4).position(x: x, y: y-(20/scale)).scaleEffect(1/scale).foregroundStyle(.white).allowsHitTesting(false) }
                }
            }
        }.scaleEffect(scale).offset(offset)
        Color.clear.contentShape(Rectangle())
            .gesture(MagnificationGesture().onChanged { v in scale = max(1.0, lastScale*v) }.onEnded { _ in lastScale = scale })
            .simultaneousGesture(DragGesture().onChanged { v in if !isPlacing || isLocked { offset = CGSize(width: lastOffset.width+v.translation.width, height: lastOffset.height+v.translation.height) } }.onEnded { _ in if !isPlacing || isLocked { lastOffset = offset } })
            .onTapGesture(count: 2) { withAnimation { scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero } }.allowsHitTesting(!isPlacing || isLocked)
    }.clipped() } }
}
struct EstheticLines2D: View {
    var landmarks: [LandmarkType: CGPoint]; var rect: CGRect
    func pt(_ t: LandmarkType) -> CGPoint? { guard let n = landmarks[t] else { return nil }; return CGPoint(x: rect.minX+n.x*rect.width, y: rect.minY+n.y*rect.height) }
    var body: some View { Path { p in
        if let l = pt(.leftPupil), let r = pt(.rightPupil) { p.move(to: l); p.addLine(to: r); let m = CGPoint(x: (l.x+r.x)/2, y: (l.y+r.y)/2); p.move(to: m); p.addLine(to: CGPoint(x: m.x, y: rect.maxY)) }
        if let l = pt(.leftCommissure), let r = pt(.rightCommissure) { p.move(to: l); p.addLine(to: r) }
        if let g = pt(.glabella) { p.move(to: CGPoint(x: rect.minX, y: g.y)); p.addLine(to: CGPoint(x: rect.maxX, y: g.y)) }
        if let s = pt(.subnasale) { p.move(to: CGPoint(x: rect.minX, y: s.y)); p.addLine(to: CGPoint(x: rect.maxX, y: s.y)) }
        if let m = pt(.menton) { p.move(to: CGPoint(x: rect.minX, y: m.y)); p.addLine(to: CGPoint(x: rect.maxX, y: m.y)) }
    }.stroke(Color.white.opacity(0.6), lineWidth: 1).allowsHitTesting(false) }
}
struct DesignToolsView: View {
    @Binding var templateVisible: Bool; @Binding var showGoldenRatio: Bool; @Binding var selectedToothName: String?; @Binding var toothStates: [String: ToothState]
    @Binding var archPosX: Float; @Binding var archPosY: Float; @Binding var archPosZ: Float; @Binding var archWidth: Float; @Binding var archCurve: Float; @Binding var toothLength: Float; @Binding var toothRatio: Float
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 15) {
        Toggle("Show Template", isOn: $templateVisible); Toggle("Golden Ratio", isOn: $showGoldenRatio); Divider()
        if let selected = selectedToothName {
            Text("Selected: \(selected)").font(.headline).foregroundStyle(.blue)
            let binding = Binding(get: { toothStates[selected] ?? ToothState() }, set: { toothStates[selected] = $0 })
            SliderRow(label: "Rotate", value: Binding(get: { binding.wrappedValue.rotation.z }, set: { var n = binding.wrappedValue; n.rotation.z = $0; binding.wrappedValue = n }), range: -1.0...1.0)
            SliderRow(label: "Scale", value: Binding(get: { binding.wrappedValue.scale }, set: { var n = binding.wrappedValue; n.scale = $0; binding.wrappedValue = n }), range: 0.5...2.0)
            Button("Deselect") { selectedToothName = nil }.font(.caption)
        } else {
            Group { Text("Position").font(.headline); SliderRow(label: "Up/Down", value: $archPosY, range: -0.1...0.1); SliderRow(label: "Left/Right", value: $archPosX, range: -0.05...0.05); SliderRow(label: "Fwd/Back", value: $archPosZ, range: -0.1...0.2) }
            Divider()
            Group { Text("Shape").font(.headline); SliderRow(label: "Width", value: $archWidth, range: 0.5...2.0); SliderRow(label: "Curve", value: $archCurve, range: 0.0...1.0); SliderRow(label: "Length", value: $toothLength, range: 0.5...2.0); SliderRow(label: "Ratio", value: $toothRatio, range: 0.5...1.0) }
        }
    }}}
}
struct ExportToolsView: View {
    @Binding var isExporting: Bool; @Binding var selectedFormat: GeometryUtils.ExportFormat
    var body: some View { HStack { Picker("", selection: $selectedFormat) { Text("STL").tag(GeometryUtils.ExportFormat.stl); Text("USDZ").tag(GeometryUtils.ExportFormat.usdz) }.frame(width: 80); Button("Export") { isExporting = true }.buttonStyle(.borderedProminent) } }
}
struct SliderRow: View {
    let label: String; @Binding var value: Float; let range: ClosedRange<Float>
    var body: some View { HStack { Text(label).font(.caption).frame(width: 60, alignment: .leading); Slider(value: $value, in: range) } }
}
struct GenericFile: FileDocument {
    static var readableContentTypes: [UTType] { [UTType.data] }
    var sourceURL: URL?; init(sourceURL: URL?) { self.sourceURL = sourceURL }
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { return FileWrapper(regularFileWithContents: try! Data(contentsOf: sourceURL!)) }
}
struct ImageFile: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .jpeg] }
    var image: NSImage?
    init(image: NSImage?) { self.image = image }
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { return FileWrapper(regularFileWithContents: Data()) }
        return FileWrapper(regularFileWithContents: png)
    }
}
