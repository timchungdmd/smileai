//
//  EditorView.swift
//  smileai
//
//  Created by Tim Chung on 1/7/26.
//

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
    
    private var selectedToothNode: SCNNode?
    private var gizmo: GizmoNode?
    private var isDraggingGizmo: Bool = false
    private var dragStartPosition: CGPoint?
    private var dragStartToothState: ToothState?
    
    override func mouseDown(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        
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
            
            // Rotation with Option + Scroll
            var state = currentToothStates[name] ?? ToothState()
            let rotationDelta = CGFloat(Float(event.scrollingDeltaY) * 0.01)
            
            // Rotate around Y axis (most common for teeth)
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
        
        // Create or update gizmo
        if gizmo == nil {
            gizmo = GizmoNode()
            self.scene?.rootNode.addChildNode(gizmo!)
        }
        
        gizmo?.position = node.worldPosition
        gizmo?.isHidden = false
        
        // Visual feedback
        highlightTooth(node, highlighted: true)
    }
    
    private func deselectTooth() {
        if let tooth = selectedToothNode {
            highlightTooth(tooth, highlighted: false)
        }
        selectedToothNode = nil
        gizmo?.isHidden = true
        onToothSelected?(nil, false)
    }
    
    private func highlightTooth(_ node: SCNNode, highlighted: Bool) {
        let emissionColor = highlighted ? NSColor.cyan : NSColor.black
        node.geometry?.materials.forEach { mat in
            mat.emission.contents = emissionColor
        }
    }
    
    func updateGizmoPosition() {
        guard let tooth = selectedToothNode else {
            gizmo?.isHidden = true
            return
        }
        gizmo?.position = tooth.worldPosition
        gizmo?.isHidden = false
    }
}
