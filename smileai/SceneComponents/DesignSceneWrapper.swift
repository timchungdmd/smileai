import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

// Struct for Alert Data
struct ReplaceAlertData: Identifiable {
    let id = UUID()
    let existingID: String
    let newURL: URL
    let newPos: SCNVector3
    let newRot: SCNVector4
}

struct DesignSceneWrapper: NSViewRepresentable {
    let scanURL: URL
    let mode: DesignMode
    
    var showSmileTemplate: Bool
    var smileParams: SmileTemplateParams
    var toothStates: [String: ToothState]
    var onToothSelected: ((String?) -> Void)?
    var onToothTransformChange: ((String, ToothState) -> Void)?
    
    var landmarks: [LandmarkType: SCNVector3]
    var activeLandmarkType: LandmarkType?
    var isPlacingLandmarks: Bool
    var onLandmarkPicked: ((SCNVector3) -> Void)?
    
    @Binding var triggerSnapshot: Bool
    var onSnapshotTaken: ((NSImage) -> Void)?
    
    var showGrid: Bool
    var onModelLoaded: ((_ bounds: (min: SCNVector3, max: SCNVector3)) -> Void)? = nil
    
    var toothLibrary: [String: URL] = [:]
    var libraryID: UUID = UUID()
    
    @Binding var isDrawingCurve: Bool
    var isCurveLocked: Bool
    @Binding var customCurvePoints: [SCNVector3]
    
    var useStoneMaterial: Bool
    
    // Drop Callbacks
    var onToothDrop: ((String, URL) -> Void)?
    @Binding var showReplaceAlert: Bool
    @Binding var replaceAlertData: ReplaceAlertData?
    
    func makeNSView(context: Context) -> EditorView {
        let view = EditorView()
        view.defaultCameraController.interactionMode = .orbitArcball
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true // Critical for Stone Mode
        view.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        view.scene = SCNScene()
        return view
    }
    
    func updateNSView(_ view: EditorView, context: Context) {
        view.currentMode = mode
        view.onToothSelected = { name in self.onToothSelected?(name) }
        view.onToothTransformChange = onToothTransformChange
        view.currentToothStates = toothStates
        view.activeLandmarkType = activeLandmarkType
        view.isPlacingLandmarks = isPlacingLandmarks
        view.onLandmarkPicked = onLandmarkPicked
        view.onToothDrop = onToothDrop
        
        // Pass Drawing State
        view.isDrawingCurve = isDrawingCurve
        view.curveEditor.isLocked = isCurveLocked
        
        // Sync Curve Logic
        view.curveEditor.onCurveChanged = { points in
            DispatchQueue.main.async {
                self.customCurvePoints = points
                if view.curveEditor.isClosed { self.isDrawingCurve = false }
            }
        }
        
        // Initialize curve if external data exists
        if view.curveEditor.points.count != customCurvePoints.count {
            view.curveEditor.setPoints(customCurvePoints)
        }
        
        view.updateSceneRef()
        
        // Handle Drop Collision (Connects to SwiftUI Alert)
        view.onDropCollision = { id, url, pos, rot in
            DispatchQueue.main.async {
                self.replaceAlertData = ReplaceAlertData(existingID: id, newURL: url, newPos: pos, newRot: rot)
                self.showReplaceAlert = true
            }
        }
        
        // Handle Add New
        view.onToothAdd = { url, pos, rot in
            // For now, treat as replace or implement specific Add logic
            // Since we don't have a "Create Node" function here exposed to binding,
            // we typically callback to parent to add to `toothLibrary` or `toothStates`
            print("Add new tooth at \(pos)")
        }
        
        if triggerSnapshot {
            DispatchQueue.main.async {
                let scale: CGFloat = 4.0
                let size = view.bounds.size
                let target = CGSize(width: size.width * scale, height: size.height * scale)
                let renderer = SCNRenderer(device: view.device, options: nil)
                renderer.scene = view.scene
                renderer.pointOfView = view.pointOfView
                renderer.autoenablesDefaultLighting = true
                let img = renderer.snapshot(atTime: 0, with: target, antialiasingMode: .multisampling4X)
                onSnapshotTaken?(img)
                triggerSnapshot = false
            }
        }
        
        guard let root = view.scene?.rootNode else { return }
        
        setupScene(root, view)
        
        if mode == .analysis, let last = landmarks.values.first {
             view.defaultCameraController.target = last
        }
        
        updateSmileTemplate(root: root)
        updateLandmarkVisuals(root: root)
        drawEstheticAnalysis(root: root)
        updateGrid(root: root)
    }
    
