//
//  GizmoNode.swift
//  smileai
//
//  Created by Tim Chung on 1/7/26.
//

import SceneKit
import AppKit

enum GizmoAxis {
    case x, y, z
    case none
}

enum GizmoMode {
    case translate
    case rotate
    case scale
}

class GizmoNode: SCNNode {
    var mode: GizmoMode = .translate
    var activeAxis: GizmoAxis = .none
    var gizmoScale: CGFloat = 0.02
    
    private var xHandle: SCNNode!
    private var yHandle: SCNNode!
    private var zHandle: SCNNode!
    
    override init() {
        super.init()
        setupGizmo()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    private func setupGizmo() {
        createTranslationHandles()
    }
    
    private func createTranslationHandles() {
        // X-Axis (Red)
        let xArrow = SCNCone(topRadius: 0, bottomRadius: 0.002, height: 0.02)
        xArrow.firstMaterial?.diffuse.contents = NSColor.red
        xArrow.firstMaterial?.emission.contents = NSColor.red
        xArrow.firstMaterial?.lightingModel = .constant
        xHandle = SCNNode(geometry: xArrow)
        xHandle.name = "GIZMO_X"
        xHandle.eulerAngles.z = -.pi / 2
        xHandle.position.x = 0.015
        xHandle.renderingOrder = 5000
        addChildNode(xHandle)
        
        let xLine = SCNCylinder(radius: 0.0005, height: 0.03)
        xLine.firstMaterial?.diffuse.contents = NSColor.red
        xLine.firstMaterial?.lightingModel = .constant
        let xLineNode = SCNNode(geometry: xLine)
        xLineNode.eulerAngles.z = .pi / 2
        xLineNode.position.x = 0.0075
        xLineNode.renderingOrder = 5000
        xHandle.parent?.addChildNode(xLineNode)
        
        // Y-Axis (Green)
        let yArrow = SCNCone(topRadius: 0, bottomRadius: 0.002, height: 0.02)
        yArrow.firstMaterial?.diffuse.contents = NSColor.green
        yArrow.firstMaterial?.emission.contents = NSColor.green
        yArrow.firstMaterial?.lightingModel = .constant
        yHandle = SCNNode(geometry: yArrow)
        yHandle.name = "GIZMO_Y"
        yHandle.position.y = 0.015
        yHandle.renderingOrder = 5000
        addChildNode(yHandle)
        
        let yLine = SCNCylinder(radius: 0.0005, height: 0.03)
        yLine.firstMaterial?.diffuse.contents = NSColor.green
        yLine.firstMaterial?.lightingModel = .constant
        let yLineNode = SCNNode(geometry: yLine)
        yLineNode.position.y = 0.0075
        yLineNode.renderingOrder = 5000
        yHandle.parent?.addChildNode(yLineNode)
        
        // Z-Axis (Blue)
        let zArrow = SCNCone(topRadius: 0, bottomRadius: 0.002, height: 0.02)
        zArrow.firstMaterial?.diffuse.contents = NSColor.blue
        zArrow.firstMaterial?.emission.contents = NSColor.blue
        zArrow.firstMaterial?.lightingModel = .constant
        zHandle = SCNNode(geometry: zArrow)
        zHandle.name = "GIZMO_Z"
        zHandle.eulerAngles.x = .pi / 2
        zHandle.position.z = 0.015
        zHandle.renderingOrder = 5000
        addChildNode(zHandle)
        
        let zLine = SCNCylinder(radius: 0.0005, height: 0.03)
        zLine.firstMaterial?.diffuse.contents = NSColor.blue
        zLine.firstMaterial?.lightingModel = .constant
        let zLineNode = SCNNode(geometry: zLine)
        zLineNode.eulerAngles.x = .pi / 2
        zLineNode.position.z = 0.0075
        zLineNode.renderingOrder = 5000
        zHandle.parent?.addChildNode(zLineNode)
        
        // Center sphere for uniform scaling
        let center = SCNSphere(radius: 0.003)
        center.firstMaterial?.diffuse.contents = NSColor.white
        center.firstMaterial?.emission.contents = NSColor.white
        center.firstMaterial?.lightingModel = .constant
        let centerNode = SCNNode(geometry: center)
        centerNode.name = "GIZMO_CENTER"
        centerNode.renderingOrder = 5000
        addChildNode(centerNode)
    }
    
    func hitTest(location: CGPoint, in view: SCNView) -> GizmoAxis {
        let hitResults = view.hitTest(location, options: [
            .rootNode: self,
            .searchMode: SCNHitTestSearchMode.all.rawValue
        ])
        
        for result in hitResults {
            if let name = result.node.name ?? result.node.parent?.name {
                switch name {
                case "GIZMO_X": return .x
                case "GIZMO_Y": return .y
                case "GIZMO_Z": return .z
                case "GIZMO_CENTER": return .none // Could be used for uniform scale
                default: continue
                }
            }
        }
        return .none
    }
    
    func highlightAxis(_ axis: GizmoAxis) {
        // Reset all
        [xHandle, yHandle, zHandle].forEach { handle in
            handle?.geometry?.firstMaterial?.emission.intensity = 1.0
        }
        
        // Highlight active
        switch axis {
        case .x:
            xHandle.geometry?.firstMaterial?.emission.intensity = 2.0
        case .y:
            yHandle.geometry?.firstMaterial?.emission.intensity = 2.0
        case .z:
            zHandle.geometry?.firstMaterial?.emission.intensity = 2.0
        case .none:
            break
        }
    }
}
