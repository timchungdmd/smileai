import SceneKit
import AppKit

class ToothDropHandler {
    
    enum DropTarget {
        case existingTooth(String)      // Hit an actual tooth mesh
        case curvePoint(SCNVector3, SCNVector4) // Position + Rotation (Tangent)
        case background
    }
    
    /// Calculates drop target based on Curve "Magnetism"
    static func handleDrop(
        in view: SCNView,
        sender: NSDraggingInfo,
        curvePoints: [SCNVector3]
    ) -> (target: DropTarget, url: URL)? {
        
        guard let pasteboard = sender.draggingPasteboard.propertyList(forType: .fileURL) as? String,
              let url = URL(string: pasteboard) else { return nil }
        
        // Validate
        let ext = url.pathExtension.lowercased()
        guard ["obj", "stl", "ply", "usdz", "scn"].contains(ext) else { return nil }
        
        let loc = view.convert(sender.draggingLocation, from: nil)
        
        // 1. Check direct hit on existing tooth
        let hitOptions: [SCNHitTestOption: Any] = [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .ignoreHiddenNodes: true
        ]
        if let hit = view.hitTest(loc, options: hitOptions).first,
           let toothNode = findParentToothNode(from: hit.node) {
            return (.existingTooth(toothNode.name!), url)
        }
        
        // 2. Check "Magnetic" Snap to Curve
        if !curvePoints.isEmpty, let snap = calculateSnapToCurve(view: view, location: loc, points: curvePoints) {
            return (.curvePoint(snap.position, snap.rotation), url)
        }
        
        return (.background, url)
    }
    
    // MARK: - Geometry Math
    
    private static func calculateSnapToCurve(view: SCNView, location: CGPoint, points: [SCNVector3]) -> (position: SCNVector3, rotation: SCNVector4)? {
        guard points.count > 1 else { return nil }
        
        // Ray from camera
        let near = view.unprojectPoint(SCNVector3(location.x, location.y, 0))
        let far = view.unprojectPoint(SCNVector3(location.x, location.y, 1))
        
        // Find closest point on polyline to this ray
        var bestPoint = SCNVector3Zero
        var minDistance: Float = .greatestFiniteMagnitude
        var bestTangent = SCNVector3(1, 0, 0)
        
        for i in 0..<points.count - 1 {
            let p0 = points[i]
            let p1 = points[i+1]
            
            // Math: Closest point on segment p0-p1 to Ray
            if let (ptOnSeg, dist) = closestPointOnSegmentToRay(p0: p0, p1: p1, rayOrigin: near, rayEnd: far) {
                if dist < minDistance {
                    minDistance = dist
                    bestPoint = ptOnSeg
                    
                    // Calculate Tangent (Direction)
                    let dx = p1.x - p0.x
                    let dy = p1.y - p0.y
                    let dz = p1.z - p0.z
                    // macOS uses CGFloat for sqrt, so we cast components if needed, or result
                    let len = sqrt(dx*dx + dy*dy + dz*dz)
                    
                    if len > 0 {
                        bestTangent = SCNVector3(dx/len, dy/len, dz/len)
                    }
                }
            }
        }
        
        // Threshold: If mouse is too far from curve visually, ignore snap (0.05 = 5cm)
        if minDistance < 0.05 {
            let rotation = rotationFromTangent(bestTangent)
            return (bestPoint, rotation)
        }
        
        return nil
    }
    
    // Finds closest point on 3D segment to a 3D ray
    private static func closestPointOnSegmentToRay(p0: SCNVector3, p1: SCNVector3, rayOrigin: SCNVector3, rayEnd: SCNVector3) -> (SCNVector3, Float)? {
        // Basic Check: Distance to midpoint (Simplified for performance)
        let mid = SCNVector3((p0.x+p1.x)/2, (p0.y+p1.y)/2, (p0.z+p1.z)/2)
        let rayDir = SCNVector3(rayEnd.x-rayOrigin.x, rayEnd.y-rayOrigin.y, rayEnd.z-rayOrigin.z)
        
        // Project mid onto ray to find distance
        let v = SCNVector3(mid.x-rayOrigin.x, mid.y-rayOrigin.y, mid.z-rayOrigin.z)
        
        // Dot products
        let dot1 = v.x*rayDir.x + v.y*rayDir.y + v.z*rayDir.z
        let dot2 = rayDir.x*rayDir.x + rayDir.y*rayDir.y + rayDir.z*rayDir.z
        
        let t = dot1 / dot2
        let closestOnRay = SCNVector3(rayOrigin.x + rayDir.x*t, rayOrigin.y + rayDir.y*t, rayOrigin.z + rayDir.z*t)
        
        let dist = sqrt(pow(mid.x-closestOnRay.x, 2) + pow(mid.y-closestOnRay.y, 2) + pow(mid.z-closestOnRay.z, 2))
        
        // FIX: Cast CGFloat to Float for return type
        return (mid, Float(dist))
    }
    
    private static func rotationFromTangent(_ tangent: SCNVector3) -> SCNVector4 {
        // Align +Z (Model Front) to Cross Product of Tangent and Up
        // atan2 returns CGFloat on macOS
        let angle = atan2(tangent.x, tangent.z)
        
        // FIX: Cast CGFloat to Float
        return SCNVector4(0, 1, 0, Float(angle))
    }
    
    private static func findParentToothNode(from node: SCNNode) -> SCNNode? {
        if let name = node.name, name.starts(with: "T_") { return node }
        if let parent = node.parent { return findParentToothNode(from: parent) }
        return nil
    }
}
