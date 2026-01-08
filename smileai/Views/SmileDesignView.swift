import SwiftUI
import SceneKit
import UniformTypeIdentifiers
import AVFoundation

struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    
    @State private var currentMode: DesignMode = .analysis
    @State private var landmarks3D: [LandmarkType: SCNVector3] = [:]
    @State private var landmarks2D: [LandmarkType: CGPoint] = [:]
    @State private var facePhoto: NSImage?
    @State private var isPlacingLandmarks: Bool = false
    @State private var landmarksLocked: Bool = false
    @State private var triggerSnapshot: Bool = false
    @State private var isRulerToolActive: Bool = false
    @State private var ruler2D = GoldenRulerState()
    @State private var ruler3D = GoldenRulerState()
    
    // CUSTOM CURVE
    @State private var isDrawingCurve: Bool = false
    @State private var customCurvePoints: [SCNVector3] = []
    
    // LIBRARY STATE
    @State private var isImportingLibrary: Bool = false
    @State private var importedFiles: [URL] = []
    @State private var toothAssignments: [String: URL] = [:]
    @State private var libraryID: UUID = UUID()
    
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
    
    @State private var showGoldenRatio: Bool = false
    @State private var templateVisible: Bool = true
    @State private var toothStates: [String: ToothState] = [:]
    @State private var selectedToothName: String? = nil
    @State private var archPosX: Float = 0.0; @State private var archPosY: Float = 0.0; @State private var archPosZ: Float = 0.05
    @State private var archWidth: Float = 1.0; @State private var archCurve: Float = 0.5
    @State private var toothLength: Float = 1.0; @State private var toothRatio: Float = 0.8
    
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
                HStack {
                    Text("Smile Studio").font(.title2).fontWeight(.bold)
                    Spacer()
                    Button(action: { isImporting3D = true }) { Image(systemName: "cube") }.buttonStyle(.plain).font(.title2)
                    Button(action: { isImportingPhoto = true }) { Image(systemName: "photo") }.buttonStyle(.plain).font(.title2).padding(.leading, 8)
                    if session.activeScanURL != nil || facePhoto != nil { Button(action: { showDeleteConfirmation = true }) { Image(systemName: "trash").foregroundStyle(.red) }.buttonStyle(.plain).font(.title2).padding(.leading, 8) }
                }.padding(.top)
                
                Divider()
                
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
                            HStack {
                                Toggle(isOn: $isPlacingLandmarks) { Label("Place", systemImage: "target") }.toggleStyle(.button).disabled(landmarksLocked)
                                Toggle(isOn: $landmarksLocked) { Label(landmarksLocked ? "Locked" : "Unlocked", systemImage: landmarksLocked ? "lock.fill" : "lock.open.fill") }.toggleStyle(.button).tint(landmarksLocked ? .orange : .green)
                            }.controlSize(.large).frame(maxWidth: .infinity)
                            Toggle(isOn: $isRulerToolActive) { Label("Golden Percentage", systemImage: "ruler.fill").foregroundStyle(isRulerToolActive ? .yellow : .primary) }.toggleStyle(.button).frame(maxWidth: .infinity).tint(.yellow).padding(.top, 5)
                            Divider()
                            if isRulerToolActive { Text("Click & Drag to measure (23% - 15% - 12%)").font(.caption).foregroundStyle(.yellow) } else if landmarksLocked { Text("Unlock to edit. Drag to Pan/Zoom.").font(.caption2).foregroundStyle(.secondary) } else if isPlacingLandmarks { Text("Tap to place points. Drag to adjust.").font(.caption2).foregroundStyle(.blue) } else { Text("View mode. Drag to Pan. Pinch to Zoom.").font(.caption2).foregroundStyle(.secondary) }
                            if !isRulerToolActive, let target = nextLandmark { Text("Next: \(target.rawValue)").font(.title3).fontWeight(.bold).foregroundStyle(.blue).padding(.vertical, 5) } else if !isRulerToolActive { Text("✅ Analysis Complete").font(.headline).foregroundStyle(.green); Button("Start Design") { currentMode = .design; templateVisible = true; isPlacingLandmarks = false }.buttonStyle(.borderedProminent) }
                            Divider()
                            Button("Reset All Landmarks") { landmarks3D.removeAll(); landmarks2D.removeAll(); landmarksLocked = false; ruler2D = GoldenRulerState(); ruler3D = GoldenRulerState() }.buttonStyle(.bordered).controlSize(.small)
                        }
                    case .design:
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Smile Curve").font(.headline)
                            HStack {
                                Toggle(isOn: $isDrawingCurve) { Label(isDrawingCurve ? "Drawing..." : "Draw Curve", systemImage: "pencil.and.outline") }.toggleStyle(.button).tint(.orange)
                                Button(role: .destructive) { customCurvePoints.removeAll() } label: { Image(systemName: "eraser") }.disabled(customCurvePoints.isEmpty)
                            }
                            if !customCurvePoints.isEmpty { Text("✅ Using Custom Curve").font(.caption).foregroundStyle(.green) } else if isDrawingCurve { Text("Draw on the 3D model...").font(.caption).foregroundStyle(.orange) }
                            
                            Divider()
                            
                            Button(action: { isImportingLibrary = true }) {
                                Label("Import Tooth Library", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                            
                            if !importedFiles.isEmpty {
                                Text("Assign Shapes:").font(.caption).bold().padding(.top, 5)
                                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                                    GridRow { Text("Central").frame(width: 50, alignment: .leading); ToothPicker(selection: bindingFor("Central"), files: importedFiles) }
                                    GridRow { Text("Lateral").frame(width: 50, alignment: .leading); ToothPicker(selection: bindingFor("Lateral"), files: importedFiles) }
                                    GridRow { Text("Canine").frame(width: 50, alignment: .leading); ToothPicker(selection: bindingFor("Canine"), files: importedFiles) }
                                }
                                .padding(8).background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                            }
                            
                            Divider()
                            
                            DesignToolsView(
                                templateVisible: $templateVisible, showGoldenRatio: $showGoldenRatio, selectedToothName: $selectedToothName,
                                toothStates: $toothStates, archPosX: $archPosX, archPosY: $archPosY, archPosZ: $archPosZ,
                                archWidth: $archWidth, archCurve: $archCurve, toothLength: $toothLength, toothRatio: $toothRatio
                            )
                        }
                    }
                }
                Spacer()
                if facePhoto != nil { HStack { Button("Download Analysis") { isExporting2D = true }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity) } }
                Divider()
                ExportToolsView(isExporting: $isExporting, selectedFormat: $selectedFormat)
            }
            .frame(width: 280).padding().background(Color(nsColor: .windowBackgroundColor))
            
            // RIGHT PANEL
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if let image = facePhoto {
                        ZStack(alignment: .topTrailing) {
                            PhotoAnalysisView(image: image, landmarks: $landmarks2D, isPlacing: isPlacingLandmarks, isLocked: landmarksLocked, activeType: nextLandmark).overlay(GoldenRulerOverlay(isActive: isRulerToolActive, state: $ruler2D)).background(Color.black)
                            Button(action: { facePhoto = nil; landmarks2D.removeAll(); ruler2D = GoldenRulerState() }) { Image(systemName: "trash.circle.fill").font(.system(size: 24)).foregroundStyle(.white, .red).shadow(radius: 2) }.buttonStyle(.plain).padding(10)
                        }.frame(width: session.activeScanURL != nil ? geo.size.width * 0.5 : geo.size.width)
                    }
                    if let url = session.activeScanURL {
                        ZStack(alignment: .bottomTrailing) {
                            DesignSceneWrapper(
                                scanURL: url, mode: currentMode, showSmileTemplate: (currentMode == .design && templateVisible),
                                smileParams: SmileTemplateParams(posX: archPosX, posY: archPosY, posZ: archPosZ, scale: archWidth, curve: archCurve, length: toothLength, ratio: toothRatio),
                                toothStates: toothStates, onToothSelected: { selectedToothName = $0 }, onToothTransformChange: { toothStates[$0] = $1 },
                                landmarks: landmarks3D, activeLandmarkType: nextLandmark, isPlacingLandmarks: (isPlacingLandmarks && facePhoto == nil && !landmarksLocked),
                                onLandmarkPicked: { pos in if let t = nextLandmark { landmarks3D[t] = pos } },
                                triggerSnapshot: $triggerSnapshot, onSnapshotTaken: { img in self.facePhoto = img; self.statusMessage = "📸 Snapshot Taken" },
                                showGrid: (currentMode == .design && showGoldenRatio),
                                toothLibrary: toothAssignments,
                                libraryID: libraryID,
                                isDrawingCurve: isDrawingCurve,
                                customCurvePoints: $customCurvePoints
                            ).id(url).overlay(GoldenRulerOverlay(isActive: isRulerToolActive, state: $ruler3D))
                            Button(action: { triggerSnapshot = true }) { Image(systemName: "camera.viewfinder").font(.largeTitle).padding().background(Circle().fill(Color.white.opacity(0.8))) }.buttonStyle(.plain).padding()
                        }.frame(width: facePhoto != nil ? geo.size.width * 0.5 : geo.size.width)
                    }
                    if facePhoto == nil && session.activeScanURL == nil { ContentUnavailableView("No Content", systemImage: "square.dashed").frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
            }
        }
        .fileImporter(isPresented: $isImporting3D, allowedContentTypes: [UTType.usdz, UTType.stl, UTType.obj]) { res in handleImport3D(res) }
        .fileImporter(isPresented: $isImportingPhoto, allowedContentTypes: [UTType.jpeg, UTType.png, UTType.heic]) { res in handleImportPhoto(res) }
        .fileImporter(isPresented: $isImportingLibrary, allowedContentTypes: [UTType.folder, UTType.obj], allowsMultipleSelection: true) { res in handleImportLibrary(res) }
        .fileExporter(isPresented: $isExporting, document: GenericFile(sourceURL: session.activeScanURL), contentType: UTType.data, defaultFilename: "Project3D") { _ in }
        .fileExporter(isPresented: $isExporting2D, document: ImageFile(image: render2DAnalysis()), contentType: .png, defaultFilename: "Analysis_Snapshot") { _ in }
        .alert("Clear Workspace?", isPresented: $showDeleteConfirmation) { Button("Cancel", role: .cancel) { }; Button("Clear All", role: .destructive) { session.activeScanURL = nil; facePhoto = nil; landmarks2D.removeAll(); landmarks3D.removeAll(); toothAssignments.removeAll(); importedFiles.removeAll(); customCurvePoints.removeAll() } }
    }
    
    // Binding helper
    func bindingFor(_ key: String) -> Binding<URL?> {
        Binding(
            get: { toothAssignments[key] },
            set: { newVal in
                if let url = newVal { toothAssignments[key] = url }
                else { toothAssignments.removeValue(forKey: key) }
                libraryID = UUID()
            }
        )
    }
    
    @MainActor func render2DAnalysis() -> NSImage? {
        guard let image = facePhoto else { return nil }
        let renderer = ImageRenderer(content: PhotoAnalysisView(image: image, landmarks: $landmarks2D, isPlacing: false, isLocked: true, activeType: nil).overlay(GoldenRulerOverlay(isActive: false, state: $ruler2D)).frame(width: image.size.width, height: image.size.height))
        renderer.scale = 2.0; return renderer.nsImage
    }
    
    func handleImport3D(_ result: Result<URL, Error>) { if case .success(let url) = result { guard url.startAccessingSecurityScopedResource() else { return }; defer { url.stopAccessingSecurityScopedResource() }; let dst = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent); try? FileManager.default.removeItem(at: dst); try? FileManager.default.copyItem(at: url, to: dst); DispatchQueue.main.async { session.activeScanURL = dst; statusMessage = "✅ 3D Model Loaded" } } }
    func handleImportPhoto(_ result: Result<URL, Error>) { if case .success(let url) = result { guard url.startAccessingSecurityScopedResource() else { return }; defer { url.stopAccessingSecurityScopedResource() }; if let img = NSImage(contentsOf: url) { DispatchQueue.main.async { facePhoto = img; statusMessage = "✅ Photo Loaded" } } } }
    
    func handleImportLibrary(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            var foundFiles: [URL] = []
            func scan(_ url: URL) {
                let start = url.startAccessingSecurityScopedResource()
                defer { if start { url.stopAccessingSecurityScopedResource() } }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) { for content in contents { scan(content) } }
                } else if url.pathExtension.lowercased() == "obj" { foundFiles.append(url) }
            }
            for url in urls { scan(url) }
            DispatchQueue.main.async { self.importedFiles = foundFiles; self.statusMessage = "✅ Found \(foundFiles.count) files." }
        }
    }
}

