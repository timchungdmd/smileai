import SceneKit
import AppKit
import simd

class EditorView: SCNView {
    
    // MARK: - Properties
    var currentMode: DesignMode = .analysis
    var activeLandmarkType: LandmarkType?
    var isPlacingLandmarks: Bool = false
    
    var isModelLocked: Bool = false {
        didSet { updateCameraLock() }
    }
    
    // Alignment State
    var isAlignmentMode: Bool = false
    var onAlignmentPointPicked: ((SCNVector3) -> Void)?
    
    // Callbacks
    var onLandmarkPicked: ((SCNVector3) -> Void)?
    var onToothSelected: ((String?) -> Void)?
    var onToothTransformChange: ((String, ToothState) -> Void)?
    var onToothDrop: ((String, URL) -> Void)?
    var onToothAdd: ((URL, SCNVector3, SCNVector4) -> Void)?
    var onDropCollision: ((String, URL, SCNVector3, SCNVector4) -> Void)?
    
    var currentToothStates: [String: ToothState] = [:]
    
    // Managers
    let curveEditor = SmileCurveEditor()
    var isDrawingCurve: Bool = false {
        didSet { DispatchQueue.main.async { self.window?.invalidateCursorRects(for: self) } }
    }
    
    // Internal State
    private var selectedToothNode: SCNNode?
    private var gizmo: SCNNode?
    private var isRotatingTooth: Bool = false
    private var dragStartPosition: CGPoint?
    private var draggingCurveHandleIndex: Int?
    
    // MARK: - Lifecycle
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSceneRef()
        
        // Listen for alignment trigger from SwiftUI
        NotificationCenter.default.addObserver(self, selector: #selector(executeAlignment), name: NSNotification.Name("PerformAlignment"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func updateSceneRef() {
        if let root = self.scene?.rootNode {
            curveEditor.setup(in: root)
        }
    }
    
    private func updateCameraLock() {
        if isModelLocked {
            self.allowsCameraControl = false
        } else {
            self.allowsCameraControl = (draggingCurveHandleIndex == nil && !isRotatingTooth)
        }
    }
    
    // MARK: - Alignment Logic
    
    @objc func executeAlignment() {
        // Determine which node to align:
        // 1. The currently selected node (Tooth or Imported Model)
        // 2. OR fall back to the main Patient Model
        let targetNode = selectedToothNode ?? self.scene?.rootNode.childNode(withName: "PATIENT_MODEL", recursively: true)
        
        if let node = targetNode {
            // Post notification back to DesignSceneWrapper's Coordinator
            // passing the specific Node and this View (for projection math)
            NotificationCenter.default.post(
                name: NSNotification.Name("AlignNode"),
                object: node,
                userInfo: ["view": self]
            )
        }
    }
    
    // API for Automation/Alignment Manager to project points
    func project2DPointsTo3D(points: [CGPoint]) -> [SCNVector3] {
        var results: [SCNVector3] = []
        let options: [SCNHitTestOption: Any] = [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .ignoreHiddenNodes: true
        ]
        
        for point in points {
            // Hit test against Patient Model AND Imported Models
            let hit = self.hitTest(point, options: options).first { result in
                let name = result.node.name ?? ""
                return name == "PATIENT_MODEL" || name.starts(with: "IMPORTED_")
            }
            
            if let hit = hit {
                results.append(hit.worldCoordinates)
            } else {
                // Fallback: unproject at fixed depth
                results.append(self.unprojectPoint(SCNVector3(point.x, point.y, 0.1)))
            }
        }
        return results
    }
    
    // MARK: - Interaction / Gestures
    