    private func setupScene(_ root: SCNNode, _ view: EditorView) {
        if root.childNode(withName: "CONTENT_CONTAINER", recursively: false) == nil {
            let c = SCNNode(); c.name = "CONTENT_CONTAINER"; root.addChildNode(c)
        }
        
        if root.childNode(withName: "PATIENT_MODEL", recursively: true) == nil {
            let authorized = scanURL.startAccessingSecurityScopedResource()
            defer { if authorized { scanURL.stopAccessingSecurityScopedResource() } }
            
            if let scene = try? SCNScene(url: scanURL, options: nil),
               let geoNode = findFirstGeometryNode(in: scene.rootNode) {
                
                let node = geoNode.clone()
                node.name = "PATIENT_MODEL"
                
                // NORMALIZE (Center & Scale)
                let (min, max) = node.boundingBox
                let cx = (min.x + max.x) / 2
                let cy = (min.y + max.y) / 2
                let cz = (min.z + max.z) / 2
                node.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)
                node.position = SCNVector3Zero
                
                let maxDim = Swift.max(max.x - min.x, Swift.max(max.y - min.y, max.z - min.z))
                if maxDim > 50 { node.scale = SCNVector3(0.001, 0.001, 0.001) } // Fix massive STL files
                
                // CACHE TEXTURE for Restore
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
            // Toggle Update
            if let node = root.childNode(withName: "PATIENT_MODEL", recursively: true) {
                applyMaterial(to: node)
            }
        }
    }
    
    private func applyMaterial(to node: SCNNode) {
        node.geometry?.materials.forEach { mat in
            mat.isDoubleSided = true
            
            if useStoneMaterial {
                // Stone Mode
                mat.lightingModel = .blinn
                mat.diffuse.contents = NSColor(calibratedRed: 0.85, green: 0.82, blue: 0.78, alpha: 1.0)
                mat.specular.contents = NSColor(white: 0.1, alpha: 1.0)
                mat.roughness.contents = 0.8
            } else {
                // Restore Original
                if let original = mat.value(forKey: "originalDiffuse") {
                    mat.diffuse.contents = original
                    mat.lightingModel = .physicallyBased
                } else {
                    // Fallback
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
    
    // ... [KEEP PREVIOUS HELPER METHODS HERE: updateSmileTemplate, fitTeethToCustomCurve, etc.]
    // (Omitted only to save space, assuming they exist from previous turns)
    private func updateSmileTemplate(root: SCNNode) {
        let name = "SMILE_TEMPLATE"; let nodeID = "\(name)|\(libraryID.uuidString)"; var templateNode = root.childNode(withName: nodeID, recursively: false)
        root.childNodes.forEach { if $0.name?.starts(with: name) == true && $0.name != nodeID { $0.removeFromParentNode() } }
        if showSmileTemplate {
            if templateNode == nil { templateNode = createProceduralArch(); templateNode?.name = nodeID; root.addChildNode(templateNode!) }
            applyProceduralTransforms(to: templateNode!)
        } else { templateNode?.removeFromParentNode() }
    }
    
    // Placeholder functions to ensure compilation - Replace with real logic
    private func createProceduralArch() -> SCNNode { let root = SCNNode(); return root }
    private func applyProceduralTransforms(to templateNode: SCNNode) {}
    private func drawEstheticAnalysis(root: SCNNode) {}
    private func updateLandmarkVisuals(root: SCNNode) {}
    private func updateGrid(root: SCNNode) {}
}
