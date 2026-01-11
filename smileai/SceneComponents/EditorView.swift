import SceneKit
import AppKit
import simd // Explicit import for vector math

class EditorView: SCNView {
    
    // MARK: - Properties
    var currentMode: DesignMode = .analysis
    var activeLandmarkType: LandmarkType?
    var isPlacingLandmarks: Bool = false
    
    var isModelLocked: Bool = false {
        didSet { updateCameraLock() }
    }
    
    // NEW: Alignment State
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
    
    // MARK: - API for Automation
    func project2DPointsTo3D(points: [CGPoint]) -> [SCNVector3] {
        guard let patientNode = self.scene?.rootNode.childNode(withName: "PATIENT_MODEL", recursively: true) else {
            return points.map { _ in SCNVector3Zero }
        }
        var results: [SCNVector3] = []
        let options: [SCNHitTestOption: Any] = [.searchMode: SCNHitTestSearchMode.closest.rawValue, .rootNode: patientNode, .ignoreHiddenNodes: true]
        for point in points {
            if let hit = self.hitTest(point, options: options).first {
                results.append(hit.worldCoordinates)
            } else {
                results.append(self.unprojectPoint(SCNVector3(point.x, point.y, 0.1)))
            }
        }
        return results
    }
    
    // MARK: - Mouse Events
    override func mouseDown(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        
        // Alignment Picking (High Priority)
        if isAlignmentMode {
            if let point = resolveSmartPoint(location: loc) {
                addDebugMarker(at: point, color: .green)
                onAlignmentPointPicked?(point)
            }
            return
        }
        
        let hitOptions: [SCNHitTestOption: Any] = [.searchMode: SCNHitTestSearchMode.closest.rawValue, .ignoreHiddenNodes: true]
        let hitResults = self.hitTest(loc, options: hitOptions)
        
        // Gizmo
        if let _ = hitResults.first(where: { $0.node.name == "GIZMO_ROTATE_HANDLE" }) {
            isRotatingTooth = true
            dragStartPosition = loc
            self.allowsCameraControl = false
            return
        }
        
        // Curve
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
        
        // Drawing
        if isDrawingCurve && !curveEditor.isLocked && !curveEditor.isClosed {
            if let point = resolveSmartPoint(location: loc) {
                curveEditor.handleClick(at: point)
            }
            return
        }
        
        // Selection/Analysis
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
        
        if let index = draggingCurveHandleIndex {
            if let point = resolveSmartPoint(location: loc) {
                curveEditor.updatePoint(index: index, position: point)
            }
            return
        }
        
        if isRotatingTooth, let tooth = selectedToothNode, let start = dragStartPosition {
            let dx = CGFloat(loc.x - start.x); let dy = CGFloat(loc.y - start.y)
            tooth.eulerAngles.y += dy * 0.01; tooth.eulerAngles.x += dx * 0.01
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
        updateCameraLock()
        super.mouseUp(with: event)
    }
    
    // MARK: - Drag Drop
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { return .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let result = ToothDropHandler.handleDrop(in: self, sender: sender, curvePoints: curveEditor.points) else { return false }
        switch result.target {
        case .existingTooth(let id): onToothDrop?(id, result.url)
        case .curvePoint(let pos, let rot):
            if let nearest = findNearestTooth(to: pos) { onDropCollision?(nearest, result.url, pos, rot) }
            else { onToothAdd?(result.url, pos, rot) }
        case .background: return false
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { node.removeFromParentNode() }
    }
    
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
        node.geometry?.materials.forEach { $0.emission.contents = highlighted ? NSColor.cyan : NSColor.black }
    }
    
    private func findNearestTooth(to pos: SCNVector3) -> String? {
        var nearestID: String?
        var minDst: Float = 0.005
        
        self.scene?.rootNode.enumerateChildNodes { node, _ in
            guard let name = node.name, name.starts(with: "T_") else { return }
            
            // FIX: Explicit cast to Float for SIMD compatibility
            // macOS uses CGFloat for SCNVector3, but SIMD requires Float
            let nPos = node.worldPosition
            let tPos = pos
            
            let simdA = SIMD3<Float>(Float(nPos.x), Float(nPos.y), Float(nPos.z))
            let simdB = SIMD3<Float>(Float(tPos.x), Float(tPos.y), Float(tPos.z))
            
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
        let options: [SCNHitTestOption: Any] = [.searchMode: SCNHitTestSearchMode.closest.rawValue, .rootNode: scene.rootNode, .ignoreHiddenNodes: true]
        if let hit = self.hitTest(location, options: options).first(where: { $0.node.name == "PATIENT_MODEL" }) {
            return hit.worldCoordinates
        }
        return projectToCameraFacingPlane(location: location)
    }
    
    private func projectToCameraFacingPlane(location: CGPoint) -> SCNVector3? {
        guard let _ = self.pointOfView else { return nil }
        var centerPos = SCNVector3Zero
        if let model = self.scene?.rootNode.childNode(withName: "PATIENT_MODEL", recursively: true) { centerPos = model.worldPosition }
        let near = self.unprojectPoint(SCNVector3(location.x, location.y, 0))
        let far = self.unprojectPoint(SCNVector3(location.x, location.y, 1))
        let dir = SCNVector3(far.x-near.x, far.y-near.y, far.z-near.z)
        if abs(dir.z) < 0.0001 { return nil }
        let t = (centerPos.z - near.z) / dir.z
        return SCNVector3(near.x + dir.x * t, near.y + dir.y * t, centerPos.z)
    }
}
