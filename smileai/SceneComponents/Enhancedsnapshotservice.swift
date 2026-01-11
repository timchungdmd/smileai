//
//  EnhancedSnapshotService.swift
//  smileai
//
//  High-resolution snapshot with anatomical markers
//  Created by Polymath Architect
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
        var backgroundColor: NSColor = .black
        
        enum Resolution {
            case match                  // Match view size exactly
            case scale(CGFloat)        // Multiply view size by factor
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
        
        // 1. Calculate target size
        let viewSize = view.bounds.size
        let targetSize: CGSize
        
        switch config.resolution {
        case .match:
            targetSize = viewSize
        case .scale(let factor):
            targetSize = CGSize(
                width: viewSize.width * factor,
                height: viewSize.height * factor
            )
        case .fixed(let width, let height):
            targetSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        }
        
        print("📸 Snapshot Configuration:")
        print("   View Size: \(viewSize.width) x \(viewSize.height)")
        print("   Target Size: \(targetSize.width) x \(targetSize.height)")
        
        // 2. Clone the scene to avoid modifying the live view
        guard let originalScene = view.scene else {
            print("❌ No scene available")
            return nil
        }
        
        let snapshotScene = originalScene.clone()
        
        // 3. Add landmark markers as geometry (not overlays)
        if config.includeMarkers && !landmarks.isEmpty {
            addLandmarkGeometry(to: snapshotScene, landmarks: landmarks, markerSize: config.markerSize)
            print("✅ Added \(landmarks.count) landmark markers to snapshot")
        }
        
        // 4. Create offscreen renderer
        guard let device = view.device else {
            print("❌ No Metal device available")
            return nil
        }
        
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = snapshotScene
        renderer.autoenablesDefaultLighting = true
        
        // 5. Copy camera settings from live view
        if let originalCamera = view.pointOfView {
            // Clone the camera node with all transforms
            let cameraClone = originalCamera.clone()
            renderer.pointOfView = cameraClone
            
            print("📷 Camera Settings:")
            print("   Position: \(cameraClone.position)")
            print("   Euler: \(cameraClone.eulerAngles)")
            if let camera = cameraClone.camera {
                print("   FOV: \(camera.fieldOfView)°")
            }
        }
        
        // 6. Render at high resolution
        let image = renderer.snapshot(
            atTime: 0,
            with: targetSize,
            antialiasingMode: config.antialiasingMode
        )
        
        print("✅ Snapshot captured: \(image.size.width) x \(image.size.height)")
        
        return image
    }
    
    // MARK: - Landmark Geometry Generation
    
    /// Add anatomical markers as 3D geometry (not SwiftUI overlays)
    private static func addLandmarkGeometry(
        to scene: SCNScene,
        landmarks: [LandmarkType: SCNVector3],
        markerSize: CGFloat
    ) {
        
        // Create container node for markers
        let markerContainer = SCNNode()
        markerContainer.name = "SNAPSHOT_MARKERS"
        scene.rootNode.addChildNode(markerContainer)
        
        for (type, position) in landmarks {
            // Create sphere geometry
            let sphere = SCNSphere(radius: markerSize)
            sphere.segmentCount = 16
            
            // Use landmark's color
            let material = SCNMaterial()
            material.diffuse.contents = type.nsColor
            material.emission.contents = type.nsColor.blended(withFraction: 0.5, of: .white)
            material.lightingModel = .constant  // Always visible
            sphere.firstMaterial = material
            
            // Create node
            let markerNode = SCNNode(geometry: sphere)
            markerNode.position = position
            markerNode.name = "MARKER_\(type.rawValue)"
            
            markerContainer.addChildNode(markerNode)
            
            // Add label (optional - creates text geometry)
            if let labelNode = createLabelNode(for: type, at: position, markerSize: markerSize) {
                markerContainer.addChildNode(labelNode)
            }
        }
    }
    
    /// Create 3D text label for landmark
    private static func createLabelNode(
        for type: LandmarkType,
        at position: SCNVector3,
        markerSize: CGFloat
    ) -> SCNNode? {
        
        // Create 3D text
        let text = SCNText(string: type.rawValue.prefix(2).uppercased(), extrusionDepth: 0.0)
        text.font = NSFont.systemFont(ofSize: markerSize * 800, weight: .bold)  // Scale font
        text.flatness = 0.1
        
        // Material
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.white
        material.emission.contents = NSColor.white
        material.lightingModel = .constant
        text.firstMaterial = material
        
        // Create node
        let textNode = SCNNode(geometry: text)
        
        // Center the text
        let (min, max) = textNode.boundingBox
        let textWidth = CGFloat(max.x - min.x)
        let textHeight = CGFloat(max.y - min.y)
        
        textNode.position = SCNVector3(
            position.x - textWidth / 2,
            position.y + Float(markerSize * 2),  // Position above marker
            position.z
        )
        
        // Make text always face camera (billboard effect)
        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = [.Y]  // Only rotate around Y axis
        textNode.constraints = [constraint]
        
        return textNode
    }
    
    // MARK: - Convenience Methods
    
    /// Quick snapshot at view resolution
    static func quickSnapshot(
        from view: SCNView,
        landmarks: [LandmarkType: SCNVector3]
    ) -> NSImage? {
        return captureSnapshot(from: view, landmarks: landmarks)
    }
    
    /// High-resolution snapshot (2x scale)
    static func highResSnapshot(
        from view: SCNView,
        landmarks: [LandmarkType: SCNVector3]
    ) -> NSImage? {
        var config = SnapshotConfig()
        config.resolution = .scale(2.0)
        return captureSnapshot(from: view, landmarks: landmarks, config: config)
    }
    
    /// Ultra high-resolution snapshot (4x scale)
    static func ultraResSnapshot(
        from view: SCNView,
        landmarks: [LandmarkType: SCNVector3]
    ) -> NSImage? {
        var config = SnapshotConfig()
        config.resolution = .scale(4.0)
        return captureSnapshot(from: view, landmarks: landmarks, config: config)
    }
    
    /// Fixed resolution snapshot (e.g., for 4K output)
    static func fixedResSnapshot(
        from view: SCNView,
        landmarks: [LandmarkType: SCNVector3],
        width: Int,
        height: Int
    ) -> NSImage? {
        var config = SnapshotConfig()
        config.resolution = .fixed(width: width, height: height)
        return captureSnapshot(from: view, landmarks: landmarks, config: config)
    }
}

