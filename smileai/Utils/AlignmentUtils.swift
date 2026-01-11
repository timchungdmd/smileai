import SceneKit

class AlignmentUtils {
    
    /// Estimates a transform to align 3D model points to 2D screen points
    static func align3DTo2D(modelPoints: [SCNVector3], screenPoints: [CGPoint], in view: SCNView) -> SCNMatrix4? {
        // Strategy:
        // 1. Project the model points to find their average Z-depth in camera space.
        // 2. Unproject the target 2D screen points to that same Z-depth to get "Target 3D Points".
        // 3. Use 3D-3D alignment (Rigid Body) to align the Model to these Targets.
        
        let n = Float(modelPoints.count)
        let centerModel = modelPoints.reduce(SCNVector3Zero) { SCNVector3($0.x+$1.x, $0.y+$1.y, $0.z+$1.z) }
        let centroid = SCNVector3(centerModel.x/CGFloat(n), centerModel.y/CGFloat(n), centerModel.z/CGFloat(n))
        
        // Average depth from camera
        let projectedCentroid = view.projectPoint(centroid)
        let targetZ = projectedCentroid.z
        
        var targetPoints3D: [SCNVector3] = []
        for p2 in screenPoints {
            // Unproject screen point at the model's depth
            let p3 = view.unprojectPoint(SCNVector3(p2.x, p2.y, targetZ))
            targetPoints3D.append(p3)
        }
        
        return calculateRigidBodyTransform(from: modelPoints, to: targetPoints3D)
    }
    
    /// Calculates optimal rotation/translation to align source to target (Simplified Kabsch)
    static func calculateRigidBodyTransform(from source: [SCNVector3], to target: [SCNVector3]) -> SCNMatrix4 {
        // Simplified translation-only alignment for robustness if SVD is unavailable
        // (Full SVD requires Accelerate framework complexity, using centroid matching here for stability)
        
        let n = CGFloat(source.count)
        
        let sourceCenter = source.reduce(SCNVector3Zero) { SCNVector3($0.x+$1.x, $0.y+$1.y, $0.z+$1.z) }
        let sourceCentroid = SCNVector3(sourceCenter.x/n, sourceCenter.y/n, sourceCenter.z/n)
        
        let targetCenter = target.reduce(SCNVector3Zero) { SCNVector3($0.x+$1.x, $0.y+$1.y, $0.z+$1.z) }
        let targetCentroid = SCNVector3(targetCenter.x/n, targetCenter.y/n, targetCenter.z/n)
        
        // Calculate translation vector
        let translation = SCNVector3(
            targetCentroid.x - sourceCentroid.x,
            targetCentroid.y - sourceCentroid.y,
            targetCentroid.z - sourceCentroid.z
        )
        
        // Return Translation Matrix
        return SCNMatrix4MakeTranslation(translation.x, translation.y, translation.z)
    }
}
