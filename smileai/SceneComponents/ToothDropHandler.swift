import SceneKit
import AppKit

class ToothDropHandler {
    
    enum DropTarget {
        case existingTooth(String)
        case curvePoint(SCNVector3, SCNVector4)
        case background
    }
    
    static func handleDrop(in view: SCNView, sender: NSDraggingInfo, curvePoints: [SCNVector3]) -> (target: DropTarget, url: URL)? {
        // 1. CRITICAL FIX: Use readObjects to preserve the Security Scope (The "Access Key")
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let originalUrl = urls.first else { return nil }
        
        // 2. CRITICAL FIX: Securely copy the file to a temp location we own
        // Without this, the app loses permission the moment the drop gesture ends.
        guard let safeUrl = secureCopyToTemp(url: originalUrl) else {
            print("❌ Failed to copy dropped file to temp storage.")
            return nil
        }
        
        let ext = safeUrl.pathExtension.lowercased()
        guard ["obj", "stl", "ply", "usdz", "scn"].contains(ext) else { return nil }
        
        let loc = view.convert(sender.draggingLocation, from: nil)
        
        // 3. Check direct hit on existing tooth
        let hitOptions: [SCNHitTestOption: Any] = [.searchMode: SCNHitTestSearchMode.closest.rawValue, .ignoreHiddenNodes: true]
        if let hit = view.hitTest(loc, options: hitOptions).first,
           let toothNode = findParentToothNode(from: hit.node) {
            return (.existingTooth(toothNode.name!), safeUrl)
        }
        
        // 4. Check "Magnetic" Snap to Curve
        if !curvePoints.isEmpty, let snap = calculateSnapToCurve(view: view, location: loc, points: curvePoints) {
            return (.curvePoint(snap.position, snap.rotation), safeUrl)
        }
        
        return (.background, safeUrl)
    }
    
    // MARK: - Secure File Handling
    static func secureCopyToTemp(url: URL) -> URL? {
        // A. Explicitly ask to use the "Access Key"
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        // B. Perform the copy
        do {
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory
            let dst = tempDir.appendingPathComponent(url.lastPathComponent)
            
            if fileManager.fileExists(atPath: dst.path) {
                try fileManager.removeItem(at: dst)
            }
            
            try fileManager.copyItem(at: url, to: dst)
            return dst
        } catch {
            print("❌ Error copying file during drop: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Geometry Logic (Unchanged)
    private static func calculateSnapToCurve(view: SCNView, location: CGPoint, points: [SCNVector3]) -> (position: SCNVector3, rotation: SCNVector4)? {
        guard points.count > 1 else { return nil }
        
        let near = view.unprojectPoint(SCNVector3(location.x, location.y, 0))
        let far = view.unprojectPoint(SCNVector3(location.x, location.y, 1))
        
        var bestPoint = SCNVector3Zero
        var minDistance: Float = .greatestFiniteMagnitude
        var bestTangent = SCNVector3(1, 0, 0)
        
        for i in 0..<points.count - 1 {
            let p0 = points[i]
            let p1 = points[i+1]
            
            if let (ptOnSeg, dist) = closestPointOnSegmentToRay(p0: p0, p1: p1, rayOrigin: near, rayEnd: far) {
                if dist < minDistance {
                    minDistance = dist
                    bestPoint = ptOnSeg
                    
                    let dx = p1.x - p0.x
                    let dy = p1.y - p0.y
                    let dz = p1.z - p0.z
                    let len = sqrt(dx*dx + dy*dy + dz*dz)
                    
                    if len > 0 {
                        bestTangent = SCNVector3(dx/len, dy/len, dz/len)
                    }
                }
            }
        }
        
        if minDistance < 0.05 {
            let rotation = rotationFromTangent(bestTangent)
            return (bestPoint, rotation)
        }
        
        return nil
    }
    
    private static func closestPointOnSegmentToRay(p0: SCNVector3, p1: SCNVector3, rayOrigin: SCNVector3, rayEnd: SCNVector3) -> (SCNVector3, Float)? {
        let mid = SCNVector3((p0.x+p1.x)/2, (p0.y+p1.y)/2, (p0.z+p1.z)/2)
        let rayDir = SCNVector3(rayEnd.x-rayOrigin.x, rayEnd.y-rayOrigin.y, rayEnd.z-rayOrigin.z)
        
        let v = SCNVector3(mid.x-rayOrigin.x, mid.y-rayOrigin.y, mid.z-rayOrigin.z)
        let dot1 = v.x*rayDir.x + v.y*rayDir.y + v.z*rayDir.z
        let dot2 = rayDir.x*rayDir.x + rayDir.y*rayDir.y + rayDir.z*rayDir.z
        
        let t = dot1 / dot2
        let closestOnRay = SCNVector3(rayOrigin.x + rayDir.x*t, rayOrigin.y + rayDir.y*t, rayOrigin.z + rayDir.z*t)
        
        let dx = mid.x - closestOnRay.x
        let dy = mid.y - closestOnRay.y
        let dz = mid.z - closestOnRay.z
        
        let distSq = Float(dx*dx + dy*dy + dz*dz)
        return (mid, sqrt(distSq))
    }
    
    private static func rotationFromTangent(_ tangent: SCNVector3) -> SCNVector4 {
        let angle = atan2(tangent.x, tangent.z)
        return SCNVector4(0, 1, 0, Float(angle))
    }
    
    private static func findParentToothNode(from node: SCNNode) -> SCNNode? {
        if let name = node.name, name.starts(with: "T_") { return node }
        if let parent = node.parent { return findParentToothNode(from: parent) }
        return nil
    }
}
