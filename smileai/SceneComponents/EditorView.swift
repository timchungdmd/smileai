import SceneKit
import AppKit

class EditorView: SCNView {
    var currentMode: DesignMode = .analysis
    var activeLandmarkType: LandmarkType?
    var isPlacingLandmarks: Bool = false
    var onLandmarkPicked: ((SCNVector3) -> Void)?
    var onToothSelected: ((String?, Bool) -> Void)?
    var onToothTransformChange: ((String, ToothState) -> Void)?
    var currentToothStates: [String: ToothState] = [:]
    var snapSettings: SnapSettings = SnapSettings()
    var selectionManager: SelectionManager?
    
    // DRAWING CURVE SUPPORT
    var isDrawingCurve: Bool = false
    var onCurveUpdated: (([SCNVector3]) -> Void)?
    private var currentCurvePoints: [SCNVector3] = []
    
    private var selectedToothNode: SCNNode?
    private var gizmo: GizmoNode?
    private var isDraggingGizmo: Bool = false
    private var dragStartPosition: CGPoint?
    private var dragStartToothState: ToothState?
    
    override func mouseDown(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        
        // DRAWING MODE
        if isDrawingCurve {
            currentCurvePoints.removeAll() // Start new curve
            if let point = projectToArchPlane(location: loc) {
                currentCurvePoints.append(point)
                onCurveUpdated?(currentCurvePoints)
            }
            return // Consume event
        }
        
        switch currentMode {
        case .analysis:
            if isPlacingLandmarks && activeLandmarkType != nil {
                let results = self.hitTest(loc, options: [
                    .rootNode: self.scene!.rootNode,
                    .searchMode: SCNHitTestSearchMode.closest.rawValue
                ])
                if let hit = results.first(where: { $0.node.name == "PATIENT_MODEL" }) {
                    onLandmarkPicked?(hit.worldCoordinates)
                }
            } else {
                super.mouseDown(with: event)
            }
            
        case .design:
            // Check gizmo first
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
            
            // Check tooth selection
            let results = self.hitTest(loc, options: nil)
            if let hit = results.first(where: { $0.node.name?.starts(with: "T_") == true }) {
                let isMultiSelect = event.modifierFlags.contains(.shift)
                selectTooth(hit.node, multiSelect: isMultiSelect)
            } else {
                deselectTooth()
                super.mouseDown(with: event)
            }
        }
        
        dragStartPosition = loc
    }
    
    override func mouseDragged(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        
        // DRAWING MODE
        if isDrawingCurve {
            if let point = projectToArchPlane(location: loc) {
                // Simple distance filter to prevent too many points
                if let last = currentCurvePoints.last {
                    let dist = sqrt(pow(point.x - last.x, 2) + pow(point.y - last.y, 2))
                    if dist > 0.001 { // 1mm
                        currentCurvePoints.append(point)
                        onCurveUpdated?(currentCurvePoints)
                    }
                } else {
                    currentCurvePoints.append(point)
                }
            }
            return
        }
        
        if currentMode == .design && isDraggingGizmo,
           let tooth = selectedToothNode,
           let name = tooth.name,
           let startPos = dragStartPosition,
           let axis = gizmo?.activeAxis {
            
            let deltaX = Float(loc.x - startPos.x)
            let deltaY = Float(loc.y - startPos.y)
            
            var state = dragStartToothState ?? currentToothStates[name] ?? ToothState()
            
            // Apply transformation based on axis - cast Float to CGFloat
            let sensitivity: CGFloat = 0.0001 // 0.1mm per pixel
            switch axis {
            case .x:
                state.position.x += CGFloat(deltaX) * sensitivity
            case .y:
                state.position.y -= CGFloat(deltaY) * sensitivity // Invert Y for screen space
            case .z:
                state.position.z += CGFloat(deltaY) * sensitivity
            case .none:
                break
            }
            
            state.applySnapping(snapSettings)
            onToothTransformChange?(name, state)
        } else if !isDraggingGizmo {
            super.mouseDragged(with: event)
        }
        
        dragStartPosition = loc
    }
    
    override func mouseUp(with event: NSEvent) {
        if isDrawingCurve { return } // Keep logic simple
        
        isDraggingGizmo = false
        dragStartPosition = nil
        dragStartToothState = nil
        gizmo?.activeAxis = .none
        gizmo?.highlightAxis(.none)
        self.allowsCameraControl = true
        super.mouseUp(with: event)
    }
    
    // Project screen point to a Z-plane where the arch sits
    private func projectToArchPlane(location: CGPoint) -> SCNVector3? {
        // Find the "Smile Template" node to determine Z-depth
        let templateZ: CGFloat
        if let template = self.scene?.rootNode.childNode(withName: "SMILE_TEMPLATE", recursively: true) {
            templateZ = CGFloat(template.position.z)
        } else {
            templateZ = 0.05 // Default
        }
        
        // Unproject 2 points to create a ray
        let near = self.unprojectPoint(SCNVector3(location.x, location.y, 0))
        let far = self.unprojectPoint(SCNVector3(location.x, location.y, 1))
        
        // Ray-Plane Intersection (Plane Normal is (0,0,1))
        // P = Origin + Direction * t
        // Z = Origin.z + Direction.z * t
        // t = (TargetZ - Origin.z) / Direction.z
        
        let dir = SCNVector3(far.x - near.x, far.y - near.y, far.z - near.z)
        
        if abs(dir.z) < 0.0001 { return nil } // Parallel to plane
        
        let t = (templateZ - CGFloat(near.z)) / CGFloat(dir.z)
        
        return SCNVector3(
            near.x + dir.x * t,
            near.y + dir.y * t,
            templateZ
        )
    }
    
    // ... (Existing scrollWheel, checkGizmoHit, selectTooth, deselectTooth, highlightTooth, updateGizmoPosition methods preserved) ...
    override func scrollWheel(with event: NSEvent) {
        if currentMode == .design && event.modifierFlags.contains(.option),
           let tooth = selectedToothNode,
           let name = tooth.name {
            var state = currentToothStates[name] ?? ToothState()
            let rotationDelta = CGFloat(Float(event.scrollingDeltaY) * 0.01)
            let currentAngle = state.rotation.w
            state.rotation = SCNVector4(0, 1, 0, currentAngle + rotationDelta)
            state.applySnapping(snapSettings)
            onToothTransformChange?(name, state)
        } else {
            super.scrollWheel(with: event)
        }
    }
    
    private func checkGizmoHit(at location: CGPoint) -> GizmoAxis? {
        guard let gizmo = gizmo else { return nil }
        return gizmo.hitTest(location: location, in: self)
    }
    
    private func selectTooth(_ node: SCNNode, multiSelect: Bool) {
        selectedToothNode = node
        onToothSelected?(node.name, multiSelect)
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
        onToothSelected?(nil, false)
    }
    
    private func highlightTooth(_ node: SCNNode, highlighted: Bool) {
        let emissionColor = highlighted ? NSColor.cyan : NSColor.black
        node.geometry?.materials.forEach { mat in mat.emission.contents = emissionColor }
    }
    
    func updateGizmoPosition() {
        guard let tooth = selectedToothNode else { gizmo?.isHidden = true; return }
        gizmo?.position = tooth.worldPosition
        gizmo?.isHidden = false
    }
}