// MARK: - Integration Helper

extension EnhancedSnapshotService {
    
    /// Process snapshot for display (ensure proper sizing)
    static func processForDisplay(_ image: NSImage, targetSize: CGSize) -> NSImage {
        
        // If image already matches target, return as-is
        if abs(image.size.width - targetSize.width) < 1.0 &&
           abs(image.size.height - targetSize.height) < 1.0 {
            return image
        }
        
        // Create properly sized representation
        let targetRect = CGRect(origin: .zero, size: targetSize)
        let outputImage = NSImage(size: targetSize)
        
        outputImage.lockFocus()
        
        // Draw with aspect fill
        let imageAspect = image.size.width / image.size.height
        let targetAspect = targetSize.width / targetSize.height
        
        var drawRect = targetRect
        
        if imageAspect > targetAspect {
            // Image is wider - fit height
            let scaledWidth = targetSize.height * imageAspect
            drawRect = CGRect(
                x: (targetSize.width - scaledWidth) / 2,
                y: 0,
                width: scaledWidth,
                height: targetSize.height
            )
        } else {
            // Image is taller - fit width
            let scaledHeight = targetSize.width / imageAspect
            drawRect = CGRect(
                x: 0,
                y: (targetSize.height - scaledHeight) / 2,
                width: targetSize.width,
                height: scaledHeight
            )
        }
        
        image.draw(in: drawRect)
        outputImage.unlockFocus()
        
        return outputImage
    }
}
