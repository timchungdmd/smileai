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
    
    @StateObject private var selectionManager = SelectionManager()
    @StateObject private var history = TransformHistory()
    
    @State private var templateVisible: Bool = true
    @State private var toothStates: [String: ToothState] = [:]
    @State private var showGoldenRatio: Bool = false
    @State private var snapSettings = SnapSettings()
    
    // Arch parameters
    @State private var archPosX: Float = 0.0
    @State private var archPosY: Float = 0.0
    @State private var archPosZ: Float = 0.05
    @State private var archWidth: Float = 1.0
    @State private var archCurve: Float = 0.5
    @State private var toothLength: Float = 1.0
    @State private var toothRatio: Float = 0.8
    @State private var previousArchParams: SmileTemplateParams?
    
    @State private var toothLibrary = ToothLibraryManager()
    @State private var isImportingLibrary: Bool = false
    
    @State private var isExporting = false
    @State private var isImporting3D = false
    @State private var isImportingPhoto = false
    @State private var showDeleteConfirmation = false
    @State private var selectedFormat: GeometryUtils.ExportFormat = .stl
    
    // Validation
    @State private var showValidationReport = false
    @State private var validationReport: ValidationReport?
    
    var nextLandmark: LandmarkType? {
        let sequence = LandmarkType.allCases
        return facePhoto != nil
            ? sequence.first(where: { landmarks2D[$0] == nil })
            : sequence.first(where: { landmarks3D[$0] == nil })
    }
    
    var currentArchParams: SmileTemplateParams {
        SmileTemplateParams(
            posX: archPosX,
            posY: archPosY,
            posZ: archPosZ,
            scale: archWidth,
            curve: archCurve,
            length: toothLength,
            ratio: toothRatio
        )
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT SIDEBAR
            VStack(alignment: .leading, spacing: 20) {
                headerView
                Divider()
                
                if session.activeScanURL == nil && facePhoto == nil {
                    emptyStateView
                } else {
                    contentView
                }
                
                Spacer()
                
                if currentMode == .design {
                    undoRedoSection
                    Divider()
                }
                
                exportSection
            }
            .frame(width: 300)
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // RIGHT PANEL
            mainSceneView
        }
        .fileImporter(
            isPresented: $isImporting3D,
            allowedContentTypes: [.usdz, .stl, .obj]
        ) { handleImport3D($0) }
        .fileImporter(
            isPresented: $isImportingPhoto,
            allowedContentTypes: [.jpeg, .png, .heic]
        ) { handleImportPhoto($0) }
        .fileImporter(
            isPresented: $isImportingLibrary,
            allowedContentTypes: [.folder, .obj],
            allowsMultipleSelection: true
        ) { handleImportLibrary($0) }
        .fileExporter(
            isPresented: $isExporting,
            document: GenericFile(sourceURL: session.activeScanURL),
            contentType: UTType.data,
            defaultFilename: "SmileDesign"
        ) { _ in }
        .alert("Validation Report", isPresented: $showValidationReport) {
            Button("OK") { }
            if validationReport?.passed == false {
                Button("Export Anyway") { isExporting = true }
            }
        } message: {
            Text(validationReport?.summary ?? "Unknown error")
        }
        .alert("Clear Workspace?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                session.activeScanURL = nil
                facePhoto = nil
                landmarks2D.removeAll()
                landmarks3D.removeAll()
                toothStates.removeAll()
                history.clear()
                selectionManager.deselectAll()
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        HStack {
            Text("Smile Studio")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            Button(action: { isImporting3D = true }) {
                Image(systemName: "cube")
            }
            .buttonStyle(.plain)
            .font(.title2)
            .help("Import 3D Model")
            
            Button(action: { isImportingPhoto = true }) {
                Image(systemName: "photo")
            }
            .buttonStyle(.plain)
            .font(.title2)
            .padding(.leading, 8)
            .help("Import Face Photo")
            
            if session.activeScanURL != nil || facePhoto != nil {
                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .font(.title2)
                .padding(.leading, 8)
            }
        }
        .padding(.top)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "Empty Workspace",
                systemImage: "macwindow",
                description: Text("Import a 3D Scan or 2D Photo to begin.")
            )
            
            HStack {
                Button("Load 3D") { isImporting3D = true }
                    .buttonStyle(.borderedProminent)
                Button("Load Photo") { isImportingPhoto = true }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Picker("Mode", selection: $currentMode) {
                ForEach(DesignMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            Divider()
            
            switch currentMode {
            case .analysis:
                analysisControlsView
            case .design:
                designControlsView
            }
        }
    }
    
    private var analysisControlsView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Esthetic Analysis", systemImage: "scope")
                .font(.headline)
            
            HStack {
                Toggle(isOn: $isPlacingLandmarks) {
                    Label("Place", systemImage: "target")
                }
                .toggleStyle(.button)
                .disabled(landmarksLocked)
                
                Toggle(isOn: $landmarksLocked) {
                    Label(
                        landmarksLocked ? "Locked" : "Unlocked",
                        systemImage: landmarksLocked ? "lock.fill" : "lock.open.fill"
                    )
                }
                .toggleStyle(.button)
                .tint(landmarksLocked ? .orange : .green)
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            
            if let target = nextLandmark {
                Text("Next: \(target.rawValue)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
                    .padding(.vertical, 5)
            } else {
                Text("✅ Analysis Complete")
                    .font(.headline)
                    .foregroundStyle(.green)
                
                Button("Start Design") {
                    currentMode = .design
                    templateVisible = true
                    isPlacingLandmarks = false
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            Button("Reset All Landmarks") {
                landmarks3D.removeAll()
                landmarks2D.removeAll()
                landmarksLocked = false
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    private var designControlsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                // Selection Info
                if selectionManager.hasSelection {
                    HStack {
                        Label("\(selectionManager.selectionCount) Selected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                        Spacer()
                        Button("Deselect All") {
                            selectionManager.deselectAll()
                        }
                        .font(.caption)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
                }
                
                // Mirror Mode Toggle
                Toggle(isOn: $selectionManager.mirrorMode) {
                    Label("Mirror Mode", systemImage: "arrow.left.and.right")
                }
                .toggleStyle(.switch)
                .tint(.purple)
                
                Divider()
                
                // Tooth Library
                Text("Tooth Library").font(.headline)
                
                Button(action: { isImportingLibrary = true }) {
                    Label("Import Files", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Divider()
                
                // Template Toggle
                Toggle("Show Template", isOn: $templateVisible)
                Toggle("Golden Ratio Grid", isOn: $showGoldenRatio)
                Toggle("Snap to Grid", isOn: $snapSettings.enabled)
                
                if snapSettings.enabled {
                    HStack {
                        Text("Grid Size:")
                            .font(.caption)
                        Slider(value: Binding(
                            get: { Double(snapSettings.gridSize * 1000) },
                            set: { snapSettings.gridSize = Float($0) / 1000 }
                        ), in: 0.1...5.0)
                        Text("\(snapSettings.gridSize * 1000, specifier: "%.1f")mm")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                // Tooth Controls
                if selectionManager.hasSelection {
                    selectedToothControls
                } else {
                    archControlsView
                }
            }
        }
    }
    
    private var selectedToothControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Multi-Tooth Controls")
                .font(.headline)
                .foregroundStyle(.blue)
            
            Text("Use Gizmo or Option+Scroll to transform")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Batch operations
            VStack(alignment: .leading, spacing: 8) {
                Text("Batch Operations").font(.subheadline)
                
                HStack {
                    Button("Reset Position") {
                        batchResetPosition()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Reset Scale") {
                        batchResetScale()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Button("Reset All") {
                    batchResetAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
        }
    }
    
    private var archControlsView: some View {
        Group {
            Text("Position").font(.headline)
            SliderRow(
                label: "Up/Down",
                value: $archPosY,
                range: -0.1...0.1,
                format: "%.3f",
                onChange: { handleArchChange() }
            )
            SliderRow(
                label: "Left/Right",
                value: $archPosX,
                range: -0.05...0.05,
                format: "%.3f",
                onChange: { handleArchChange() }
            )
            SliderRow(
                label: "Fwd/Back",
                value: $archPosZ,
                range: -0.1...0.2,
                format: "%.3f",
                onChange: { handleArchChange() }
            )
            
            Divider()
            
            Text("Shape").font(.headline)
            SliderRow(
                label: "Width",
                value: $archWidth,
                range: 0.5...2.0,
                format: "%.2f",
                onChange: { handleArchChange() }
            )
            SliderRow(
                label: "Curve",
                value: $archCurve,
                range: 0.0...1.0,
                format: "%.2f",
                onChange: { handleArchChange() }
            )
            SliderRow(
                label: "Length",
                value: $toothLength,
                range: 0.5...2.0,
                format: "%.2f",
                onChange: { handleArchChange() }
            )
            SliderRow(
                label: "Ratio",
                value: $toothRatio,
                range: 0.5...1.0,
                format: "%.2f",
                onChange: { handleArchChange() }
            )
        }
    }
    
    private var undoRedoSection: some View {
        HStack {
            Button(action: { history.undo() }) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(!history.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            
            Button(action: { history.redo() }) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .buttonStyle(.bordered)
            .disabled(!history.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .frame(maxWidth: .infinity)
    }
    
    private var exportSection: some View {
        VStack(spacing: 10) {
            Divider()
            
            Button("Validate Design") {
                validateDesign()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            
            HStack {
                Picker("", selection: $selectedFormat) {
                    Text("STL").tag(GeometryUtils.ExportFormat.stl)
                    Text("OBJ").tag(GeometryUtils.ExportFormat.obj)
                    Text("USDZ").tag(GeometryUtils.ExportFormat.usdz)
                }
                .frame(width: 100)
                
                Button("Export") {
                    isExporting = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.activeScanURL == nil)
            }
        }
    }
    
    private var mainSceneView: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                if let image = facePhoto {
                    photoView(image: image, width: session.activeScanURL != nil ? geo.size.width * 0.5 : geo.size.width)
                }
                
                if let url = session.activeScanURL {
                    sceneView(url: url, width: facePhoto != nil ? geo.size.width * 0.5 : geo.size.width)
                }
                
                if facePhoto == nil && session.activeScanURL == nil {
                    ContentUnavailableView("No Content", systemImage: "square.dashed")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    
    private func photoView(image: NSImage, width: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            PhotoAnalysisView(
                image: image,
                landmarks: $landmarks2D,
                isPlacing: isPlacingLandmarks,
                isLocked: landmarksLocked,
                activeType: nextLandmark
            )
            .background(Color.black)
            
            Button(action: {
                facePhoto = nil
                landmarks2D.removeAll()
            }) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white, .red)
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .frame(width: width)
    }
    
    private func sceneView(url: URL, width: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            DesignSceneWrapper(
                scanURL: url,
                mode: currentMode,
                showSmileTemplate: (currentMode == .design && templateVisible),
                smileParams: currentArchParams,
                toothStates: toothStates,
                onToothSelected: { id, multiSelect in
                    if let id = id {
                        selectionManager.selectTooth(id, multiSelect: multiSelect)
                    } else {
                        selectionManager.deselectAll()
                    }
                },
                onToothTransformChange: handleToothTransform,
                landmarks: landmarks3D,
                activeLandmarkType: nextLandmark,
                isPlacingLandmarks: (isPlacingLandmarks && facePhoto == nil && !landmarksLocked),
                onLandmarkPicked: { pos in
                    if let t = nextLandmark {
                        landmarks3D[t] = pos
                    }
                },
                triggerSnapshot: $triggerSnapshot,
                onSnapshotTaken: { img in
                    self.facePhoto = img
                },
                showGrid: (currentMode == .design && showGoldenRatio),
                snapSettings: snapSettings,
                toothLibrary: toothLibrary,
                selectionManager: selectionManager
            )
            .id(url)
            
            Button(action: { triggerSnapshot = true }) {
                Image(systemName: "camera.viewfinder")
                    .font(.largeTitle)
                    .padding()
                    .background(Circle().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .padding()
        }
        .frame(width: width)
    }
    
    // MARK: - Handlers
    
    private func handleToothTransform(_ toothID: String, _ newState: ToothState) {
        toothStates[toothID] = newState
    }
    
    private func handleArchChange() {
        let newParams = currentArchParams
        
        if let oldParams = previousArchParams {
            let command = ArchTransformCommand(
                oldParams: oldParams,
                newParams: newParams
            ) { [self] params in
                self.archPosX = params.posX
                self.archPosY = params.posY
                self.archPosZ = params.posZ
                self.archWidth = params.scale
                self.archCurve = params.curve
                self.toothLength = params.length
                self.toothRatio = params.ratio
            }
            
            history.pushCommand(command)
        }
        
        previousArchParams = newParams
    }
    
    private func batchResetPosition() {
        var commands: [ToothTransformCommand] = []
        
        for id in selectionManager.selectedToothIDs {
            let oldState = toothStates[id] ?? ToothState()
            var newState = oldState
            newState.position = SCNVector3Zero
            
            commands.append(ToothTransformCommand(
                toothID: id,
                oldState: oldState,
                newState: newState
            ) { [self] toothID, state in
                self.toothStates[toothID] = state
            })
        }
        
        if !commands.isEmpty {
            history.pushCommand(BatchTransformCommand(commands: commands))
        }
    }
    
    private func batchResetScale() {
        var commands: [ToothTransformCommand] = []
        
        for id in selectionManager.selectedToothIDs {
            let oldState = toothStates[id] ?? ToothState()
            var newState = oldState
            newState.scale = SCNVector3(1, 1, 1)
            
            commands.append(ToothTransformCommand(
                toothID: id,
                oldState: oldState,
                newState: newState
            ) { [self] toothID, state in
                self.toothStates[toothID] = state
            })
        }
        
        if !commands.isEmpty {
            history.pushCommand(BatchTransformCommand(commands: commands))
        }
    }
    
    private func batchResetAll() {
        var commands: [ToothTransformCommand] = []
        
        for id in selectionManager.selectedToothIDs {
            let oldState = toothStates[id] ?? ToothState()
            let newState = ToothState()
            
            commands.append(ToothTransformCommand(
                toothID: id,
                oldState: oldState,
                newState: newState
            ) { [self] toothID, state in
                self.toothStates[toothID] = state
            })
        }
        
        if !commands.isEmpty {
            history.pushCommand(BatchTransformCommand(commands: commands))
        }
    }
    
    private func validateDesign() {
        let validator = ExportValidator()
        
        // In production, you would extract actual tooth nodes from the scene
        let mockTeeth: [String: SCNNode] = [:]
        
        let report = validator.validate(
            teeth: mockTeeth,
            states: toothStates,
            landmarks: landmarks3D
        )
        
        validationReport = report
        showValidationReport = true
    }
    
    func handleImport3D(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: url, to: dst)
            
            DispatchQueue.main.async {
                session.activeScanURL = dst
                history.clear()
            }
        }
    }
    
    func handleImportPhoto(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            
            if let img = NSImage(contentsOf: url) {
                DispatchQueue.main.async {
                    facePhoto = img
                }
            }
        }
    }
    
    func handleImportLibrary(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            do {
                try toothLibrary.loadFromFolder(urls)
            } catch {
                print("Library import error: \(error)")
            }
        }
    }
}

// MARK: - Helper Views

struct SliderRow: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var format: String = "%.2f"
    var onChange: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .frame(width: 80, alignment: .leading)
                Spacer()
                Text(String(format: format, value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .onChange(of: value) { _, _ in
                    onChange?()
                }
        }
    }
}
