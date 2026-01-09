import SceneKit
import AppKit

class EditorView: SCNView {
    
    // MARK: - Properties
    var currentMode: DesignMode = .analysis
    var activeLandmarkType: LandmarkType?
    var isPlacingLandmarks: Bool = false
    
    // NEW: Lock State
    var isModelLocked: Bool = false {
        didSet {
            // Immediate update when property changes
            updateCameraLock()
        }
    }
    
    // Callbacks
    var onLandmarkPicked: ((SCNVector3) -> Void)?
    var onToothSelected: ((String?) -> Void)?
    var onToothTransformChange: ((String, ToothState) -> Void)?
    
    // Drop Callbacks
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
    }
    
    func updateSceneRef() {
        if let root = self.scene?.rootNode {
            curveEditor.setup(in: root)
        }
    }
    
    // Helper to consolidate lock logic
    private func updateCameraLock() {
        if isModelLocked {
            self.allowsCameraControl = false
        } else {
            // Only enable if we aren't currently dragging something else
            self.allowsCameraControl = (draggingCurveHandleIndex == nil && !isRotatingTooth)
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
        if let _ = hitResults.first(where: { $0.node.name == "GIZMO_ROTATE_HANDLE" }) {
            isRotatingTooth = true
            dragStartPosition = loc
            self.allowsCameraControl = false // Always disable during drag
            return
        }
        
        // 2. CURVE MANIPULATION
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
                self.allowsCameraControl = false // Always disable during drag
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
        
        // B. Free Rotate Tooth
        if isRotatingTooth, let tooth = selectedToothNode, let start = dragStartPosition {
            let dx = CGFloat(loc.x - start.x)
            let dy = CGFloat(loc.y - start.y)
            
            let sensitivity: CGFloat = 0.01
            
            tooth.eulerAngles.y += dy * sensitivity
            tooth.eulerAngles.x += dx * sensitivity
            
            self.gizmo?.position = tooth.worldPosition
            
            let state = currentToothStates[tooth.name!] ?? ToothState()
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
        
        // CRITICAL FIX: Respect the lock state when releasing mouse
        updateCameraLock()
        
        super.mouseUp(with: event)
    }
    
    // MARK: - Drag & Drop Logic
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { return .copy }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let result = ToothDropHandler.handleDrop(in: self, sender: sender, curvePoints: curveEditor.points) else {
            return false
        }
        
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
    private func selectTooth(_ node: SCNNode) {
        selectedToothNode = node
        onToothSelected?(node.name)
        self.scene?.rootNode.childNode(withName: "MANIPULATION_GIZMO", recursively: true)?.removeFromParentNode()
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
        var minDst: Float = 0.005
        self.scene?.rootNode.enumerateChildNodes { node, _ in
            guard let name = node.name, name.starts(with: "T_") else { return }
            let dx = Float(node.worldPosition.x - pos.x)
            let dy = Float(node.worldPosition.y - pos.y)
            let dz = Float(node.worldPosition.z - pos.z)
            let d = sqrt(dx*dx + dy*dy + dz*dz)
            if d < minDst {
                minDst = d
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
        let hits = self.hitTest(location, options: options)
        if let hit = hits.first(where: { $0.node.name == "PATIENT_MODEL" }) {
            let offset: CGFloat = 0.0005
            let nx = hit.worldNormal.x * offset
            let ny = hit.worldNormal.y * offset
            let nz = hit.worldNormal.z * offset
            let finalX = hit.worldCoordinates.x + nx
            let finalY = hit.worldCoordinates.y + ny
            let finalZ = hit.worldCoordinates.z + nz
            return SCNVector3(finalX, finalY, finalZ)
        }
        return projectToCameraFacingPlane(location: location)
    }
    
    private func projectToCameraFacingPlane(location: CGPoint) -> SCNVector3? {
        guard let _ = self.pointOfView else { return nil }
        var centerPos = SCNVector3Zero
        if let model = self.scene?.rootNode.childNode(withName: "PATIENT_MODEL", recursively: true) {
            centerPos = model.worldPosition
        }
        let near = self.unprojectPoint(SCNVector3(location.x, location.y, 0))
        let far = self.unprojectPoint(SCNVector3(location.x, location.y, 1))
        let dir = SCNVector3(far.x - near.x, far.y - near.y, far.z - near.z)
        let planeZ = centerPos.z
        if abs(dir.z) < 0.0001 { return nil }
        let t = (planeZ - near.z) / dir.z
        return SCNVector3(near.x + dir.x * t, near.y + dir.y * t, planeZ)
    }
}
