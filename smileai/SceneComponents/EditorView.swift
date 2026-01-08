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
    
    // State
    var currentToothStates: [String: ToothState] = [:]
    
    // Drawing Curve Support
    var isDrawingCurve: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.window?.invalidateCursorRects(for: self)
            }
        }
    }
    
    var isCurveLocked: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.window?.invalidateCursorRects(for: self)
            }
        }
    }
    
    var onCurveUpdated: (([SCNVector3]) -> Void)?
    var onCurveClosed: (() -> Void)?
    
    // Internal Curve Data
    private var localCurvePoints: [SCNVector3] = []
    private var curveHandles: [SCNNode] = []
    private var selectedCurveHandle: SCNNode?
    
    // Selection / Manipulation
    private var selectedToothNode: SCNNode?
    private var gizmo: GizmoNode?
    private var isDraggingGizmo: Bool = false
    private var dragStartPosition: CGPoint?
    private var dragStartToothState: ToothState?
    
    // MARK: - API
    
    func setCurvePoints(_ points: [SCNVector3]) {
        if points.count != localCurvePoints.count {
            localCurvePoints = points
            rebuildCurveVisuals()
            // Invalidate cursor so logic knows points exist (for pointingHand)
            DispatchQueue.main.async {
                self.window?.invalidateCursorRects(for: self)
            }
        }
    }
    
    // MARK: - Cursor Management (Fixed)
    
    override func resetCursorRects() {
        super.resetCursorRects()
        
        // Discard any existing tracking areas to ensure fresh logic
        self.discardCursorRects()
        
        if isDrawingCurve && !isCurveLocked {
            self.addCursorRect(self.bounds, cursor: .crosshair)
        } else if !isCurveLocked && !localCurvePoints.isEmpty {
            self.addCursorRect(self.bounds, cursor: .pointingHand)
        } else {
            self.addCursorRect(self.bounds, cursor: .arrow)
        }
    }
    
    // MARK: - Input Events
    
    override func mouseDown(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        
        // 1. EDIT MODE PRIORITY (Check if we clicked an existing dot first)
        if !isCurveLocked && !localCurvePoints.isEmpty {
            let hitResults = self.hitTest(loc, options: nil)
            
            if let hit = hitResults.first(where: { $0.node.name?.starts(with: "HANDLE_") == true }) {
                
                // CHECK FOR LOOP CLOSURE (Clicking the first point)
                if isDrawingCurve, let name = hit.node.name, name == "HANDLE_0", localCurvePoints.count > 2 {
                    onCurveClosed?() // Notify wrapper to stop drawing
                    return
                }
                
                // Start Dragging Handle
                selectedCurveHandle = hit.node
                dragStartPosition = loc
                self.allowsCameraControl = false
                return
            }
        }
        
        // 2. DRAW MODE (Add new point)
        if isDrawingCurve && !isCurveLocked {
            if let point = resolveSmartPoint(location: loc) {
                localCurvePoints.append(point)
                addCurveHandle(at: point, index: localCurvePoints.count - 1)
                updateCurveGeometry()
                onCurveUpdated?(localCurvePoints)
                
                // Update cursor logic (e.g. switching to hand if we stop drawing)
                self.window?.invalidateCursorRects(for: self)
            }
            return
        }
        
        // 3. STANDARD MODES (Landmarks/Teeth)
        switch currentMode {
        case .analysis:
            if isPlacingLandmarks && activeLandmarkType != nil {
                if let point = resolveSmartPoint(location: loc) {
                    onLandmarkPicked?(point)
                }
            } else {
                super.mouseDown(with: event)
            }
            
        case .design:
            if let gizmo = gizmo, let axis = checkGizmoHit(at: loc) {
                isDraggingGizmo = true
                dragStartPosition = loc
                if let name = selectedToothNode?.name {
                    dragStartToothState = currentToothStates[name]
                }
                gizmo.activeAxis = axis
                gizmo.highlightAxis(axis)
                self.allowsCameraControl = false
                return
            }
            
            let results = self.hitTest(loc, options: nil)
            if let hit = results.first(where: { $0.node.name?.starts(with: "T_") == true }) {
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
        
        // 1. DRAG CURVE HANDLE
        if let handle = selectedCurveHandle {
            if let newPoint = resolveSmartPoint(location: loc) {
                handle.position = newPoint
                
                if let name = handle.name,
                   let indexStr = name.split(separator: "_").last,
                   let index = Int(indexStr),
                   index < localCurvePoints.count {
                    localCurvePoints[index] = newPoint
                    updateCurveGeometry()
                    onCurveUpdated?(localCurvePoints)
                }
            }
            return
        }
        
        // 2. DRAG TOOTH (Gizmo)
        if currentMode == .design && isDraggingGizmo,
           let tooth = selectedToothNode,
           let name = tooth.name,
           let startPos = dragStartPosition,
           let axis = gizmo?.activeAxis {
            
            let deltaX = CGFloat(loc.x - startPos.x)
            let deltaY = CGFloat(loc.y - startPos.y)
            
            var state = dragStartToothState ?? currentToothStates[name] ?? ToothState()
            
            let sensitivity: Float = 0.0001
            switch axis {
            case .x: state.positionOffset.x += Float(deltaX) * sensitivity
            case .y: state.positionOffset.y -= Float(deltaY) * sensitivity
            case .z: state.positionOffset.z += Float(deltaY) * sensitivity
            case .none: break
            }
            
            onToothTransformChange?(name, state)
        } else if !isDraggingGizmo {
            super.mouseDragged(with: event)
        }
        
        dragStartPosition = loc
    }
    
    override func mouseUp(with event: NSEvent) {
        selectedCurveHandle = nil
        isDraggingGizmo = false
        dragStartPosition = nil
        dragStartToothState = nil
        gizmo?.activeAxis = .none
        gizmo?.highlightAxis(.none)
        self.allowsCameraControl = true
        super.mouseUp(with: event)
    }
    
    override func scrollWheel(with event: NSEvent) {
        if currentMode == .design && event.modifierFlags.contains(.option),
           let tooth = selectedToothNode,
           let name = tooth.name {
            var state = currentToothStates[name] ?? ToothState()
            let rotationDelta = Float(event.scrollingDeltaY) * 0.01
            state.rotation.y += rotationDelta
            onToothTransformChange?(name, state)
        } else {
            super.scrollWheel(with: event)
        }
    }
    
    // MARK: - VISUALS
    
    private func rebuildCurveVisuals() {
        self.scene?.rootNode.enumerateChildNodes { (node, _) in
            if node.name?.starts(with: "HANDLE_") == true || node.name == "CUSTOM_CURVE_LINE" {
                node.removeFromParentNode()
            }
        }
        curveHandles.removeAll()
        for (i, p) in localCurvePoints.enumerated() {
            addCurveHandle(at: p, index: i)
        }
        updateCurveGeometry()
    }
    
    private func addCurveHandle(at pos: SCNVector3, index: Int) {
        let sphere = SCNSphere(radius: 0.0015)
        let color: NSColor = isCurveLocked ? .gray : .orange
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.emission.contents = color
        sphere.firstMaterial?.readsFromDepthBuffer = false
        
        let node = SCNNode(geometry: sphere)
        node.position = pos
        node.name = "HANDLE_\(index)"
        node.renderingOrder = 6000
        
        self.scene?.rootNode.addChildNode(node)
        curveHandles.append(node)
    }
    
    private func updateCurveGeometry() {
        let name = "CUSTOM_CURVE_LINE"
        self.scene?.rootNode.childNode(withName: name, recursively: false)?.removeFromParentNode()
        
        guard localCurvePoints.count > 1 else { return }
        
        var indices: [Int32] = []
        for i in 0..<localCurvePoints.count-1 {
            indices.append(Int32(i))
            indices.append(Int32(i+1))
        }
        
        let source = SCNGeometrySource(vertices: localCurvePoints)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geo = SCNGeometry(sources: [source], elements: [element])
        geo.firstMaterial?.diffuse.contents = NSColor.yellow
        geo.firstMaterial?.emission.contents = NSColor.yellow
        geo.firstMaterial?.readsFromDepthBuffer = false
        
        let node = SCNNode(geometry: geo)
        node.name = name
        node.renderingOrder = 5999
        self.scene?.rootNode.addChildNode(node)
    }
    
    // MARK: - MATH & RAYCASTING
    
    private func resolveSmartPoint(location: CGPoint) -> SCNVector3? {
        guard let scene = self.scene else { return nil }
        
        let options: [SCNHitTestOption: Any] = [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .rootNode: scene.rootNode,
            .ignoreHiddenNodes: true
        ]
        
        let hits = self.hitTest(location, options: options)
        
        if let hit = hits.first(where: { isModelNode($0.node) }) {
            let offset: CGFloat = 0.0005
            return SCNVector3(
                hit.worldCoordinates.x + hit.worldNormal.x * offset,
                hit.worldCoordinates.y + hit.worldNormal.y * offset,
                hit.worldCoordinates.z + hit.worldNormal.z * offset
            )
        }
        
        return projectToCameraFacingPlane(location: location)
    }
    
    private func isModelNode(_ node: SCNNode) -> Bool {
        if node.name == "PATIENT_MODEL" { return true }
        if let parent = node.parent { return isModelNode(parent) }
        return false
    }
    
    private func projectToCameraFacingPlane(location: CGPoint) -> SCNVector3? {
        guard let _ = self.pointOfView else { return nil } // Ensure camera exists
        
        // Use approximate center of model for depth
        var centerPos = SCNVector3Zero
        if let model = self.scene?.rootNode.childNode(withName: "PATIENT_MODEL", recursively: true) {
            centerPos = model.worldPosition
        }
        
        let near = self.unprojectPoint(SCNVector3(location.x, location.y, 0))
        let far = self.unprojectPoint(SCNVector3(location.x, location.y, 1))
        
        let dir = SCNVector3(far.x - near.x, far.y - near.y, far.z - near.z)
        
        // Simplified: Project to a Z-plane at model depth (or 0)
        let planeZ = centerPos.z
        
        if abs(dir.z) < 0.0001 { return nil }
        
        let t = (planeZ - near.z) / dir.z
        
        return SCNVector3(near.x + dir.x * t, near.y + dir.y * t, planeZ)
    }
    
    private func checkGizmoHit(at location: CGPoint) -> GizmoAxis? {
        guard let gizmo = gizmo else { return nil }
        return gizmo.hitTest(location: location, in: self)
    }
    
    private func selectTooth(_ node: SCNNode) {
        selectedToothNode = node
        onToothSelected?(node.name)
        if gizmo == nil {
            gizmo = GizmoNode()
            self.scene?.rootNode.addChildNode(gizmo!)
        }
        gizmo?.position = node.worldPosition
        gizmo?.isHidden = false
        highlightTooth(node, highlighted: true)
    }
    
    private func deselectTooth() {
        if let tooth = selectedToothNode { highlightTooth(tooth, highlighted: false) }
        selectedToothNode = nil
        gizmo?.isHidden = true
        onToothSelected?(nil)
    }
    
    private func highlightTooth(_ node: SCNNode, highlighted: Bool) {
        let emissionColor = highlighted ? NSColor.cyan : NSColor.black
        node.geometry?.materials.forEach { mat in mat.emission.contents = emissionColor }
    }
}
