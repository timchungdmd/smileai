import SwiftUI
import SceneKit
import UniformTypeIdentifiers
import AVFoundation
import simd

struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    @StateObject private var history = TransformHistory()
    
    // MARK: - STATE
    @State private var currentMode: DesignMode = .analysis
    @State private var facePhoto: NSImage?
    @State private var triggerSnapshot: Bool = false
    @State private var isModelLocked: Bool = false
    
    // MARK: - MANAGERS
    @StateObject private var markerManager = AnatomicalMarkerManager()
    @StateObject private var automationManager = SmileAutomationManager()
    @StateObject private var smileOverlayState = SmileOverlayState()
    @StateObject private var alignmentManager = AlignmentManager()
    
    @State private var showAlignmentUI = false
    
    // NEW: Multi-Ratio Calculator State
    @State private var r1Start: LandmarkType = .rightCanine
    @State private var r1End: LandmarkType = .leftCanine
    @State private var r2Start: LandmarkType = .rightCommissure
    @State private var r2End: LandmarkType = .leftCommissure
    @State private var r3Start: LandmarkType = .rightPupil
    @State private var r3End: LandmarkType = .leftPupil
    
    // Tools
    @State private var isRulerToolActive: Bool = false
    @State private var isRulerLocked: Bool = false
    @State private var ruler2D = GoldenRulerState()
    @State private var ruler3D = GoldenRulerState()
    @State private var selectedRatioType: Int = 0
    @State private var isDrawingCurve: Bool = false
    @State private var isCurveLocked: Bool = false
    @State private var customCurvePoints: [SCNVector3] = []
    @State private var useStoneMaterial: Bool = false
    @State private var isImportingLibrary: Bool = false
    @State private var importedFiles: [URL] = []
    @State private var toothAssignments: [String: URL] = [:]
    @State private var libraryID: UUID = UUID()
    @State private var isTargeted: Bool = false
    
    @State private var showReplaceAlert = false
    @State private var replaceAlertData: ReplaceAlertData?
    @State private var showDeleteConfirmation = false
    @State private var statusMessage: String = ""
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
    @State private var isExporting = false
    @State private var isExporting2D = false
    @State private var isImporting3D = false
    @State private var isImportingPhoto = false
    @State private var selectedFormat: GeometryUtils.ExportFormat = .stl
    @State private var show2DOverlaySheet = false
    
    var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 340)
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
        .sheet(isPresented: $show2DOverlaySheet) {
            Smile2DOverlaySheet(state: smileOverlayState, isPresented: $show2DOverlaySheet)
        }
        .alert("Clear Workspace?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                session.activeScanURL = nil
                facePhoto = nil
                markerManager.reset()
                toothAssignments.removeAll()
                importedFiles.removeAll()
                customCurvePoints.removeAll()
            }
        }
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
            HStack {
                Text("Smile Studio").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { isImporting3D = true }) {
                    Image(systemName: "cube")
                }.buttonStyle(.plain)
                Button(action: { isImportingPhoto = true }) {
                    Image(systemName: "photo")
                }.buttonStyle(.plain).padding(.leading, 8)
            }.padding(.top)
            
            Divider()
            
            if session.activeScanURL == nil && facePhoto == nil {
                ContentUnavailableView {
                    Label("Drag & Drop", systemImage: "arrow.down.doc")
                } description: {
                    Text("Drop 3D models or Photos here.")
                }
                .frame(maxWidth: .infinity)
                .background(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
            } else {
                Picker("Mode", selection: $currentMode) {
                    ForEach(DesignMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                Divider()
                
                if showAlignmentUI {
                    alignmentToolsView
                } else {
                    switch currentMode {
                    case .analysis: analysisToolsView
                    case .design: designToolsView
                    }
                }
            }
            
            Spacer()
            
            // Status message
            Text(statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            ExportToolsView(isExporting: $isExporting, selectedFormat: $selectedFormat)
        }
    }
    
    // Alignment UI
    private var alignmentToolsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Align Models").font(.headline)
                Spacer()
                Button("Done") { showAlignmentUI = false }
            }
            
            Picker("Type", selection: $alignmentManager.alignmentType) {
                Text("2D -> 3D").tag(AlignmentManager.AlignmentType.photoToModel)
                Text("3D -> 3D").tag(AlignmentManager.AlignmentType.modelToModel)
            }
            .pickerStyle(.segmented)
            
            List {
                ForEach(alignmentManager.pairs) { pair in
                    HStack {
                        Circle()
                            .fill(pair.isComplete ? Color.green : (alignmentManager.activePairIndex == pair.index - 1 ? Color.blue : Color.gray))
                            .frame(width: 8, height: 8)
                        Text("Point \(pair.index)")
                        Spacer()
                        if pair.point2D != nil { Image(systemName: "photo") }
                        if pair.point3D != nil { Image(systemName: "cube") }
                    }
                    .padding(4)
                    .background(alignmentManager.activePairIndex == pair.index - 1 ? Color.blue.opacity(0.1) : Color.clear)
                    .onTapGesture { alignmentManager.activePairIndex = pair.index - 1 }
                }
            }
            .frame(height: 150)
            
            HStack {
                Button("Reset") { alignmentManager.reset() }
                Spacer()
                Button("Align") {
                    NotificationCenter.default.post(name: NSNotification.Name("PerformAlignment"), object: nil)
                }
                .disabled(alignmentManager.pairs.filter { $0.isComplete }.count < 3)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.blue))
    }
    
    // ✅ FIXED: analysisToolsView with proper structure
    private var analysisToolsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Label("Analysis", systemImage: "scope").font(.headline)
                
                Button(action: { showAlignmentUI.toggle() }) {
                    HStack {
                        Image(systemName: "align.horizontal.center")
                        Text("Align Models")
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                
                Toggle(isOn: $useStoneMaterial) {
                    Label("Stone Mode", systemImage: "circle.lefthalf.filled.righthalf.striped.horizontal")
                }.toggleStyle(.button)
                
                Toggle(isOn: $isModelLocked) {
                    Label(isModelLocked ? "Unlock View" : "Lock View", systemImage: isModelLocked ? "lock.fill" : "lock.open.fill")
                }.toggleStyle(.button).tint(isModelLocked ? .red : .green)
                
                // ANATOMICAL MARKERS
                GroupBox("Anatomical Markers") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(markerManager.getCurrentPrompt(hasFacePhoto: facePhoto != nil))
                            .font(.caption).bold().foregroundStyle(.blue)
                        
                        HStack {
                            Toggle(isOn: $markerManager.isPlacingMode) {
                                Label("Place", systemImage: "target")
                            }.toggleStyle(.button).disabled(markerManager.isLocked)
                            
                            Toggle(isOn: $markerManager.isLocked) {
                                Image(systemName: markerManager.isLocked ? "lock.fill" : "lock.open.fill")
                            }.toggleStyle(.button).tint(markerManager.isLocked ? .orange : .green)
                            
                            Spacer()
                            
                            Button(action: { markerManager.undoLast(hasFacePhoto: facePhoto != nil) }) {
                                Image(systemName: "arrow.uturn.backward")
                            }.disabled(markerManager.isLocked)
                        }
                        
                        DisclosureGroup("Marker Legend") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                                ForEach(LandmarkType.allCases, id: \.self) { lm in
                                    HStack {
                                        Circle().fill(lm.color).frame(width: 8, height: 8)
                                        Text(lm.rawValue).font(.system(size: 10))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: { markerManager.reset() }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Reset Markers")
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
                
                // ✨ PHOTO REGISTRATION with DEBUG
                Divider()
                
                GroupBox("Photo Registration") {
                    VStack(alignment: .leading, spacing: 10) {
                        
                        // 🐛 DEBUG: Photo Status
                        HStack {
                            Image(systemName: facePhoto == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(facePhoto == nil ? .red : .green)
                            Text(facePhoto == nil ? "No photo loaded" : "Photo loaded ✅")
                                .font(.caption2)
                        }
                        .padding(4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                        
                        // Auto-Register Button
                        Button(action: {
                            print("🎯 FOV Button Pressed!")
                            Task {
                                await performAutoFOVEstimation()
                            }
                        }) {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("Estimate FOV")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(facePhoto == nil)
                        
                        // Display Results
                        if let fov = alignmentManager.estimatedFOV {
                            HStack {
                                Text("Field of View:")
                                Spacer()
                                Text(String(format: "%.1f°", fov * 180 / .pi))
                                    .foregroundColor(.green)
                                    .bold()
                            }
                            .font(.caption)
                            .padding(.horizontal, 4)
                        }
                        
                        // Info Text
                        Text("Uses face landmarks to calculate camera FOV")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // RATIO CALCULATOR
                GroupBox("Ratio Calculator") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Measure between markers")
                            .font(.caption).foregroundStyle(.secondary)
                        
                        ratioRow(label: "Ratio 1", start1: $r1Start, end1: $r1End, start2: $r2Start, end2: $r2End)
                        
                        Divider()
                        
                        Text("Additional Comparison").font(.caption).bold().padding(.top, 4)
                        
                        HStack {
                            Text("C:").bold().frame(width: 20)
                            Picker("", selection: $r3Start) {
                                ForEach(LandmarkType.allCases, id: \.self) { lm in
                                    Text(lm.rawValue).tag(lm)
                                }
                            }.labelsHidden()
                            Image(systemName: "arrow.right").font(.caption)
                            Picker("", selection: $r3End) {
                                ForEach(LandmarkType.allCases, id: \.self) { lm in
                                    Text(lm.rawValue).tag(lm)
                                }
                            }.labelsHidden()
                        }
                        
                        if let res = calculateSingleDistance(s: r3Start, e: r3End) {
                            Text("Dist C: \(String(format: "%.1f", res.dist)) \(res.unit)")
                                .font(.caption2).foregroundStyle(.blue)
                        }
                    }
                }
                
                // RULER TOOLS
                HStack {
                    Toggle(isOn: $isRulerToolActive) {
                        Label("Golden Ruler", systemImage: "ruler.fill")
                    }.toggleStyle(.button).frame(maxWidth: .infinity).tint(.yellow)
                    
                    Toggle(isOn: $isRulerLocked) {
                        Image(systemName: isRulerLocked ? "lock.fill" : "lock.open.fill")
                    }.toggleStyle(.button).tint(isRulerLocked ? .red : .green).disabled(!isRulerToolActive)
                }
                
                if isRulerToolActive {
                    GroupBox("Ruler Settings") {
                        VStack {
                            HStack {
                                Image(systemName: "eye")
                                Slider(value: Binding(
                                    get: { ruler2D.opacity },
                                    set: { ruler2D.opacity = $0; ruler3D.opacity = $0 }
                                ), in: 0.1...1.0)
                            }
                            Picker("Ratio", selection: Binding(
                                get: { selectedRatioType },
                                set: { val in
                                    selectedRatioType = val
                                    switch val {
                                    case 0:
                                        ruler2D.setRatioType(.goldenRatio)
                                        ruler3D.setRatioType(.goldenRatio)
                                    case 1:
                                        ruler2D.setRatioType(.goldenPercentage)
                                        ruler3D.setRatioType(.goldenPercentage)
                                    case 2:
                                        ruler2D.setRatioType(.halves)
                                        ruler3D.setRatioType(.halves)
                                    default: break
                                    }
                                }
                            )) {
                                Text("Golden Ratio (φ)").tag(0)
                                Text("Golden %").tag(1)
                                Text("Midline").tag(2)
                            }.pickerStyle(.segmented)
                        }
                    }
                }
            }
            .padding(.trailing, 5)
        }
    }
    
    // Helper: ratio row
    private func ratioRow(label: String, start1: Binding<LandmarkType>, end1: Binding<LandmarkType>, start2: Binding<LandmarkType>, end2: Binding<LandmarkType>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("A:").bold().frame(width: 20)
                Picker("", selection: start1) {
                    ForEach(LandmarkType.allCases, id: \.self) { lm in
                        Text(lm.rawValue).tag(lm)
                    }
                }.labelsHidden()
                Image(systemName: "arrow.right").font(.caption)
                Picker("", selection: end1) {
                    ForEach(LandmarkType.allCases, id: \.self) { lm in
                        Text(lm.rawValue).tag(lm)
                    }
                }.labelsHidden()
            }
            
            HStack {
                Text("B:").bold().frame(width: 20)
                Picker("", selection: start2) {
                    ForEach(LandmarkType.allCases, id: \.self) { lm in
                        Text(lm.rawValue).tag(lm)
                    }
                }.labelsHidden()
                Image(systemName: "arrow.right").font(.caption)
                Picker("", selection: end2) {
                    ForEach(LandmarkType.allCases, id: \.self) { lm in
                        Text(lm.rawValue).tag(lm)
                    }
                }.labelsHidden()
            }
            
            if let result = calculateRatioGeneric(s1: start1.wrappedValue, e1: end1.wrappedValue, s2: start2.wrappedValue, e2: end2.wrappedValue) {
                VStack(alignment: .leading) {
                    Text("Ratio (A/B): \(String(format: "%.3f", result.ratio))").font(.headline).foregroundStyle(.blue)
                    Text("Dist A: \(String(format: "%.1f", result.d1)) | Dist B: \(String(format: "%.1f", result.d2)) \(result.unit)").font(.caption2)
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
            } else {
                Text("Incomplete markers").font(.caption2).foregroundStyle(.red)
            }
        }
    }
    
    private var designToolsView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Smile Curve").font(.headline)
            Button(action: { show2DOverlaySheet = true }) {
                HStack {
                    Image(systemName: "pencil.and.outline")
                    Text("Open 2D Designer")
                }.frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
            
            Divider()
            
            HStack {
                Toggle(isOn: $isDrawingCurve) {
                    Label(isDrawingCurve ? "Drawing..." : "Draw Curve", systemImage: "pencil.and.outline")
                }.toggleStyle(.button).tint(.orange).disabled(isCurveLocked)
                
                Toggle(isOn: $isCurveLocked) {
                    Image(systemName: isCurveLocked ? "lock.fill" : "lock.open.fill")
                }.toggleStyle(.button).tint(isCurveLocked ? .red : .green)
                
                Spacer()
                
                Button(role: .destructive) {
                    customCurvePoints.removeAll()
                    isCurveLocked = false
                    isDrawingCurve = false
                } label: {
                    Image(systemName: "trash")
                }.disabled(customCurvePoints.isEmpty)
            }
            
            Divider()
            
            HStack {
                Text("Library").font(.headline)
                Spacer()
                Button(action: { history.undo() }) {
                    Image(systemName: "arrow.uturn.backward")
                }.disabled(!history.canUndo)
                Button(action: { history.redo() }) {
                    Image(systemName: "arrow.uturn.forward")
                }.disabled(!history.canRedo)
                Button(action: { isImportingLibrary = true }) {
                    Image(systemName: "folder.badge.plus")
                }.buttonStyle(.plain)
            }
            
            if !importedFiles.isEmpty {
                List(importedFiles, id: \.self) { file in
                    HStack {
                        Image(systemName: "doc.text.fill").foregroundStyle(.blue)
                        Text(file.lastPathComponent).font(.caption).lineLimit(1)
                    }.draggable(file)
                }.frame(height: 100).listStyle(.bordered(alternatesRowBackgrounds: true))
                
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    ToothDropSlot(label: "Central", assignment: bindingFor("Central"))
                    ToothDropSlot(label: "Lateral", assignment: bindingFor("Lateral"))
                    ToothDropSlot(label: "Canine", assignment: bindingFor("Canine"))
                }.padding(8).background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
            } else {
                Button("Load Library Folder") {
                    isImportingLibrary = true
                }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            }
            
            Divider()
            
            DesignToolsView(
                templateVisible: $templateVisible,
                showGoldenRatio: $showGoldenRatio,
                selectedToothName: $selectedToothName,
                toothStates: $toothStates,
                archPosX: $archPosX,
                archPosY: $archPosY,
                archPosZ: $archPosZ,
                archWidth: $archWidth,
                archCurve: $archCurve,
                toothLength: $toothLength,
                toothRatio: $toothRatio
            )
            
            Divider()
            
            Button(action: {
                Task {
                    let results = await automationManager.runAutoDesign(
                        overlayState: smileOverlayState,
                        scanNode: nil,
                        antagonistNode: nil
                    )
                    withAnimation {
                        self.toothStates.merge(results) { (_, new) in new }
                        self.currentMode = .design
                    }
                }
            }) {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Auto-Generate 3D Smile")
                }.frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(automationManager.status != .idle)
            
            if case .optimizing(let progress) = automationManager.status {
                ProgressView(value: progress).progressViewStyle(.linear)
            }
        }
    }
    
    private var mainContentView: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                if let image = facePhoto {
                    ZStack(alignment: .topTrailing) {
                        PhotoAnalysisView(
                            image: image,
                            landmarks: $markerManager.landmarks2D,
                            isPlacing: markerManager.isPlacingMode,
                            isLocked: markerManager.isLocked,
                            activeType: markerManager.nextLandmark(hasFacePhoto: true),
                            onTap: { point in
                                if showAlignmentUI && alignmentManager.alignmentType == .photoToModel {
                                    alignmentManager.registerPoint2D(point)
                                }
                            }
                        )
                        .overlay(GoldenRulerOverlay(isActive: isRulerToolActive, isLocked: isRulerLocked, state: $ruler2D))
                        .background(Color.black)
                        
                        Button(action: {
                            facePhoto = nil
                            markerManager.landmarks2D.removeAll()
                        }) {
                            Image(systemName: "trash.circle.fill").font(.title).foregroundStyle(.red)
                        }.buttonStyle(.plain).padding(10)
                    }.frame(width: session.activeScanURL != nil ? geo.size.width * 0.5 : geo.size.width)
                }
                
                if let url = session.activeScanURL {
                    ZStack(alignment: .bottomTrailing) {
                        DesignSceneWrapper(
                            scanURL: url,
                            mode: currentMode,
                            showSmileTemplate: (currentMode == .design && templateVisible),
                            smileParams: SmileTemplateParams(
                                posX: archPosX,
                                posY: archPosY,
                                posZ: archPosZ,
                                scale: archWidth,
                                curve: archCurve,
                                length: toothLength,
                                ratio: toothRatio
                            ),
                            toothStates: toothStates,
                            onToothSelected: { selectedToothName = $0 },
                            onToothTransformChange: { id, newState in toothStates[id] = newState },
                            landmarks: markerManager.landmarks3D,
                            activeLandmarkType: markerManager.nextLandmark(hasFacePhoto: false),
                            isPlacingLandmarks: (markerManager.isPlacingMode && facePhoto == nil && !markerManager.isLocked),
                            onLandmarkPicked: { pos in markerManager.addLandmark3D(pos) },
                            triggerSnapshot: $triggerSnapshot,
                            onSnapshotTaken: { img in facePhoto = img },
                            showGrid: (currentMode == .design && showGoldenRatio),
                            toothLibrary: toothAssignments,
                            libraryID: libraryID,
                            isDrawingCurve: $isDrawingCurve,
                            isCurveLocked: isCurveLocked,
                            customCurvePoints: $customCurvePoints,
                            useStoneMaterial: useStoneMaterial,
                            isModelLocked: isModelLocked,
                            onToothDrop: { toothID, fileURL in handleToothDrop(toothID: toothID, fileURL: fileURL) },
                            showReplaceAlert: $showReplaceAlert,
                            replaceAlertData: $replaceAlertData,
                            automationManager: automationManager,
                            isAlignmentMode: showAlignmentUI,
                            onAlignmentPointPicked: { point3D in
                                alignmentManager.registerPoint3D(point3D)
                            }
                        )
                        .id(url)
                        .overlay(GoldenRulerOverlay(isActive: isRulerToolActive, isLocked: isRulerLocked, state: $ruler3D))
                        
                        Button(action: { triggerSnapshot = true }) {
                            Image(systemName: "camera.viewfinder")
                                .font(.largeTitle)
                                .padding()
                                .background(Circle().fill(Color.white.opacity(0.8)))
                        }.buttonStyle(.plain).padding()
                    }
                    .frame(width: facePhoto != nil ? geo.size.width * 0.5 : geo.size.width)
                }
                
                if facePhoto == nil && session.activeScanURL == nil {
                    ContentUnavailableView("Drag & Drop", systemImage: "arrow.down.doc.fill")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    
    // MARK: - LOGIC & HELPERS
    
    private func calculateRatioGeneric(s1: LandmarkType, e1: LandmarkType, s2: LandmarkType, e2: LandmarkType) -> (d1: Double, d2: Double, ratio: Double, unit: String)? {
        if let _ = facePhoto {
            guard let p1 = markerManager.landmarks2D[s1],
                  let p2 = markerManager.landmarks2D[e1],
                  let p3 = markerManager.landmarks2D[s2],
                  let p4 = markerManager.landmarks2D[e2] else { return nil }
            
            let d1 = Double(hypot(p2.x - p1.x, p2.y - p1.y))
            let d2 = Double(hypot(p4.x - p3.x, p4.y - p3.y))
            if d2 == 0 { return nil }
            return (d1, d2, d1/d2, "px")
        } else if session.activeScanURL != nil {
            guard let p1 = markerManager.landmarks3D[s1],
                  let p2 = markerManager.landmarks3D[e1],
                  let p3 = markerManager.landmarks3D[s2],
                  let p4 = markerManager.landmarks3D[e2] else { return nil }
            
            let v1 = SIMD3<Float>(Float(p1.x), Float(p1.y), Float(p1.z))
            let v2 = SIMD3<Float>(Float(p2.x), Float(p2.y), Float(p2.z))
            let v3 = SIMD3<Float>(Float(p3.x), Float(p3.y), Float(p3.z))
            let v4 = SIMD3<Float>(Float(p4.x), Float(p4.y), Float(p4.z))
            
            let d1 = Double(simd_distance(v1, v2)) * 1000.0
            let d2 = Double(simd_distance(v3, v4)) * 1000.0
            if d2 == 0 { return nil }
            return (d1, d2, d1/d2, "mm")
        }
        return nil
    }
    
    private func calculateSingleDistance(s: LandmarkType, e: LandmarkType) -> (dist: Double, unit: String)? {
        if let _ = facePhoto {
            guard let p1 = markerManager.landmarks2D[s], let p2 = markerManager.landmarks2D[e] else { return nil }
            return (Double(hypot(p2.x - p1.x, p2.y - p1.y)), "px")
        } else if session.activeScanURL != nil {
            guard let p1 = markerManager.landmarks3D[s], let p2 = markerManager.landmarks3D[e] else { return nil }
            let v1 = SIMD3<Float>(Float(p1.x), Float(p1.y), Float(p1.z))
            let v2 = SIMD3<Float>(Float(p2.x), Float(p2.y), Float(p2.z))
            return (Double(simd_distance(v1, v2)) * 1000.0, "mm")
        }
        return nil
    }
    
    private func handleDroppedContent(_ type: DroppedContentType) {
        print("🎯 Dropped: \(type)")
        switch type {
        case .model3D(let url):
            session.activeScanURL = url
            statusMessage = "✅ Loaded Model"
        case .facePhoto(let image):
            self.facePhoto = image
            statusMessage = "✅ Loaded Photo"
            print("✅ facePhoto set: \(self.facePhoto != nil)")
        case .libraryItem(let url):
            handleImportLibrary(.success([url]))
        case .unknown:
            break
        }
    }
    
    private func handleDeleteKey() -> KeyPress.Result {
        if let name = selectedToothName {
            let old = toothStates[name] ?? ToothState()
            history.pushCommand(ToothTransformCommand(
                toothID: name,
                oldState: old,
                newState: ToothState(),
                applyState: { id, s in toothStates[id] = s }
            ))
            toothStates[name] = ToothState()
            return .handled
        }
        if !customCurvePoints.isEmpty {
            customCurvePoints.removeLast()
            return .handled
        }
        return .ignored
    }
    
    func handleToothDrop(toothID: String, fileURL: URL) {
        var typeKey = "Central"
        if toothID.contains("2") {
            typeKey = "Lateral"
        } else if toothID.contains("3") {
            typeKey = "Canine"
        }
        toothAssignments[typeKey] = fileURL
        libraryID = UUID()
        statusMessage = "✅ Replaced \(typeKey) Shape"
    }
    
    func bindingFor(_ key: String) -> Binding<URL?> {
        Binding(
            get: { toothAssignments[key] },
            set: {
                if let url = $0 {
                    toothAssignments[key] = url
                } else {
                    toothAssignments.removeValue(forKey: key)
                }
                libraryID = UUID()
            }
        )
    }
    
    @MainActor
    func render2DAnalysis() -> NSImage? {
        guard let image = facePhoto else { return nil }
        let renderer = ImageRenderer(content:
            PhotoAnalysisView(
                image: image,
                landmarks: $markerManager.landmarks2D,
                isPlacing: false,
                isLocked: true,
                activeType: nil
            )
            .overlay(GoldenRulerOverlay(isActive: false, isLocked: true, state: $ruler2D))
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
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: url, to: dst)
            
            DispatchQueue.main.async {
                session.activeScanURL = dst
                statusMessage = "✅ Loaded Model"
            }
        }
    }
    
    func handleImportPhoto(_ result: Result<URL, Error>) {
        print("📸 handleImportPhoto called")
        
        if case .success(let url) = result {
            print("📸 Photo URL: \(url)")
            
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ Could not access security scoped resource")
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            if let img = NSImage(contentsOf: url) {
                print("✅ Image loaded: \(img.size)")
                DispatchQueue.main.async {
                    self.facePhoto = img
                    self.statusMessage = "✅ Loaded Photo"
                    print("✅ facePhoto set: \(self.facePhoto != nil)")
                }
            } else {
                print("❌ Could not create NSImage")
            }
        }
    }
    
    func handleImportLibrary(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            var foundFiles: [URL] = []
            
            func scan(_ url: URL) {
                let start = url.startAccessingSecurityScopedResource()
                defer { if start { url.stopAccessingSecurityScopedResource() } }
                
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let c = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                        for f in c { scan(f) }
                    }
                } else if url.pathExtension.lowercased() == "obj" {
                    foundFiles.append(url)
                }
            }
            
            for url in urls { scan(url) }
            
            DispatchQueue.main.async {
                self.importedFiles = foundFiles
                self.statusMessage = "✅ Loaded Lib"
            }
        }
    }
    
    // ✨ FOV Estimation
    func performAutoFOVEstimation() async {
        guard let photo = facePhoto else {
            statusMessage = "⚠️ No photo loaded"
            return
        }
        
        statusMessage = "🔄 Detecting face landmarks..."
        
        do {
            guard let landmarks = try await FaceDetectionService.detectLandmarks(in: photo) else {
                statusMessage = "⚠️ No face detected"
                return
            }
            
            statusMessage = "📸 Calculating FOV..."
            
            let fov = alignmentManager.estimateFieldOfView(from: photo, faceLandmarks: landmarks)
            let fovDegrees = fov * 180.0 / Float.pi
            
            statusMessage = "✅ FOV: \(String(format: "%.1f°", fovDegrees))"
            
            print("✅ FOV Complete:")
            print("   FOV: \(String(format: "%.1f°", fovDegrees))")
            print("   Radians: \(String(format: "%.3f", fov))")
            
        } catch {
            statusMessage = "❌ Failed: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
    }
}

