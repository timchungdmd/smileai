import SwiftUI
import SceneKit
import UniformTypeIdentifiers
import AVFoundation

struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    
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
    @State private var isRulerLocked: Bool = false // NEW STATE FOR RULER LOCK
    @State private var ruler2D = GoldenRulerState()
    @State private var ruler3D = GoldenRulerState()
    
    // CUSTOM CURVE
    @State private var isDrawingCurve: Bool = false
    @State private var isCurveLocked: Bool = false
    @State private var customCurvePoints: [SCNVector3] = []
    
    // LIBRARY
    @State private var isImportingLibrary: Bool = false
    @State private var importedFiles: [URL] = []
    @State private var toothAssignments: [String: URL] = [:]
    @State private var libraryID: UUID = UUID()
    @State private var isTargeted: Bool = false
    
    // DESIGN PARAMS
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
    
    var nextLandmark: LandmarkType? {
        let sequence: [LandmarkType] = [.rightPupil, .leftPupil, .glabella, .subnasale, .menton, .rightCommissure, .leftCommissure, .upperLipCenter, .lowerLipCenter, .midline, .rightCanine, .leftCanine]
        return facePhoto != nil ? sequence.first(where: { landmarks2D[$0] == nil }) : sequence.first(where: { landmarks3D[$0] == nil })
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT SIDEBAR
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("Smile Studio").font(.title2).fontWeight(.bold); Spacer(); Button(action: { isImporting3D = true }) { Image(systemName: "cube") }.buttonStyle(.plain); Button(action: { isImportingPhoto = true }) { Image(systemName: "photo") }.buttonStyle(.plain).padding(.leading, 8) }.padding(.top)
                Divider()
                
                if session.activeScanURL == nil && facePhoto == nil {
                    ContentUnavailableView { Label("Drag & Drop", systemImage: "arrow.down.doc") } description: { Text("Drop 3D models or Photos here.") }
                        .frame(maxWidth: .infinity).background(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
                } else {
                    Picker("Mode", selection: $currentMode) { ForEach(DesignMode.allCases) { mode in Text(mode.title).tag(mode) } }.pickerStyle(.segmented)
                    Divider()
                    
                    switch currentMode {
                    case .analysis:
                        VStack(alignment: .leading, spacing: 15) {
                            Label("Analysis", systemImage: "scope").font(.headline)
                            HStack { Toggle(isOn: $isPlacingLandmarks) { Label("Place", systemImage: "target") }.toggleStyle(.button).disabled(landmarksLocked); Toggle(isOn: $landmarksLocked) { Label("Locked", systemImage: landmarksLocked ? "lock.fill" : "lock.open.fill") }.toggleStyle(.button).tint(landmarksLocked ? .orange : .green) }.controlSize(.large).frame(maxWidth: .infinity)
                            
                            // GOLDEN RULER CONTROLS
                            HStack {
                                Toggle(isOn: $isRulerToolActive) {
                                    Label("Golden Ruler", systemImage: "ruler.fill")
                                }
                                .toggleStyle(.button)
                                .frame(maxWidth: .infinity)
                                .tint(.yellow)
                                
                                // Lock Toggle for Ruler
                                Toggle(isOn: $isRulerLocked) {
                                    Image(systemName: isRulerLocked ? "lock.fill" : "lock.open.fill")
                                }
                                .toggleStyle(.button)
                                .tint(isRulerLocked ? .red : .green)
                                .disabled(!isRulerToolActive)
                            }
                            
                            if isRulerToolActive {
                                Text(isRulerLocked ? "Ruler Locked. Unlock to move." : "Drag ends to stretch. Drag center to move.").font(.caption2).foregroundStyle(.yellow)
                                Button("Reset Ruler") { ruler2D = GoldenRulerState(); ruler3D = GoldenRulerState(); isRulerLocked = false }.buttonStyle(.bordered).controlSize(.small)
                            } else if !isRulerToolActive, let target = nextLandmark {
                                Text("Next: \(target.rawValue)").font(.title3).foregroundStyle(.blue)
                            }
                            
                            Divider()
                            Button("Reset All") { landmarks3D.removeAll(); landmarks2D.removeAll(); landmarksLocked = false; ruler2D = GoldenRulerState(); ruler3D = GoldenRulerState() }.buttonStyle(.bordered).controlSize(.small)
                        }
                    case .design:
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Smile Curve").font(.headline)
                            HStack {
                                Toggle(isOn: $isDrawingCurve) { Label(isDrawingCurve ? "Drawing..." : "Draw Curve", systemImage: "pencil.and.outline") }.toggleStyle(.button).tint(.orange).disabled(isCurveLocked)
                                Toggle(isOn: $isCurveLocked) { Image(systemName: isCurveLocked ? "lock.fill" : "lock.open.fill") }.toggleStyle(.button).tint(isCurveLocked ? .red : .green)
                                Spacer()
                                Button(role: .destructive) { customCurvePoints.removeAll(); isCurveLocked = false; isDrawingCurve = false } label: { Image(systemName: "trash") }.disabled(customCurvePoints.isEmpty)
                            }
                            Divider()
                            
                            HStack { Text("Tooth Library").font(.headline); Spacer(); Button(action: { isImportingLibrary = true }) { Image(systemName: "folder.badge.plus") }.buttonStyle(.plain) }
                            if !importedFiles.isEmpty {
                                List(importedFiles, id: \.self) { file in HStack { Image(systemName: "doc.text.fill").foregroundStyle(.blue); Text(file.lastPathComponent).font(.caption).lineLimit(1) }.draggable(file) }.frame(height: 100).listStyle(.bordered(alternatesRowBackgrounds: true))
                                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) { ToothDropSlot(label: "Central", assignment: bindingFor("Central")); ToothDropSlot(label: "Lateral", assignment: bindingFor("Lateral")); ToothDropSlot(label: "Canine", assignment: bindingFor("Canine")) }.padding(8).background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                            } else { Button("Load Library Folder") { isImportingLibrary = true }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
                            Divider()
                            DesignToolsView(templateVisible: $templateVisible, showGoldenRatio: $showGoldenRatio, selectedToothName: $selectedToothName, toothStates: $toothStates, archPosX: $archPosX, archPosY: $archPosY, archPosZ: $archPosZ, archWidth: $archWidth, archCurve: $archCurve, toothLength: $toothLength, toothRatio: $toothRatio)
                        }
                    }
                }
                Spacer()
                ExportToolsView(isExporting: $isExporting, selectedFormat: $selectedFormat)
            }
            .frame(width: 280).padding().background(Color(nsColor: .windowBackgroundColor))
            
            // RIGHT PANEL
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if let image = facePhoto {
                        ZStack(alignment: .topTrailing) {
                            PhotoAnalysisView(image: image, landmarks: $landmarks2D, isPlacing: isPlacingLandmarks, isLocked: landmarksLocked, activeType: nextLandmark)
                                .overlay(GoldenRulerOverlay(isActive: isRulerToolActive, isLocked: isRulerLocked, state: $ruler2D))
                                .background(Color.black)
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
                                triggerSnapshot: $triggerSnapshot, onSnapshotTaken: { img in self.facePhoto = img },
                                showGrid: (currentMode == .design && showGoldenRatio),
                                toothLibrary: toothAssignments, libraryID: libraryID,
                                isDrawingCurve: $isDrawingCurve, isCurveLocked: isCurveLocked, customCurvePoints: $customCurvePoints
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
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in loadFromDrop(providers: providers) }
        .fileImporter(isPresented: $isImporting3D, allowedContentTypes: [UTType.usdz, UTType.stl, UTType.obj]) { res in handleImport3D(res) }
        .fileImporter(isPresented: $isImportingPhoto, allowedContentTypes: [UTType.jpeg, UTType.png, UTType.heic]) { res in handleImportPhoto(res) }
        .fileImporter(isPresented: $isImportingLibrary, allowedContentTypes: [UTType.folder, UTType.obj], allowsMultipleSelection: true) { res in handleImportLibrary(res) }
        .fileExporter(isPresented: $isExporting, document: GenericFile(sourceURL: session.activeScanURL), contentType: UTType.data, defaultFilename: "Project3D") { _ in }
        .fileExporter(isPresented: $isExporting2D, document: ImageFile(image: render2DAnalysis()), contentType: .png, defaultFilename: "Analysis_Snapshot") { _ in }
        .alert("Clear Workspace?", isPresented: $showDeleteConfirmation) { Button("Cancel", role: .cancel) { }; Button("Clear All", role: .destructive) { session.activeScanURL = nil; facePhoto = nil; landmarks2D.removeAll(); landmarks3D.removeAll(); toothAssignments.removeAll(); importedFiles.removeAll(); customCurvePoints.removeAll() } }
    }
    
    // HELPERS
    func bindingFor(_ key: String) -> Binding<URL?> { Binding(get: { toothAssignments[key] }, set: { if let url = $0 { toothAssignments[key] = url } else { toothAssignments.removeValue(forKey: key) }; libraryID = UUID() }) }
    @MainActor func render2DAnalysis() -> NSImage? { guard let image = facePhoto else { return nil }; let renderer = ImageRenderer(content: PhotoAnalysisView(image: image, landmarks: $landmarks2D, isPlacing: false, isLocked: true, activeType: nil).overlay(GoldenRulerOverlay(isActive: false, isLocked: true, state: $ruler2D)).frame(width: image.size.width, height: image.size.height)); renderer.scale = 2.0; return renderer.nsImage }
    func handleImport3D(_ result: Result<URL, Error>) { if case .success(let url) = result { guard url.startAccessingSecurityScopedResource() else { return }; defer { url.stopAccessingSecurityScopedResource() }; let dst = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent); try? FileManager.default.removeItem(at: dst); try? FileManager.default.copyItem(at: url, to: dst); DispatchQueue.main.async { session.activeScanURL = dst; statusMessage = "✅ Loaded" } } }
    func handleImportPhoto(_ result: Result<URL, Error>) { if case .success(let url) = result { guard url.startAccessingSecurityScopedResource() else { return }; defer { url.stopAccessingSecurityScopedResource() }; if let img = NSImage(contentsOf: url) { DispatchQueue.main.async { facePhoto = img; statusMessage = "✅ Loaded" } } } }
    func handleImportLibrary(_ result: Result<[URL], Error>) { if case .success(let urls) = result { var foundFiles: [URL] = []; func scan(_ url: URL) { let start = url.startAccessingSecurityScopedResource(); defer { if start { url.stopAccessingSecurityScopedResource() } }; var isDir: ObjCBool = false; if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { if let c = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) { for f in c { scan(f) } } } else if url.pathExtension.lowercased() == "obj" { foundFiles.append(url) } }; for url in urls { scan(url) }; DispatchQueue.main.async { self.importedFiles = foundFiles; self.statusMessage = "✅ Loaded Lib" } } }
    private func loadFromDrop(providers: [NSItemProvider]) -> Bool { guard let provider = providers.first else { return false }; provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in if let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { DispatchQueue.main.async { if ["obj","stl","usdz"].contains(url.pathExtension.lowercased()) { let dst = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent); try? FileManager.default.removeItem(at: dst); try? FileManager.default.copyItem(at: url, to: dst); session.activeScanURL = dst } else if ["jpg","png"].contains(url.pathExtension.lowercased()), let img = NSImage(contentsOf: url) { facePhoto = img } else { handleImportLibrary(.success([url])) } } } }; return true }
}

