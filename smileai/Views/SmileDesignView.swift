import SwiftUI
import SceneKit
import UniformTypeIdentifiers
import AVFoundation

struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    @StateObject private var history = TransformHistory()
    
    // MARK: - STATE
    @State private var currentMode: DesignMode = .analysis
    @State private var landmarks3D: [LandmarkType: SCNVector3] = [:]
    @State private var landmarks2D: [LandmarkType: CGPoint] = [:]
    @State private var facePhoto: NSImage?
    
    // Interaction
    @State private var isPlacingLandmarks: Bool = false
    @State private var landmarksLocked: Bool = false
    @State private var triggerSnapshot: Bool = false
    
    // Tools
    @State private var isRulerToolActive: Bool = false
    @State private var isRulerLocked: Bool = false
    @State private var ruler2D = GoldenRulerState()
    @State private var ruler3D = GoldenRulerState()
    
    // Smile Curve
    @State private var isDrawingCurve: Bool = false
    @State private var isCurveLocked: Bool = false
    @State private var customCurvePoints: [SCNVector3] = []
    
    // Visuals
    @State private var useStoneMaterial: Bool = false
    
    // Library / Drop
    @State private var isImportingLibrary: Bool = false
    @State private var importedFiles: [URL] = []
    @State private var toothAssignments: [String: URL] = [:]
    @State private var libraryID: UUID = UUID()
    @State private var isTargeted: Bool = false
    
    // Alerts
    @State private var showReplaceAlert = false
    @State private var replaceAlertData: ReplaceAlertData?
    @State private var showDeleteConfirmation = false
    @State private var statusMessage: String = ""
    
    // Design Params
    @State private var showGoldenRatio: Bool = false
    @State private var templateVisible: Bool = true
    @State private var toothStates: [String: ToothState] = [:]
    @State private var selectedToothName: String? = nil
    @State private var archPosX: Float = 0.0; @State private var archPosY: Float = 0.0; @State private var archPosZ: Float = 0.05
    @State private var archWidth: Float = 1.0; @State private var archCurve: Float = 0.5
    @State private var toothLength: Float = 1.0; @State private var toothRatio: Float = 0.8
    
    @State private var isExporting = false; @State private var isExporting2D = false; @State private var isImporting3D = false; @State private var isImportingPhoto = false
    @State private var selectedFormat: GeometryUtils.ExportFormat = .stl
    
    var nextLandmark: LandmarkType? {
        let sequence: [LandmarkType] = [.rightPupil, .leftPupil, .glabella, .subnasale, .menton, .rightCommissure, .leftCommissure, .upperLipCenter, .lowerLipCenter, .midline, .rightCanine, .leftCanine]
        return facePhoto != nil ? sequence.first(where: { landmarks2D[$0] == nil }) : sequence.first(where: { landmarks3D[$0] == nil })
    }
    
    var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 280)
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
            
            mainContentView
        }
        .focusable()
        .onKeyPress(phases: .down) { press in
            if press.key == "z" && press.modifiers.contains(.command) {
                if press.modifiers.contains(.shift) { history.redo() } else { history.undo() }
                return .handled
            }
            if press.key == .delete { return handleDeleteKey() }
            return .ignored
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            return ContentDropManager.handleDrop(providers: providers) { type in
                handleDroppedContent(type)
            }
        }
        .fileImporter(isPresented: $isImporting3D, allowedContentTypes: [UTType.usdz, UTType.stl, UTType.obj]) { res in handleImport3D(res) }
        .fileImporter(isPresented: $isImportingPhoto, allowedContentTypes: [UTType.jpeg, UTType.png, UTType.heic]) { res in handleImportPhoto(res) }
        .fileImporter(isPresented: $isImportingLibrary, allowedContentTypes: [UTType.folder, UTType.obj], allowsMultipleSelection: true) { res in handleImportLibrary(res) }
        .fileExporter(isPresented: $isExporting, document: GenericFile(sourceURL: session.activeScanURL), contentType: UTType.data, defaultFilename: "Project3D") { _ in }
        .fileExporter(isPresented: $isExporting2D, document: ImageFile(image: render2DAnalysis()), contentType: .png, defaultFilename: "Analysis_Snapshot") { _ in }
        .alert("Clear Workspace?", isPresented: $showDeleteConfirmation) { Button("Cancel", role: .cancel) { }; Button("Clear All", role: .destructive) { session.activeScanURL = nil; facePhoto = nil; landmarks2D.removeAll(); landmarks3D.removeAll(); toothAssignments.removeAll(); importedFiles.removeAll(); customCurvePoints.removeAll() } }
        // NEW: Collision Alert
        .alert("Replace Tooth?", isPresented: $showReplaceAlert, presenting: replaceAlertData) { data in
            Button("Replace Existing") {
                handleToothDrop(toothID: data.existingID, fileURL: data.newURL)
            }
            Button("Add New (Cancel)", role: .cancel) { }
        } message: { data in
            Text("Dropped near tooth \(data.existingID). Replace it?")
        }
    }
    
    // MARK: - SUBVIEWS
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Smile Studio").font(.title2).fontWeight(.bold); Spacer(); Button(action: { isImporting3D = true }) { Image(systemName: "cube") }.buttonStyle(.plain); Button(action: { isImportingPhoto = true }) { Image(systemName: "photo") }.buttonStyle(.plain).padding(.leading, 8) }.padding(.top)
            Divider()
            if session.activeScanURL == nil && facePhoto == nil { ContentUnavailableView { Label("Drag & Drop", systemImage: "arrow.down.doc") } description: { Text("Drop 3D models or Photos here.") }.frame(maxWidth: .infinity).background(isTargeted ? Color.blue.opacity(0.1) : Color.clear) } else {
                Picker("Mode", selection: $currentMode) { ForEach(DesignMode.allCases) { mode in Text(mode.title).tag(mode) } }.pickerStyle(.segmented)
                Divider()
                switch currentMode {
                case .analysis: analysisToolsView
                case .design: designToolsView
                }
            }
            Spacer()
            ExportToolsView(isExporting: $isExporting, selectedFormat: $selectedFormat)
        }
    }
    
    private var analysisToolsView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Analysis", systemImage: "scope").font(.headline)
            Toggle(isOn: $useStoneMaterial) { Label("Stone Mode", systemImage: "circle.lefthalf.filled.righthalf.striped.horizontal") }.toggleStyle(.button)
            HStack { Toggle(isOn: $isPlacingLandmarks) { Label("Place", systemImage: "target") }.toggleStyle(.button).disabled(landmarksLocked); Toggle(isOn: $landmarksLocked) { Label("Locked", systemImage: landmarksLocked ? "lock.fill" : "lock.open.fill") }.toggleStyle(.button).tint(landmarksLocked ? .orange : .green) }.controlSize(.large).frame(maxWidth: .infinity)
            HStack { Toggle(isOn: $isRulerToolActive) { Label("Golden Ruler", systemImage: "ruler.fill") }.toggleStyle(.button).frame(maxWidth: .infinity).tint(.yellow); Toggle(isOn: $isRulerLocked) { Image(systemName: isRulerLocked ? "lock.fill" : "lock.open.fill") }.toggleStyle(.button).tint(isRulerLocked ? .red : .green).disabled(!isRulerToolActive) }
            Button("Reset All") { landmarks3D.removeAll(); landmarks2D.removeAll(); landmarksLocked = false; ruler2D = GoldenRulerState(); ruler3D = GoldenRulerState() }.buttonStyle(.bordered).controlSize(.small)
        }
    }
    
    private var designToolsView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Smile Curve").font(.headline)
            HStack { Toggle(isOn: $isDrawingCurve) { Label(isDrawingCurve ? "Drawing..." : "Draw Curve", systemImage: "pencil.and.outline") }.toggleStyle(.button).tint(.orange).disabled(isCurveLocked); Toggle(isOn: $isCurveLocked) { Image(systemName: isCurveLocked ? "lock.fill" : "lock.open.fill") }.toggleStyle(.button).tint(isCurveLocked ? .red : .green); Spacer(); Button(role: .destructive) { customCurvePoints.removeAll(); isCurveLocked = false; isDrawingCurve = false } label: { Image(systemName: "trash") }.disabled(customCurvePoints.isEmpty) }
            Divider()
            HStack { Text("Library").font(.headline); Spacer(); Button(action: { history.undo() }) { Image(systemName: "arrow.uturn.backward") }.disabled(!history.canUndo); Button(action: { history.redo() }) { Image(systemName: "arrow.uturn.forward") }.disabled(!history.canRedo); Button(action: { isImportingLibrary = true }) { Image(systemName: "folder.badge.plus") }.buttonStyle(.plain) }
            if !importedFiles.isEmpty { List(importedFiles, id: \.self) { file in HStack { Image(systemName: "doc.text.fill").foregroundStyle(.blue); Text(file.lastPathComponent).font(.caption).lineLimit(1) }.draggable(file) }.frame(height: 100).listStyle(.bordered(alternatesRowBackgrounds: true)); Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) { ToothDropSlot(label: "Central", assignment: bindingFor("Central")); ToothDropSlot(label: "Lateral", assignment: bindingFor("Lateral")); ToothDropSlot(label: "Canine", assignment: bindingFor("Canine")) }.padding(8).background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3))) } else { Button("Load Library Folder") { isImportingLibrary = true }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
            Divider()
            DesignToolsView(templateVisible: $templateVisible, showGoldenRatio: $showGoldenRatio, selectedToothName: $selectedToothName, toothStates: $toothStates, archPosX: $archPosX, archPosY: $archPosY, archPosZ: $archPosZ, archWidth: $archWidth, archCurve: $archCurve, toothLength: $toothLength, toothRatio: $toothRatio)
        }
    }
    
    private var mainContentView: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                if let image = facePhoto {
                    ZStack(alignment: .topTrailing) { PhotoAnalysisView(image: image, landmarks: $landmarks2D, isPlacing: isPlacingLandmarks, isLocked: landmarksLocked, activeType: nil).overlay(GoldenRulerOverlay(isActive: isRulerToolActive, isLocked: isRulerLocked, state: $ruler2D)).background(Color.black); Button(action: { facePhoto = nil; landmarks2D.removeAll() }) { Image(systemName: "trash.circle.fill").font(.title).foregroundStyle(.red) }.buttonStyle(.plain).padding(10) }.frame(width: session.activeScanURL != nil ? geo.size.width * 0.5 : geo.size.width)
                }
                if let url = session.activeScanURL {
                    ZStack(alignment: .bottomTrailing) {
                        DesignSceneWrapper(
                            scanURL: url, mode: currentMode, showSmileTemplate: (currentMode == .design && templateVisible),
                            smileParams: SmileTemplateParams(posX: archPosX, posY: archPosY, posZ: archPosZ, scale: archWidth, curve: archCurve, length: toothLength, ratio: toothRatio),
                            toothStates: toothStates, onToothSelected: { selectedToothName = $0 },
                            onToothTransformChange: { id, newState in toothStates[id] = newState },
                            landmarks: landmarks3D, activeLandmarkType: nil, isPlacingLandmarks: (isPlacingLandmarks && facePhoto == nil && !landmarksLocked),
                            onLandmarkPicked: { pos in if let t = nextLandmark { landmarks3D[t] = pos } },
                            triggerSnapshot: $triggerSnapshot, onSnapshotTaken: { img in facePhoto = img },
                            showGrid: (currentMode == .design && showGoldenRatio),
                            toothLibrary: toothAssignments, libraryID: libraryID,
                            isDrawingCurve: $isDrawingCurve, isCurveLocked: isCurveLocked, customCurvePoints: $customCurvePoints,
                            useStoneMaterial: useStoneMaterial,
                            onToothDrop: { toothID, fileURL in handleToothDrop(toothID: toothID, fileURL: fileURL) },
                            showReplaceAlert: $showReplaceAlert, // BINDING
                            replaceAlertData: $replaceAlertData // BINDING
                        )
                        .id(url)
                        .overlay(GoldenRulerOverlay(isActive: isRulerToolActive, isLocked: isRulerLocked, state: $ruler3D))
                        
                        Button(action: { triggerSnapshot = true }) { Image(systemName: "camera.viewfinder").font(.largeTitle).padding().background(Circle().fill(Color.white.opacity(0.8))) }.buttonStyle(.plain).padding()
                    }.frame(width: facePhoto != nil ? geo.size.width * 0.5 : geo.size.width)
                }
                if facePhoto == nil && session.activeScanURL == nil { ContentUnavailableView("Drag & Drop", systemImage: "arrow.down.doc.fill").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
    }
    
    // LOGIC & HELPERS
    private func handleDroppedContent(_ type: DroppedContentType) {
        switch type {
        case .model3D(let url): session.activeScanURL = url; statusMessage = "✅ Loaded Model"
        case .facePhoto(let image): self.facePhoto = image; statusMessage = "✅ Loaded Photo"
        case .libraryItem(let url): handleImportLibrary(.success([url]))
        case .unknown: break
        }
    }
    private func handleDeleteKey() -> KeyPress.Result {
        if let name = selectedToothName { let old = toothStates[name] ?? ToothState(); history.pushCommand(ToothTransformCommand(toothID: name, oldState: old, newState: ToothState(), applyState: { id, s in toothStates[id] = s })); toothStates[name] = ToothState(); return .handled }
        if !customCurvePoints.isEmpty { customCurvePoints.removeLast(); return .handled }
        return .ignored
    }
    func handleToothDrop(toothID: String, fileURL: URL) { var typeKey = "Central"; if toothID.contains("2") { typeKey = "Lateral" } else if toothID.contains("3") { typeKey = "Canine" }; toothAssignments[typeKey] = fileURL; libraryID = UUID(); statusMessage = "✅ Replaced \(typeKey) Shape" }
    
    func bindingFor(_ key: String) -> Binding<URL?> { Binding(get: { toothAssignments[key] }, set: { if let url = $0 { toothAssignments[key] = url } else { toothAssignments.removeValue(forKey: key) }; libraryID = UUID() }) }
    @MainActor func render2DAnalysis() -> NSImage? { guard let image = facePhoto else { return nil }; let renderer = ImageRenderer(content: PhotoAnalysisView(image: image, landmarks: $landmarks2D, isPlacing: false, isLocked: true, activeType: nil).overlay(GoldenRulerOverlay(isActive: false, isLocked: true, state: $ruler2D)).frame(width: image.size.width, height: image.size.height)); renderer.scale = 2.0; return renderer.nsImage }
    func handleImport3D(_ result: Result<URL, Error>) { if case .success(let url) = result { guard url.startAccessingSecurityScopedResource() else { return }; defer { url.stopAccessingSecurityScopedResource() }; let dst = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent); try? FileManager.default.removeItem(at: dst); try? FileManager.default.copyItem(at: url, to: dst); DispatchQueue.main.async { session.activeScanURL = dst; statusMessage = "✅ Loaded" } } }
    func handleImportPhoto(_ result: Result<URL, Error>) { if case .success(let url) = result { guard url.startAccessingSecurityScopedResource() else { return }; defer { url.stopAccessingSecurityScopedResource() }; if let img = NSImage(contentsOf: url) { DispatchQueue.main.async { facePhoto = img; statusMessage = "✅ Loaded" } } } }
    func handleImportLibrary(_ result: Result<[URL], Error>) { if case .success(let urls) = result { var foundFiles: [URL] = []; func scan(_ url: URL) { let start = url.startAccessingSecurityScopedResource(); defer { if start { url.stopAccessingSecurityScopedResource() } }; var isDir: ObjCBool = false; if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { if let c = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) { for f in c { scan(f) } } } else if url.pathExtension.lowercased() == "obj" { foundFiles.append(url) } }; for url in urls { scan(url) }; DispatchQueue.main.async { self.importedFiles = foundFiles; self.statusMessage = "✅ Loaded Lib" } } }
}