// MARK: - Helper Views

struct ToothPicker: View {
    @Binding var selection: URL?
    let files: [URL]
    
    var body: some View {
        Menu {
            ForEach(files, id: \.self) { file in
                Button(file.lastPathComponent) { selection = file }
            }
            Divider()
            Button("None (Procedural)") { selection = nil }
        } label: {
            HStack {
                Text(selection?.lastPathComponent ?? "Select File...").font(.caption).truncationMode(.middle)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.5)))
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity)
    }
}

struct ToothDropSlot: View {
    let label: String
    @Binding var assignment: URL?
    @State private var isTargeted: Bool = false
    
    var body: some View {
        GridRow {
            Text(label).frame(width: 50, alignment: .leading)
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isTargeted ? Color.blue.opacity(0.2) : Color.clear)
                    .stroke(isTargeted ? Color.blue : Color.gray.opacity(0.5), lineWidth: 1)
                
                HStack {
                    if let url = assignment {
                        Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(action: { assignment = nil }) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
                        }.buttonStyle(.plain)
                    } else {
                        Text("Drop here...").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }.padding(4)
            }
            .frame(height: 24)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        DispatchQueue.main.async {
                            if let safeUrl = secureCopy(url) { assignment = safeUrl }
                        }
                    }
                }
                return true
            }
        }
    }
    
    private func secureCopy(_ url: URL) -> URL? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory
            let dst = tempDir.appendingPathComponent(url.lastPathComponent)
            if fileManager.fileExists(atPath: dst.path) { try fileManager.removeItem(at: dst) }
            try fileManager.copyItem(at: url, to: dst)
            return dst
        } catch { return nil }
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
            }
            .frame(width: 80)
            Button("Export") { isExporting = true }
                .buttonStyle(.borderedProminent)
        }
    }
}