    override func mouseDown(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        
        // 1. Alignment Picking (Highest Priority)
        if isAlignmentMode {
            if let point = resolveSmartPoint(location: loc) {
                addDebugMarker(at: point, color: .green)
                onAlignmentPointPicked?(point)
            }
            return
        }
        
        let hitOptions: [SCNHitTestOption: Any] = [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .ignoreHiddenNodes: true
        ]
        let hitResults = self.hitTest(loc, options: hitOptions)
        
        // 2. Gizmo Interaction
        if let _ = hitResults.first(where: { $0.node.name == "GIZMO_ROTATE_HANDLE" }) {
            isRotatingTooth = true
            dragStartPosition = loc
            self.allowsCameraControl = false
            return
        }
        
        // 3. Curve Editing
        if !curveEditor.isLocked {
            let curveHits = self.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            if let hit = curveHits.first(where: { $0.node.name?.starts(with: "CURVE_HANDLE_") == true }),
               let index = curveEditor.getPointIndex(for: hit.node) {
                if isDrawingCurve && index == 0 && curveEditor.points.count > 2 {
                    curveEditor.closeLoop()
                    return
                }
                draggingCurveHandleIndex = index
                dragStartPosition = loc
                self.allowsCameraControl = false
                return
            }
        }
        
        // 4. Drawing Curve
        if isDrawingCurve && !curveEditor.isLocked && !curveEditor.isClosed {
            if let point = resolveSmartPoint(location: loc) {
                curveEditor.handleClick(at: point)
            }
            return
        }
        
        // 5. Selection / Analysis
        switch currentMode {
        case .analysis:
            if isPlacingLandmarks, let point = resolveSmartPoint(location: loc) {
                onLandmarkPicked?(point)
            } else {
                super.mouseDown(with: event)
            }
            
        case .design:
            // Check for Tooth ("T_") OR Imported Model ("IMPORTED_")
            if let hit = hitResults.first(where: {
                ($0.node.name?.starts(with: "T_") ?? false) ||
                ($0.node.name?.starts(with: "IMPORTED_") ?? false)
            }) {
                selectTooth(hit.node)
            } else {
                deselectTooth()
                super.mouseDown(with: event)
            }
        }
        
        dragStartPosition = loc
    }
    
