import SceneKit
import AppKit

class EditorView: SCNView {
    // MARK: - Properties
    var currentMode: DesignMode = .analysis
    var activeLandmarkType: LandmarkType?
    var isPlacingLandmarks: Bool = false
    
    // Callbacks
    var onLandmarkPicked: ((SCNVector3) -> Void)?
    var onToothSelected: ((String?) -> Void)?
    var onToothTransformChange: ((String, ToothState) -> Void)?
    
    // Drop Callbacks
    var onToothDrop: ((String, URL) -> Void)? // Direct replacement
    var onToothAdd: ((URL, SCNVector3, SCNVector4) -> Void)? // Add new
    var onDropCollision: ((String, URL, SCNVector3, SCNVector4) -> Void)? // Collision detected
    
    var currentToothStates: [String: ToothState] = [:]
    
    // Managers
    let curveEditor = SmileCurveEditor()
    
    var isDrawingCurve: Bool = false {
        didSet { DispatchQueue.main.async { self.window?.invalidateCursorRects(for: self) } }
    }
    
    // Internal State
    private var selectedToothNode: SCNNode?
    private var gizmo: SCNNode? // Now generic to support FreeRotateGizmo
    private var isRotatingTooth: Bool = false
    private var dragStartPosition: CGPoint?
    private var draggingCurveHandleIndex: Int?
    