// Picker Helper
struct ToothPicker: View {
    @Binding var selection: URL?
    let files: [URL]
    var body: some View {
        Menu {
            ForEach(files, id: \.self) { file in Button(file.lastPathComponent) { selection = file } }
            Divider()
            Button("None (Procedural)") { selection = nil }
        } label: {
            HStack {
                Text(selection?.lastPathComponent ?? "Select File...").font(.caption).truncationMode(.middle)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .padding(4).background(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.5)))
        }
        .menuStyle(.borderlessButton).frame(maxWidth: .infinity)
    }
}

// Golden Ruler Views (Not duplicate if confined to this file or extracted to separate file, assuming unique)
// If GoldenRulerOverlay is in another file, remove it from here.
// Assuming it is NOT in Components/PhotoAnalysisView.swift based on previous checks.
struct GoldenRulerOverlay: View { var isActive: Bool; @Binding var state: GoldenRulerState; var body: some View { ZStack { Color.clear.contentShape(Rectangle()).allowsHitTesting(isActive && !state.isVisible).gesture(DragGesture(minimumDistance: 0).onChanged { val in if !state.isVisible { state.start = val.startLocation; state.end = val.location } }.onEnded { val in state.end = val.location; if hypot(state.end.x - state.start.x, state.end.y - state.start.y) > 20 { state.isVisible = true } }); if state.isVisible { RulerGraphic(start: state.start, end: state.end); RulerHandle(pos: $state.start); RulerHandle(pos: $state.end) } } } }
struct RulerHandle: View { @Binding var pos: CGPoint; var body: some View { Circle().fill(Color.yellow).frame(width: 8, height: 8).shadow(radius: 1).position(pos).gesture(DragGesture().onChanged { val in pos = val.location }) } }
struct RulerGraphic: View { var start: CGPoint; var end: CGPoint; var body: some View { Canvas { context, size in var path = Path(); path.move(to: start); path.addLine(to: end); context.stroke(path, with: .color(.yellow), lineWidth: 2); let dx = end.x - start.x; let dy = end.y - start.y; let len = sqrt(dx*dx + dy*dy); let px = -dy / len * 15; let py = dx / len * 15; let caps = [0.0, 1.0]; for p in caps { let tx = start.x + dx * p; let ty = start.y + dy * p; var cap = Path(); cap.move(to: CGPoint(x: tx - px, y: ty - py)); cap.addLine(to: CGPoint(x: tx + px, y: ty + py)); context.stroke(cap, with: .color(.yellow), lineWidth: 2) }; let percentages: [CGFloat] = [0.12, 0.27, 0.50, 0.73, 0.88]; for p in percentages { let tx = start.x + dx * p; let ty = start.y + dy * p; var tick = Path(); tick.move(to: CGPoint(x: tx - px, y: ty - py)); tick.addLine(to: CGPoint(x: tx + px, y: ty + py)); context.stroke(tick, with: .color(.yellow), lineWidth: (p == 0.5 ? 3 : 1.5)) }; let midX = start.x + dx * 0.5; let midY = start.y + dy * 0.5; context.draw(Text("23-15-12 %").font(.caption2).bold().foregroundColor(.yellow), at: CGPoint(x: midX, y: midY - 20)) }.allowsHitTesting(false) } }