    override func mouseDragged(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        
        // Curve Point Dragging
        if let index = draggingCurveHandleIndex {
            if let point = resolveSmartPoint(location: loc) {
                curveEditor.updatePoint(index: index, position: point)
            }
            return
        }
        
        // Gizmo Rotation
        if isRotatingTooth, let tooth = selectedToothNode, let start = dragStartPosition {
            let dx = CGFloat(loc.x - start.x)
            let dy = CGFloat(loc.y - start.y)
            
            // Adjust rotation based on drag
            tooth.eulerAngles.y += dy * 0.01
            tooth.eulerAngles.x += dx * 0.01
            
            // Update Gizmo
            self.gizmo?.position = tooth.worldPosition
            
            // Notify changes (only for teeth logic)
            if let name = tooth.name, name.starts(with: "T_") {
                let state = currentToothStates[name] ?? ToothState()
                onToothTransformChange?(name, state)
            }
            
            dragStartPosition = loc
            return
        }
        
        // Standard Camera Control
        if !isRotatingTooth && draggingCurveHandleIndex == nil {
            super.mouseDragged(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        draggingCurveHandleIndex = nil
        isRotatingTooth = false
        dragStartPosition = nil
        updateCameraLock()
        super.mouseUp(with: event)
    }
    
    // MARK: - Resizing Gesture
    
    override func magnify(with event: NSEvent) {
        // Only allow resizing of Imported Models
        if let node = selectedToothNode, (node.name?.starts(with: "IMPORTED_") ?? false) {
            let scaleFactor = 1.0 + event.magnification
            let current = node.scale
            node.scale = SCNVector3(
                current.x * CGFloat(scaleFactor),
                current.y * CGFloat(scaleFactor),
                current.z * CGFloat(scaleFactor)
            )
        } else {
            // Otherwise, pass to super (zooms camera)
            super.magnify(with: event)
        }
    }
    
    // MARK: - Drag Drop
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let result = ToothDropHandler.handleDrop(in: self, sender: sender, curvePoints: curveEditor.points) else { return false }
        
        switch result.target {
        case .existingTooth(let id):
            onToothDrop?(id, result.url)
        case .curvePoint(let pos, let rot):
            if let nearest = findNearestTooth(to: pos) {
                onDropCollision?(nearest, result.url, pos, rot)
            } else {
                onToothAdd?(result.url, pos, rot)
            }
        case .background:
            return false
        }
        return true
    }
    
    // MARK: - Helpers
    
    private func addDebugMarker(at pos: SCNVector3, color: NSColor) {
        let sphere = SCNSphere(radius: 0.0015)
        sphere.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: sphere)
        node.position = pos
        self.scene?.rootNode.addChildNode(node)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            node.removeFromParentNode()
        }
    }
    
    private func selectTooth(_ node: SCNNode) {
        selectedToothNode = node
        onToothSelected?(node.name)
        
        // Remove old gizmo
        self.scene?.rootNode.childNode(withName: "MANIPULATION_GIZMO", recursively: true)?.removeFromParentNode()
        
        // Add new gizmo
        let (min, max) = node.boundingBox
        let newGizmo = FreeRotateGizmo(boundMin: min, boundMax: max)
        newGizmo.position = node.worldPosition
        self.scene?.rootNode.addChildNode(newGizmo)
        self.gizmo = newGizmo
        
        highlightTooth(node, highlighted: true)
    }
    
    private func deselectTooth() {
        if let tooth = selectedToothNode {
            highlightTooth(tooth, highlighted: false)
        }
        selectedToothNode = nil
        self.scene?.rootNode.childNode(withName: "MANIPULATION_GIZMO", recursively: true)?.removeFromParentNode()
        self.gizmo = nil
        onToothSelected?(nil)
    }
    
    private func highlightTooth(_ node: SCNNode, highlighted: Bool) {
        // Visual feedback
        if node.name?.starts(with: "T_") == true {
            // Teeth glow cyan
            node.geometry?.materials.forEach {
                $0.emission.contents = highlighted ? NSColor.cyan : NSColor.black
            }
        } else if node.name?.starts(with: "IMPORTED_") == true {
            // Imported models glow white/grey
            node.geometry?.materials.forEach {
                $0.emission.contents = highlighted ? NSColor(white: 0.3, alpha: 1.0) : NSColor.black
            }
        }
    }
    
    private func findNearestTooth(to pos: SCNVector3) -> String? {
        var nearestID: String?
        var minDst: Float = 0.005
        
        self.scene?.rootNode.enumerateChildNodes { node, _ in
            guard let name = node.name, name.starts(with: "T_") else { return }
            
            let nPos = node.worldPosition
            // SIMD conversion for distance calc
            let simdA = SIMD3<Float>(Float(nPos.x), Float(nPos.y), Float(nPos.z))
            let simdB = SIMD3<Float>(Float(pos.x), Float(pos.y), Float(pos.z))
            
            let dist = simd_distance(simdA, simdB)
            
            if dist < minDst {
                minDst = dist
                nearestID = name
            }
        }
        return nearestID
    }
    
    private func resolveSmartPoint(location: CGPoint) -> SCNVector3? {
        guard let scene = self.scene else { return nil }
        
        let options: [SCNHitTestOption: Any] = [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .rootNode: scene.rootNode,
            .ignoreHiddenNodes: true
        ]
        
        // Hit test against Patient Model OR Imported Models
        let hit = self.hitTest(location, options: options).first { result in
            let name = result.node.name ?? ""
            return name == "PATIENT_MODEL" || name.starts(with: "IMPORTED_")
        }
        
        if let hit = hit {
            return hit.worldCoordinates
        }
        
        // Fallback: Project onto plane
        return projectToCameraFacingPlane(location: location)
    }
    
    private func projectToCameraFacingPlane(location: CGPoint) -> SCNVector3? {
        guard let _ = self.pointOfView else { return nil }
        
        // Default depth: approximate center of patient model
        var centerPos = SCNVector3Zero
        if let model = self.scene?.rootNode.childNode(withName: "PATIENT_MODEL", recursively: true) {
            centerPos = model.worldPosition
        }
        
        let near = self.unprojectPoint(SCNVector3(location.x, location.y, 0))
        let far = self.unprojectPoint(SCNVector3(location.x, location.y, 1))
        
        let dir = SCNVector3(far.x - near.x, far.y - near.y, far.z - near.z)
        
        if abs(dir.z) < 0.0001 { return nil } // Avoid divide by zero if parallel
        
        let t = (centerPos.z - near.z) / dir.z
        return SCNVector3(near.x + dir.x * t, near.y + dir.y * t, centerPos.z)
    }
}
