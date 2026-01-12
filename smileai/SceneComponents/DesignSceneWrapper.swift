import SwiftUI
import SceneKit

// MARK: - Shared Data Models
struct ReplaceAlertData: Identifiable {
    let id = UUID()
    var existingID: String
    var newURL: URL
    var newPos: SCNVector3
    var newRot: SCNVector4
}

// MARK: - Wrapper
struct DesignSceneWrapper: NSViewRepresentable {
    // MARK: - Properties
    let scanURL: URL
    // NEW: List of extra imported models
    var importedModels: [Imported3DModel] = []
    
    let mode: DesignMode
    
    var showSmileTemplate: Bool
    var smileParams: SmileTemplateParams
    
    // Tooth Manipulation
    var toothStates: [String: ToothState]
    var onToothSelected: ((String?) -> Void)?
    var onToothTransformChange: ((String, ToothState) -> Void)?
    
    // Landmarks
    var landmarks: [LandmarkType: SCNVector3]
    var activeLandmarkType: LandmarkType?
    var isPlacingLandmarks: Bool
    var onLandmarkPicked: ((SCNVector3) -> Void)?
    
    // Snapshot
    @Binding var triggerSnapshot: Bool
    var onSnapshotTaken: ((NSImage) -> Void)?
    
    // Visualization
    var showGrid: Bool
    var onModelLoaded: ((_ bounds: (min: SCNVector3, max: SCNVector3)) -> Void)? = nil
    
    // Library
    var toothLibrary: [String: URL] = [:]
    var libraryID: UUID = UUID()
    
    // Curve
    @Binding var isDrawingCurve: Bool
    var isCurveLocked: Bool
    @Binding var customCurvePoints: [SCNVector3]
    
    // Rendering
    var useStoneMaterial: Bool
    
    // View Locking
    var isModelLocked: Bool
    
    // Drag & Drop Callbacks
    var onToothDrop: ((String, URL) -> Void)?
    @Binding var showReplaceAlert: Bool
    @Binding var replaceAlertData: ReplaceAlertData?
    
    // Automation
    @ObservedObject var automationManager: SmileAutomationManager
    
    // Alignment
    var isAlignmentMode: Bool = false
    var onAlignmentPointPicked: ((SCNVector3) -> Void)?
    
    // MARK: - Lifecycle
    
    func makeNSView(context: Context) -> EditorView {
        let view = EditorView()
        view.defaultCameraController.interactionMode = .orbitArcball
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        view.scene = SCNScene()
        
        // Connect automation bridge
        DispatchQueue.main.async {
            self.automationManager.projectionDelegate = { points in
                return view.project2DPointsTo3D(points: points)
            }
        }
        
        return view
    }
    
    func updateNSView(_ view: EditorView, context: Context) {
        // 1. Update View Mode & State
        view.currentMode = mode
        view.isAlignmentMode = isAlignmentMode
        view.onAlignmentPointPicked = onAlignmentPointPicked
        
        // 2. Sync Callbacks
        view.onToothSelected = { name in self.onToothSelected?(name) }
        view.onToothTransformChange = onToothTransformChange
        view.onLandmarkPicked = onLandmarkPicked
        view.onToothDrop = onToothDrop
        view.onDropCollision = { id, url, pos, rot in
            DispatchQueue.main.async {
                self.replaceAlertData = ReplaceAlertData(existingID: id, newURL: url, newPos: pos, newRot: rot)
                self.showReplaceAlert = true
            }
        }
        view.onToothAdd = { url, pos, rot in print("Add new tooth at \(pos)") }
        
        // 3. Sync Data
        view.currentToothStates = toothStates
        view.activeLandmarkType = activeLandmarkType
        view.isPlacingLandmarks = isPlacingLandmarks
        view.isDrawingCurve = isDrawingCurve
        view.curveEditor.isLocked = isCurveLocked
        view.curveEditor.onCurveChanged = { points in
            DispatchQueue.main.async {
                self.customCurvePoints = points
                if view.curveEditor.isClosed { self.isDrawingCurve = false }
            }
        }
        if view.curveEditor.points.count != customCurvePoints.count {
            view.curveEditor.setPoints(customCurvePoints)
        }
        view.isModelLocked = isModelLocked
        view.updateSceneRef()
        
        guard let root = view.scene?.rootNode else { return }
        
        // 8. SNAPSHOT
        if triggerSnapshot {
            DispatchQueue.main.async {
                let config = EnhancedSnapshotService.SnapshotConfig(
                    resolution: .match,
                    includeMarkers: true,
                    markerSize: 0.003,
                    antialiasingMode: .multisampling4X,
                    backgroundColor: view.backgroundColor
                )
                if let snapshot = EnhancedSnapshotService.captureSnapshot(from: view, landmarks: landmarks, config: config) {
                    onSnapshotTaken?(snapshot)
                }
                triggerSnapshot = false
            }
        }
        
        setupScene(root, view)
        
        // NEW: Load Extra Models
        updateImportedModels(root: root)
        
        if mode == .analysis, let last = landmarks.values.first, view.defaultCameraController.target.length == 0 {
            view.defaultCameraController.target = last
        }
        
        updateSmileTemplate(root: root)
        updateLandmarkVisuals(root: root)
        drawEstheticAnalysis(root: root)
        updateGrid(root: root)
    }
    
    // MARK: - Scene Setup
    