// MARK: - DRAG & DROP TOOTH SLOT
struct ToothDropSlot: View {
    let label: String
    @Binding var assignment: URL?
    @State private var isTargeted: Bool = false
    var body: some View {
        GridRow {
            Text(label).frame(width: 50, alignment: .leading)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(isTargeted ? Color.blue.opacity(0.2) : Color.clear).stroke(isTargeted ? Color.blue : Color.gray.opacity(0.5), lineWidth: 1)
                HStack { if let url = assignment { Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle); Spacer(); Button(action: { assignment = nil }) { Image(systemName: "xmark.circle.fill").foregroundStyle(.gray) }.buttonStyle(.plain) } else { Text("Drop here...").font(.caption).foregroundStyle(.secondary); Spacer() } }.padding(4)
            }
            .frame(height: 24)
            .dropDestination(for: URL.self) { items, _ in if let url = items.first { assignment = url; return true }; return false } isTargeted: { isTargeted = $0 }
        }
    }
}

// MARK: - INTERACTIVE GOLDEN RULER (UPDATED WITH LOCK)
struct GoldenRulerOverlay: View {
    var isActive: Bool
    var isLocked: Bool
    @Binding var state: GoldenRulerState
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            // 1. Creation Layer
            if isActive && !state.isVisible {
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { val in state.start = val.startLocation; state.end = val.location }
                        .onEnded { val in state.end = val.location; if hypot(state.end.x-state.start.x, state.end.y-state.start.y) > 20 { state.isVisible = true } }
                    )
            }
            
            // 2. Interactive Ruler
            if state.isVisible {
                // Line & Ticks (Draggable only if unlocked)
                RulerGraphic(start: state.start, end: state.end)
                    .contentShape(Path { path in path.move(to: state.start); path.addLine(to: state.end) }.strokedPath(StrokeStyle(lineWidth: 20)))
                    .gesture(isLocked ? nil : DragGesture()
                        .onChanged { val in
                            let dx = val.translation.width - dragOffset.width
                            let dy = val.translation.height - dragOffset.height
                            state.start.x += dx; state.start.y += dy
                            state.end.x += dx; state.end.y += dy
                            dragOffset = val.translation
                        }
                        .onEnded { _ in dragOffset = .zero }
                    )
                
                // End Handles
                if !isLocked {
                    RulerHandle(pos: $state.start)
                    RulerHandle(pos: $state.end)
                }
            }
        }
    }
}

