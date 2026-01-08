import Foundation
import SceneKit
import ModelIO
import SceneKit.ModelIO

enum ToothType: String, CaseIterable {
    case central = "Central"
    case lateral = "Lateral"
    case canine = "Canine"
    case premolar = "Premolar"
    case molar = "Molar"
}

struct ToothTemplate {
    let meshURL: URL
    let type: ToothType
    let normalizedBounds: (min: SCNVector3, max: SCNVector3)
}

class ToothLibraryManager {
    private var library: [ToothType: [ToothTemplate]] = [:]
    
    func loadFromFolder(_ urls: [URL]) throws {
        library.removeAll()
        
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            
            guard url.pathExtension.lowercased() == "obj" else { continue }
            
            let filename = url.deletingPathExtension().lastPathComponent.lowercased()
            var detectedType: ToothType = .central
            
            if filename.contains("lateral") {
                detectedType = .lateral
            } else if filename.contains("canine") || filename.contains("cuspid") {
                detectedType = .canine
            } else if filename.contains("premolar") || filename.contains("bicuspid") {
                detectedType = .premolar
            } else if filename.contains("molar") {
                detectedType = .molar
            }
            
            if let scene = try? SCNScene(url: url, options: nil),
               let geoNode = findFirstGeometryNode(in: scene.rootNode),
               let geo = geoNode.geometry {
                
                let bounds = geo.boundingBox
                let template = ToothTemplate(
                    meshURL: url,
                    type: detectedType,
                    normalizedBounds: bounds
                )
                
                library[detectedType, default: []].append(template)
            }
        }
    }
    
    func instantiateTooth(type: ToothType) -> SCNNode? {
        guard let template = library[type]?.first else {
            return nil
        }
        
        let access = template.meshURL.startAccessingSecurityScopedResource()
        defer { if access { template.meshURL.stopAccessingSecurityScopedResource() } }
        
        guard let scene = try? SCNScene(url: template.meshURL, options: nil),
              let geoNode = findFirstGeometryNode(in: scene.rootNode) else {
            return nil
        }
        
        let node = geoNode.clone()
        configureDentalMaterial(node)
        
        let bounds = template.normalizedBounds
        let height = bounds.max.y - bounds.min.y
        let targetHeight: Float = 0.010
        // FIX: Cast height to Float explicitly
        let scaleFactor = targetHeight / Float(height)
        node.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
        
        return node
    }
    
    private func findFirstGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = findFirstGeometryNode(in: child) { return found }
        }
        return nil
    }
    
    private func configureDentalMaterial(_ node: SCNNode) {
        node.enumerateChildNodes { child, _ in
            child.geometry?.materials.forEach { applyDentalMaterial($0) }
        }
        node.geometry?.materials.forEach { applyDentalMaterial($0) }
    }
    
    private func applyDentalMaterial(_ material: SCNMaterial) {
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(
            calibratedRed: 0.95,
            green: 0.93,
            blue: 0.88,
            alpha: 1.0
        )
        material.roughness.contents = 0.3
        material.metalness.contents = 0.0
        material.specular.contents = NSColor(white: 0.2, alpha: 1.0)
        material.isDoubleSided = true
    }
}