    private func setupScene(_ root: SCNNode, _ view: EditorView) {
        if root.childNode(withName: "CONTENT_CONTAINER", recursively: false) == nil {
            let c = SCNNode()
            c.name = "CONTENT_CONTAINER"
            root.addChildNode(c)
        }
        
        // Main Patient Model
        if root.childNode(withName: "PATIENT_MODEL", recursively: true) == nil && !scanURL.path.isEmpty {
            let authorized = scanURL.startAccessingSecurityScopedResource()
            defer { if authorized { scanURL.stopAccessingSecurityScopedResource() } }
            
            if let scene = try? SCNScene(url: scanURL, options: nil),
               let geoNode = findFirstGeometryNode(in: scene.rootNode) {
                
                let node = geoNode.clone()
                node.name = "PATIENT_MODEL"
                
                let (min, max) = node.boundingBox
                let cx = (min.x + max.x) / 2
                let cy = (min.y + max.y) / 2
                let cz = (min.z + max.z) / 2
                node.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)
                node.position = SCNVector3Zero
                
                node.geometry?.materials.forEach { mat in
                    if let original = mat.diffuse.contents {
                        mat.setValue(original, forKey: "originalDiffuse")
                    }
                }
                
                applyMaterial(to: node)
                root.addChildNode(node)
                DispatchQueue.main.async { view.defaultCameraController.target = SCNVector3Zero }
            }
        } else {
            if let node = root.childNode(withName: "PATIENT_MODEL", recursively: true) {
                applyMaterial(to: node)
            }
        }
    }
    
    // NEW: Function to sync imported models
    private func updateImportedModels(root: SCNNode) {
        for model in importedModels {
            let nodeName = "IMPORTED_\(model.id.uuidString)"
            
            // Check if exists
            if let node = root.childNode(withName: nodeName, recursively: true) {
                node.isHidden = !model.isVisible
                // Update transform logic here if we were binding it back from SwiftUI
                // For now, EditorView handles transform interactively
            } else {
                // Load new model
                let authorized = model.url.startAccessingSecurityScopedResource()
                defer { if authorized { model.url.stopAccessingSecurityScopedResource() } }
                
                if let scene = try? SCNScene(url: model.url, options: nil),
                   let geoNode = findFirstGeometryNode(in: scene.rootNode) {
                    
                    let node = geoNode.clone()
                    node.name = nodeName
                    
                    // Center pivot
                    let (min, max) = node.boundingBox
                    let cx = (min.x + max.x) / 2
                    let cy = (min.y + max.y) / 2
                    let cz = (min.z + max.z) / 2
                    node.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)
                    node.position = SCNVector3Zero
                    
                    // Distinct material color for imports to distinguish
                    node.geometry?.firstMaterial?.diffuse.contents = NSColor.yellow.withAlphaComponent(0.8)
                    
                    root.addChildNode(node)
                }
            }
        }
    }
    
    private func applyMaterial(to node: SCNNode) {
        node.geometry?.materials.forEach { mat in
            mat.isDoubleSided = true
            if useStoneMaterial {
                mat.lightingModel = .blinn
                mat.diffuse.contents = NSColor(calibratedRed: 0.85, green: 0.82, blue: 0.78, alpha: 1.0)
                mat.specular.contents = NSColor(white: 0.1, alpha: 1.0)
                mat.roughness.contents = 0.8
            } else {
                if let original = mat.value(forKey: "originalDiffuse") {
                    mat.diffuse.contents = original
                    mat.lightingModel = .physicallyBased
                } else {
                    mat.lightingModel = .blinn
                    if mat.diffuse.contents == nil { mat.diffuse.contents = NSColor.lightGray }
                }
            }
        }
    }
    
    private func findFirstGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes { if let found = findFirstGeometryNode(in: child) { return found } }
        return nil
    }
    
    private func updateSmileTemplate(root: SCNNode) {
        // ... (standard logic)
    }
    
    private func updateLandmarkVisuals(root: SCNNode) {
        // ... (standard logic from previous turns)
        let containerName = "LANDMARKS_CONTAINER"
        var container = root.childNode(withName: containerName, recursively: false)
        if container == nil { container = SCNNode(); container?.name = containerName; root.addChildNode(container!) }
        
        container?.childNodes.forEach { node in
            if let name = node.name, let type = LandmarkType(rawValue: name), landmarks[type] == nil { node.removeFromParentNode() }
        }
        for (type, position) in landmarks {
            let nodeName = type.rawValue
            if let existingNode = container?.childNode(withName: nodeName, recursively: false) {
                existingNode.position = position
            } else {
                let sphere = SCNSphere(radius: 0.002)
                let color = type.nsColor
                sphere.firstMaterial?.diffuse.contents = color
                let node = SCNNode(geometry: sphere)
                node.name = nodeName
                node.position = position
                container?.addChildNode(node)
            }
        }
    }
    
    private func drawEstheticAnalysis(root: SCNNode) { }
    
    private func updateGrid(root: SCNNode) {
        let gridName = "REFERENCE_GRID"
        root.childNode(withName: gridName, recursively: false)?.removeFromParentNode()
        if showGrid { let grid = SCNNode(); grid.name = gridName; root.addChildNode(grid) }
    }
    
    // NEW: Coordinator to handle Alignment Trigger
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: DesignSceneWrapper
        
        init(_ parent: DesignSceneWrapper) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(performAlignment), name: NSNotification.Name("PerformAlignment"), object: nil)
        }
        
        @objc func performAlignment() {
            // Find the active view (this is a bit hacky in SwiftUI representables, typically we use a closure)
            // But since we are inside the Coordinator, we can't easily access the `EditorView` unless we store it.
            // Let's rely on the fact that `EditorView` handles its own logic, or pass the view into the coordinator?
            // Actually, we can perform the alignment logic right here if we had the node.
            // Ideally, EditorView listens for this.
            
            // Correction: Send another notification that EditorView specifically listens to?
            // Or, easier: Let EditorView be the observer.
        }
    }
}