// SUBVIEWS (Keep existing subviews like ToothPicker, ToothDropSlot, etc.)
struct ToothPicker: View { @Binding var selection: URL?; let files: [URL]; var body: some View { Menu { ForEach(files, id: \.self) { file in Button(file.lastPathComponent) { selection = file } }; Divider(); Button("None (Procedural)") { selection = nil } } label: { HStack { Text(selection?.lastPathComponent ?? "Select File...").font(.caption).truncationMode(.middle); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption2) }.padding(4).background(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.5))) }.menuStyle(.borderlessButton).frame(maxWidth: .infinity) } }
struct ToothDropSlot: View { let label: String; @Binding var assignment: URL?; @State private var isTargeted: Bool = false; var body: some View { GridRow { Text(label).frame(width: 50, alignment: .leading); ZStack { RoundedRectangle(cornerRadius: 6).fill(isTargeted ? Color.blue.opacity(0.2) : Color.clear).stroke(isTargeted ? Color.blue : Color.gray.opacity(0.5), lineWidth: 1); HStack { if let url = assignment { Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle); Spacer(); Button(action: { assignment = nil }) { Image(systemName: "xmark.circle.fill").foregroundStyle(.gray) }.buttonStyle(.plain) } else { Text("Drop here...").font(.caption).foregroundStyle(.secondary); Spacer() } }.padding(4) }.frame(height: 24).dropDestination(for: URL.self) { items, _ in if let url = items.first { assignment = url; return true }; return false } isTargeted: { isTargeted = $0 } } } }
struct GoldenRulerOverlay: View { var isActive: Bool; var isLocked: Bool; @Binding var state: GoldenRulerState; var body: some View { ZStack { Color.clear.contentShape(Rectangle()).allowsHitTesting(isActive && !state.isVisible).gesture(DragGesture(minimumDistance: 0).onChanged { val in if !state.isVisible { state.start = val.startLocation; state.end = val.location } }.onEnded { val in state.end = val.location; if hypot(state.end.x - state.start.x, state.end.y - state.start.y) > 20 { state.isVisible = true } }); if state.isVisible { RulerGraphic(start: state.start, end: state.end); if !isLocked { RulerHandle(pos: $state.start); RulerHandle(pos: $state.end) } } } } }
struct RulerHandle: View { @Binding var pos: CGPoint; var body: some View { Circle().fill(Color.yellow).frame(width: 8, height: 8).shadow(radius: 1).position(pos).gesture(DragGesture().onChanged { val in pos = val.location }) } }
struct RulerGraphic: View { var start: CGPoint; var end: CGPoint; var body: some View { Canvas { context, size in var path = Path(); path.move(to: start); path.addLine(to: end); context.stroke(path, with: .color(.yellow), lineWidth: 2); let dx = end.x - start.x; let dy = end.y - start.y; let len = sqrt(dx*dx + dy*dy); let px = -dy / len * 15; let py = dx / len * 15; let caps = [0.0, 1.0]; for p in caps { let tx = start.x + dx * p; let ty = start.y + dy * p; var cap = Path(); cap.move(to: CGPoint(x: tx - px, y: ty - py)); cap.addLine(to: CGPoint(x: tx + px, y: ty + py)); context.stroke(cap, with: .color(.yellow), lineWidth: 2) }; let percentages: [CGFloat] = [0.12, 0.27, 0.50, 0.73, 0.88]; for p in percentages { let tx = start.x + dx * p; let ty = start.y + dy * p; var tick = Path(); tick.move(to: CGPoint(x: tx - px, y: ty - py)); tick.addLine(to: CGPoint(x: tx + px, y: ty + py)); context.stroke(tick, with: .color(.yellow), lineWidth: (p == 0.5 ? 3 : 1.5)) }; let midX = start.x + dx * 0.5; let midY = start.y + dy * 0.5; context.draw(Text("23-15-12 %").font(.caption2).bold().foregroundColor(.yellow), at: CGPoint(x: midX, y: midY - 20)) }.allowsHitTesting(false) } }
struct ExportToolsView: View { @Binding var isExporting: Bool; @Binding var selectedFormat: GeometryUtils.ExportFormat; var body: some View { HStack { Picker("", selection: $selectedFormat) { Text("STL").tag(GeometryUtils.ExportFormat.stl); Text("USDZ").tag(GeometryUtils.ExportFormat.usdz) }.frame(width: 80); Button("Export") { isExporting = true }.buttonStyle(.borderedProminent) } } }