    // MARK: - Lifecycle
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSceneRef()
    }
    
    func updateSceneRef() {
        if let root = self.scene?.rootNode {
            curveEditor.setup(in: root)
        }
    }
    
    // MARK: - Cursor Management
    override func resetCursorRects() {
        super.resetCursorRects()
        self.discardCursorRects()
        
        if isDrawingCurve && !curveEditor.isLocked {
            self.addCursorRect(self.bounds, cursor: .crosshair)
        } else if !curveEditor.isLocked && !curveEditor.points.isEmpty {
            self.addCursorRect(self.bounds, cursor: .pointingHand)
        } else {
            self.addCursorRect(self.bounds, cursor: .arrow)
        }
    }
    
    // MARK: - Mouse Events
    override func mouseDown(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        let hitOptions: [SCNHitTestOption: Any] = [.searchMode: SCNHitTestSearchMode.closest.rawValue, .ignoreHiddenNodes: true]
        let hitResults = self.hitTest(loc, options: hitOptions)
        
        // 1. GIZMO ROTATION (Highest Priority)
        // Check if we hit the transparent sphere of the FreeRotateGizmo
        if let hit = hitResults.first(where: { $0.node.name == "GIZMO_ROTATE_HANDLE" }) {
            isRotatingTooth = true
            dragStartPosition = loc
            self.allowsCameraControl = false
            return
        }
        
        // 2. CURVE MANIPULATION
        if !curveEditor.isLocked {
            // Use .all to find handles buried inside teeth
            let curveHits = self.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            if let hit = curveHits.first(where: { $0.node.name?.starts(with: "CURVE_HANDLE_") == true }),
               let index = curveEditor.getPointIndex(for: hit.node) {
                
                // Close Loop Logic
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
        
        // 3. DRAW NEW CURVE POINT
        if isDrawingCurve && !curveEditor.isLocked && !curveEditor.isClosed {
            if let point = resolveSmartPoint(location: loc) {
                curveEditor.handleClick(at: point)
            }
            return
        }
        
        // 4. STANDARD SELECTION / ANALYSIS
        switch currentMode {
        case .analysis:
            if isPlacingLandmarks, let point = resolveSmartPoint(location: loc) {
                onLandmarkPicked?(point)
            } else {
                super.mouseDown(with: event)
            }
            
        case .design:
            // Select Tooth
            if let hit = hitResults.first(where: { $0.node.name?.starts(with: "T_") == true }) {
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
        
        // A. Drag Curve Point
        if let index = draggingCurveHandleIndex {
            if let point = resolveSmartPoint(location: loc) {
                curveEditor.updatePoint(index: index, position: point)
            }
            return
        }
        
        // B. Free Rotate Tooth (Tumble)
        if isRotatingTooth, let tooth = selectedToothNode, let start = dragStartPosition {
            let dx = CGFloat(loc.x - start.x)
            let dy = CGFloat(loc.y - start.y)
            
            let sensitivity: CGFloat = 0.01
            
            // Apply rotation (Euler is simplest for basic tumbling)
            tooth.eulerAngles.y += dy * sensitivity
            tooth.eulerAngles.x += dx * sensitivity
            
            // Sync Gizmo Position
            self.gizmo?.position = tooth.worldPosition
            
            // Notify State Change
            let state = currentToothStates[tooth.name!] ?? ToothState()
            // Note: In a real app, you'd calculate the new rotation back into the ToothState struct
            onToothTransformChange?(tooth.name!, state)
            
            dragStartPosition = loc
            return
        }
        
        if !isRotatingTooth && draggingCurveHandleIndex == nil {
            super.mouseDragged(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        draggingCurveHandleIndex = nil
        isRotatingTooth = false
        dragStartPosition = nil
        self.allowsCameraControl = true
        super.mouseUp(with: event)
    }
    
    // MARK: - Drag & Drop Logic
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { return .copy }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // Use the dedicated ToothDropHandler (ensure this file exists in your project)
        guard let result = ToothDropHandler.handleDrop(in: self, sender: sender, curvePoints: curveEditor.points) else {
            return false
        }
        
        switch result.target {
        case .existingTooth(let id):
            onToothDrop?(id, result.url) // Replace
            
        case .curvePoint(let pos, let rot):
            // Check collisions
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
    
    private func selectTooth(_ node: SCNNode) {
        selectedToothNode = node
        onToothSelected?(node.name)
        
        // Remove old gizmo
        self.scene?.rootNode.childNode(withName: "MANIPULATION_GIZMO", recursively: true)?.removeFromParentNode()
        
        // Add Free Rotation Gizmo
        let (min, max) = node.boundingBox
        let newGizmo = FreeRotateGizmo(boundMin: min, boundMax: max)
        newGizmo.position = node.worldPosition
        
        self.scene?.rootNode.addChildNode(newGizmo)
        self.gizmo = newGizmo
        
        highlightTooth(node, highlighted: true)
    }
    
    private func deselectTooth() {
        if let tooth = selectedToothNode { highlightTooth(tooth, highlighted: false) }
        selectedToothNode = nil
        self.scene?.rootNode.childNode(withName: "MANIPULATION_GIZMO", recursively: true)?.removeFromParentNode()
        self.gizmo = nil
        onToothSelected?(nil)
    }
    
    private func highlightTooth(_ node: SCNNode, highlighted: Bool) {
        let c = highlighted ? NSColor.cyan : NSColor.black
        node.geometry?.materials.forEach { $0.emission.contents = c }
    }
    
    private func findNearestTooth(to pos: SCNVector3) -> String? {
        var nearestID: String?
        var minDst: Float = 0.005 // 5mm threshold
        
        self.scene?.rootNode.enumerateChildNodes { node, _ in
            if let name = node.name, name.starts(with: "T_") {
                let d = sqrt(pow(node.worldPosition.x - pos.x, 2) + pow(node.worldPosition.y - pos.y, 2) + pow(node.worldPosition.z - pos.z, 2))
                if d < minDst {
                    minDst = d
                    nearestID = name
                }
            }
        }
        return nearestID
    }
    
    // Smart Raycasting
    private func resolveSmartPoint(location: CGPoint) -> SCNVector3? {
        guard let scene = self.scene else { return nil }
        
        // 1. Try Mesh Hit
        let options: [SCNHitTestOption: Any] = [.searchMode: SCNHitTestSearchMode.closest.rawValue, .rootNode: scene.rootNode, .ignoreHiddenNodes: true]
        let hits = self.hitTest(location, options: options)
        if let hit = hits.first(where: { $0.node.name == "PATIENT_MODEL" }) {
            let offset: CGFloat = 0.0005
            return SCNVector3(hit.worldCoordinates.x + hit.worldNormal.x * offset, hit.worldCoordinates.y + hit.worldNormal.y * offset, hit.worldCoordinates.z + hit.worldNormal.z * offset)
        }
        // 2. Fallback Plane
        return projectToCameraFacingPlane(location: location)
    }
    
    private func projectToCameraFacingPlane(location: CGPoint) -> SCNVector3? {
        guard let _ = self.pointOfView else { return nil }
        var centerPos = SCNVector3Zero
        if let model = self.scene?.rootNode.childNode(withName: "PATIENT_MODEL", recursively: true) { centerPos = model.worldPosition }
        
        let near = self.unprojectPoint(SCNVector3(location.x, location.y, 0))
        let far = self.unprojectPoint(SCNVector3(location.x, location.y, 1))
        let dir = SCNVector3(far.x - near.x, far.y - near.y, far.z - near.z)
        
        // Plane Z usually works best for "Frontal" editing, but camera-facing is better for free rotation
        // Simplified to Z-plane at model depth for stability in this context
        let planeZ = centerPos.z
        if abs(dir.z) < 0.0001 { return nil }
        let t = (planeZ - near.z) / dir.z
        return SCNVector3(near.x + dir.x * t, near.y + dir.y * t, planeZ)
    }
}
