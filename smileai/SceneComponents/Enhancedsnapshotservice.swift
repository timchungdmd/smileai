//
//  EnhancedSnapshotService.swift
//  smileai
//
//  High-resolution snapshot with anatomical markers
//

import Foundation
import SceneKit
import AppKit

class EnhancedSnapshotService {
    
    // MARK: - Configuration
    
    struct SnapshotConfig {
        var resolution: Resolution = .match  // Match source view size
        var includeMarkers: Bool = true
        var markerSize: CGFloat = 0.003      // 3mm spheres
        var antialiasingMode: SCNAntialiasingMode = .multisampling4X
        var backgroundColor: NSColor = NSColor(white: 0.1, alpha: 1.0) // Default dark grey
        
        enum Resolution {
            case match                  // Match view pixels exactly (Retina aware)
            case pointSize              // Match view points (1x)
            case scale(CGFloat)         // Multiply view size by factor
            case fixed(width: Int, height: Int)
        }
    }
    
    // MARK: - Main Snapshot Method
    
    /// Capture high-resolution snapshot from SCNView with anatomical markers
    static func captureSnapshot(
        from view: SCNView,
        landmarks: [LandmarkType: SCNVector3],
        config: SnapshotConfig = SnapshotConfig()
    ) -> NSImage? {
        
        // 1. Calculate target size (Pixels)
        let viewPointsSize = view.bounds.size
        let screenScale = view.window?.backingScaleFactor ?? 2.0 // Default to 2x if window not found
        let targetSize: CGSize
        
        switch config.resolution {
        case .match:
            // Match pixels: Points * Scale Factor
            targetSize = CGSize(
                width: viewPointsSize.width * screenScale,
                height: viewPointsSize.height * screenScale
            )
        case .pointSize:
            targetSize = viewPointsSize
        case .scale(let factor):
            targetSize = CGSize(
                width: viewPointsSize.width * factor,
                height: viewPointsSize.height * factor
            )
        case .fixed(let width, let height):
            targetSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        }
        
        print("📸 Snapshot: View \(viewPointsSize) -> Target \(targetSize) (Scale: \(screenScale))")
        
        // 2. Clone the scene content
        guard let originalScene = view.scene else { return nil }
        
        let snapshotScene = SCNScene()
        // Copy background
        snapshotScene.background.contents = config.backgroundColor
        
        // Deep copy of the root node hierarchy
        // Note: SCNScene.clone() is not available, but cloning the rootNode works for content
        let clonedRoot = originalScene.rootNode.clone()
        snapshotScene.rootNode.addChildNode(clonedRoot)
        
        // 3. Add landmark markers as geometry (not overlays)
        if config.includeMarkers && !landmarks.isEmpty {
            addLandmarkGeometry(to: snapshotScene, landmarks: landmarks, markerSize: config.markerSize)
        }
        
        // 4. Create offscreen renderer
        guard let device = view.device else { return nil }
        
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = snapshotScene
        renderer.autoenablesDefaultLighting = true
        
        // 5. Copy camera settings EXACTLY
        if let originalCameraNode = view.pointOfView {
            // Clone the camera node properties
            let cameraClone = originalCameraNode.clone()
            
            // FIX: Force the world transform to match the current view
            // This handles cases where the camera is moved by orbit controls
            cameraClone.transform = originalCameraNode.worldTransform
            
            // If the original camera had a parent, we need to ensure the clone works in root space
            // Setting worldTransform on a root-level node works perfectly.
            snapshotScene.rootNode.addChildNode(cameraClone)
            
            renderer.pointOfView = cameraClone
            
            print("📷 Camera Matched: \(cameraClone.position)")
        }
        
        // 6. Render
        let image = renderer.snapshot(
            atTime: 0,
            with: targetSize,
            antialiasingMode: config.antialiasingMode
        )
        
        return image
    }
    
    // MARK: - Landmark Geometry Generation
    
    private static func addLandmarkGeometry(
        to scene: SCNScene,
        landmarks: [LandmarkType: SCNVector3],
        markerSize: CGFloat
    ) {
        let markerContainer = SCNNode()
        markerContainer.name = "SNAPSHOT_MARKERS"
        scene.rootNode.addChildNode(markerContainer)
        
        for (type, position) in landmarks {
            // Sphere
            let sphere = SCNSphere(radius: markerSize)
            sphere.segmentCount = 16
            
            let material = SCNMaterial()
            material.diffuse.contents = type.nsColor
            material.emission.contents = type.nsColor.blended(withFraction: 0.5, of: .white)
            material.lightingModel = .constant
            sphere.firstMaterial = material
            
            let markerNode = SCNNode(geometry: sphere)
            markerNode.position = position
            markerContainer.addChildNode(markerNode)
            
            // Label
            if let labelNode = createLabelNode(for: type, at: position, markerSize: markerSize) {
                markerContainer.addChildNode(labelNode)
            }
        }
    }
    
    private static func createLabelNode(
        for type: LandmarkType,
        at position: SCNVector3,
        markerSize: CGFloat
    ) -> SCNNode? {
        let text = SCNText(string: type.rawValue.prefix(2).uppercased(), extrusionDepth: 0.0)
        // Tune font size relative to marker size
        text.font = NSFont.systemFont(ofSize: markerSize * 800, weight: .bold)
        text.flatness = 0.1
        
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.white
        material.lightingModel = .constant
        text.firstMaterial = material
        
        let textNode = SCNNode(geometry: text)
        
        // Center text
        let (min, max) = textNode.boundingBox
        let w = CGFloat(max.x - min.x)
        
        textNode.position = SCNVector3(
            position.x - w / 2,
            position.y + (markerSize * 2.5),
            position.z
        )
        
        // Billboard constraint
        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = [.Y]
        textNode.constraints = [constraint]
        
        return textNode
    }
}
