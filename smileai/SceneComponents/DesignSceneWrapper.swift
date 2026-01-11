import SwiftUI
import SceneKit

// MARK: - Enhanced DesignSceneWrapper with High-Resolution Snapshot
struct DesignSceneWrapper: NSViewRepresentable {
    // MARK: - Properties
    let scanURL: URL
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
    
    // ✨ ENHANCED: Snapshot with landmarks
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
        
        // 2. Pass Callbacks
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
        
        view.onToothAdd = { url, pos, rot in
            print("Add new tooth at \(pos)")
        }
        
        // 3. Sync Data
        view.currentToothStates = toothStates
        view.activeLandmarkType = activeLandmarkType
        view.isPlacingLandmarks = isPlacingLandmarks
        
        // 4. Curve Editing State
        view.isDrawingCurve = isDrawingCurve
        view.curveEditor.isLocked = isCurveLocked
        
        // 5. Update Curve Points
        view.curveEditor.onCurveChanged = { points in
            DispatchQueue.main.async {
                self.customCurvePoints = points
                if view.curveEditor.isClosed { self.isDrawingCurve = false }
            }
        }
        if view.curveEditor.points.count != customCurvePoints.count {
            view.curveEditor.setPoints(customCurvePoints)
        }
        
        // 6. Pass Lock State
        view.isModelLocked = isModelLocked
        
        // 7. Update Scene Logic
        view.updateSceneRef()
        
        guard let root = view.scene?.rootNode else { return }
        
        // ✨ 8. ENHANCED SNAPSHOT LOGIC
        if triggerSnapshot {
            DispatchQueue.main.async {
                print("📸 Capturing high-resolution snapshot with landmarks...")
                
                // Use EnhancedSnapshotService for full-resolution capture
                let config = EnhancedSnapshotService.SnapshotConfig(
                    resolution: .match,  // Match view size exactly
                    includeMarkers: true,
                    markerSize: 0.003,   // 3mm spheres
                    antialiasingMode: .multisampling4X,
                    backgroundColor: NSColor(white: 0.1, alpha: 1.0)
                )
                
                if let snapshot = EnhancedSnapshotService.captureSnapshot(
                    from: view,
                    landmarks: landmarks,
                    config: config
                ) {
                    print("✅ Snapshot captured: \(snapshot.size)")
                    onSnapshotTaken?(snapshot)
                } else {
                    print("❌ Snapshot capture failed")
                }
                
                triggerSnapshot = false
            }
        }
        
        // 9. Scene Composition
        setupScene(root, view)
        
        if mode == .analysis, let last = landmarks.values.first, view.defaultCameraController.target.length == 0 {
            view.defaultCameraController.target = last
        }
        
        // Update visuals
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
        
        if root.childNode(withName: "PATIENT_MODEL", recursively: true) == nil {
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
                
                let maxDim = Swift.max(max.x - min.x, Swift.max(max.y - min.y, max.z - min.z))
                if maxDim > 50 { node.scale = SCNVector3(0.001, 0.001, 0.001) }
                
                node.geometry?.materials.forEach { mat in
                    if let original = mat.diffuse.contents {
                        mat.setValue(original, forKey: "originalDiffuse")
                    }
                }
                
                applyMaterial(to: node)
                
                root.addChildNode(node)
                DispatchQueue.main.async {
                    view.defaultCameraController.target = SCNVector3Zero
                }
            }
        } else {
            if let node = root.childNode(withName: "PATIENT_MODEL", recursively: true) {
                applyMaterial(to: node)
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
                    if mat.diffuse.contents == nil {
                        mat.diffuse.contents = NSColor.lightGray
                    }
                }
            }
        }
    }
    
    private func findFirstGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = findFirstGeometryNode(in: child) { return found }
        }
        return nil
    }
    
    private func updateSmileTemplate(root: SCNNode) {
        let name = "SMILE_TEMPLATE"
        let nodeID = "\(name)|\(libraryID.uuidString)"
        var templateNode = root.childNode(withName: nodeID, recursively: false)
        
        root.childNodes.forEach {
            if $0.name?.starts(with: name) == true && $0.name != nodeID {
                $0.removeFromParentNode()
            }
        }
        
        if showSmileTemplate {
            if templateNode == nil {
                templateNode = SCNNode()
                templateNode?.name = nodeID
                root.addChildNode(templateNode!)
            }
        } else {
            templateNode?.removeFromParentNode()
        }
    }
    
    // ✨ ENHANCED: Landmark visualization (will be captured in snapshot)
    private func updateLandmarkVisuals(root: SCNNode) {
        let containerName = "LANDMARKS_CONTAINER"
        var container = root.childNode(withName: containerName, recursively: false)
        
        if container == nil {
            container = SCNNode()
            container?.name = containerName
            root.addChildNode(container!)
        }
        
        // Remove old landmarks
        container?.childNodes.forEach { node in
            if let name = node.name,
               let type = LandmarkType(rawValue: name),
               landmarks[type] == nil {
                node.removeFromParentNode()
            }
        }
        
        // Add/update landmarks
        for (type, position) in landmarks {
            let nodeName = type.rawValue
            if let existingNode = container?.childNode(withName: nodeName, recursively: false) {
                if simd_distance(SIMD3(existingNode.position), SIMD3(position)) > 0.0001 {
                    existingNode.position = position
                }
            } else {
                // Create landmark sphere with label
                let sphere = SCNSphere(radius: 0.002) // 2mm
                sphere.segmentCount = 16
                
                let color = type.nsColor
                sphere.firstMaterial?.diffuse.contents = color
                sphere.firstMaterial?.emission.contents = color.blended(withFraction: 0.5, of: .white)
                sphere.firstMaterial?.lightingModel = .constant // Always visible
                
                let node = SCNNode(geometry: sphere)
                node.name = nodeName
                node.position = position
                
                container?.addChildNode(node)
                
                // Add text label (optional - for detailed views)
                // Uncomment if you want text labels in 3D space
                /*
                let text = SCNText(string: type.rawValue.prefix(2).uppercased(), extrusionDepth: 0.0)
                text.font = NSFont.systemFont(ofSize: 0.002, weight: .bold)
                text.flatness = 0.1
                text.firstMaterial?.diffuse.contents = NSColor.white
                text.firstMaterial?.lightingModel = .constant
                
                let textNode = SCNNode(geometry: text)
                textNode.position = SCNVector3(
                    position.x,
                    position.y + 0.003,
                    position.z
                )
                
                // Billboard constraint so text always faces camera
                let billboard = SCNBillboardConstraint()
                billboard.freeAxes = [.Y]
                textNode.constraints = [billboard]
                
                container?.addChildNode(textNode)
                */
            }
        }
    }
    
    private func drawEstheticAnalysis(root: SCNNode) { }
    
    private func updateGrid(root: SCNNode) {
        let gridName = "REFERENCE_GRID"
        root.childNode(withName: gridName, recursively: false)?.removeFromParentNode()
        
        if showGrid {
            let grid = SCNNode()
            grid.name = gridName
            root.addChildNode(grid)
        }
    }
}