struct RulerHandle: View {
    @Binding var pos: CGPoint
    var body: some View {
        Circle().fill(Color.yellow).frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
            .shadow(radius: 2)
            .position(pos)
            .gesture(DragGesture().onChanged { val in pos = val.location })
    }
}

struct RulerGraphic: View {
    var start: CGPoint; var end: CGPoint
    var body: some View {
        Canvas { context, size in
            var path = Path(); path.move(to: start); path.addLine(to: end)
            context.stroke(path, with: .color(.yellow), lineWidth: 2)
            let dx = end.x - start.x; let dy = end.y - start.y; let len = sqrt(dx*dx + dy*dy)
            let px = -dy / len * 10; let py = dx / len * 10; let pxL = -dy / len * 20; let pyL = dx / len * 20
            
            func drawTick(at p: CGFloat, isMajor: Bool = false) {
                let tx = start.x + dx * p; let ty = start.y + dy * p; let ox = isMajor ? pxL : px; let oy = isMajor ? pyL : py
                var tick = Path(); tick.move(to: CGPoint(x: tx - ox, y: ty - oy)); tick.addLine(to: CGPoint(x: tx + ox, y: ty + oy))
                context.stroke(tick, with: .color(.yellow), lineWidth: isMajor ? 2.5 : 1.5)
            }
            // 23-15-12 grid
            drawTick(at: 0.0, isMajor: true); drawTick(at: 0.12); drawTick(at: 0.27); drawTick(at: 0.50, isMajor: true)
            drawTick(at: 0.73); drawTick(at: 0.88); drawTick(at: 1.0, isMajor: true)
            
            let midX = start.x + dx * 0.5; let midY = start.y + dy * 0.5
            context.draw(Text("12-15-23 | 23-15-12").font(.system(size: 10, weight: .bold)).foregroundColor(.yellow), at: CGPoint(x: midX, y: midY - 25))
        }.allowsHitTesting(false)
    }
}

struct ExportToolsView: View { @Binding var isExporting: Bool; @Binding var selectedFormat: GeometryUtils.ExportFormat; var body: some View { HStack { Picker("", selection: $selectedFormat) { Text("STL").tag(GeometryUtils.ExportFormat.stl); Text("USDZ").tag(GeometryUtils.ExportFormat.usdz) }.frame(width: 80); Button("Export") { isExporting = true }.buttonStyle(.borderedProminent) } } }
