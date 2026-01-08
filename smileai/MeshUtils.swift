import SceneKit
import ModelIO
import SceneKit.ModelIO
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class MeshUtils {
    
    /// Normalizes a tooth mesh for dental design.
    /// 1. Centers the geometry pivot (fixing "swinging" rotations).
    /// 2. Auto-scales metric units (Meters -> Millimeters) based on bounding box.
    static func normalize(_ node: SCNNode) -> SCNNode {
        let clone = node.clone()
        
        // 1. Calculate Bounding Box to find the true center
        // We use the geometry bounding box to determine where the mesh actually is.
        let (minVec, maxVec) = clone.boundingBox
        
        // 2. Center Geometry (Pivot Correction)
        // Shift geometry vertices so the center is at (0,0,0) locally
        let cx = (minVec.x + maxVec.x) / 2
        let cy = (minVec.y + maxVec.y) / 2
        let cz = (minVec.z + maxVec.z) / 2
        
        // Setting the pivot moves the "Handle" to the center of the object
        clone.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)
        
        // 3. Smart Scaling (Unit Detection)
        // A typical central incisor is ~10-12mm tall.
        // If height > 1.0 (e.g. 11.0), it's likely MM. We need Meters (0.011).
        // If height is ~0.01, it's likely already Meters.
        
        let height = maxVec.y - minVec.y
        var scaleFactor: Float = 1.0
        
        if height > 1.0 {
            // Case: File is in Millimeters (e.g. 11.5)
            scaleFactor = 0.001
        } else if height > 0.5 {
            // Safety catch for large files
            scaleFactor = 0.001
        }
        // If height is small (e.g. 0.012), we assume it's already meters.
        
        clone.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
        
        // 4. Material Standardization (Aesthetic White)
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(white: 1.0, alpha: 0.85) // Enamel-like
        mat.lightingModel = .physicallyBased
        mat.roughness.contents = 0.4
        mat.metalness.contents = 0.1
        mat.isDoubleSided = true
        clone.geometry?.materials = [mat]
        
        return clone
    }
}
