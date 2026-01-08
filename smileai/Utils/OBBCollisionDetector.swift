import Foundation
import SceneKit

struct OBB {
    var center: SCNVector3
    var axes: [SCNVector3]
    var halfExtents: SCNVector3
    
    init(from node: SCNNode) {
        guard let geometry = node.geometry else {
            center = node.worldPosition
            axes = [SCNVector3(1, 0, 0), SCNVector3(0, 1, 0), SCNVector3(0, 0, 1)]
            halfExtents = SCNVector3(0.001, 0.001, 0.001)
            return
        }
        
        let (min, max) = geometry.boundingBox
        let worldTransform = node.worldTransform
        center = node.worldPosition
        
        let axis1 = SCNVector3(
            Float(worldTransform.m11),
            Float(worldTransform.m12),
            Float(worldTransform.m13)
        ).normalized
        
        let axis2 = SCNVector3(
            Float(worldTransform.m21),
            Float(worldTransform.m22),
            Float(worldTransform.m23)
        ).normalized
        
        let axis3 = SCNVector3(
            Float(worldTransform.m31),
            Float(worldTransform.m32),
            Float(worldTransform.m33)
        ).normalized
        
        axes = [axis1, axis2, axis3]
        
        let sizeX = Float(max.x - min.x) / 2
        let sizeY = Float(max.y - min.y) / 2
        let sizeZ = Float(max.z - min.z) / 2
        
        halfExtents = SCNVector3(
            sizeX * Float(node.scale.x),
            sizeY * Float(node.scale.y),
            sizeZ * Float(node.scale.z)
        )
    }
    
    func getCorners() -> [SCNVector3] {
        var corners: [SCNVector3] = []
        for i in 0..<8 {
            let x = (i & 1) == 0 ? -Float(halfExtents.x) : Float(halfExtents.x)
            let y = (i & 2) == 0 ? -Float(halfExtents.y) : Float(halfExtents.y)
            let z = (i & 4) == 0 ? -Float(halfExtents.z) : Float(halfExtents.z)
            
            var corner = center
            corner = corner + axes[0] * x
            corner = corner + axes[1] * y
            corner = corner + axes[2] * z
            corners.append(corner)
        }
        return corners
    }
}

class OBBCollisionDetector {
    func testIntersection(_ obb1: OBB, _ obb2: OBB) -> CollisionResult {
        var minPenetration: Float = .infinity
        var minAxis = SCNVector3(1, 0, 0)
        
        var testAxes: [SCNVector3] = []
        testAxes.append(contentsOf: obb1.axes)
        testAxes.append(contentsOf: obb2.axes)
        
        for i in 0..<3 {
            for j in 0..<3 {
                let cross = obb1.axes[i].cross(obb2.axes[j])
                if cross.length > 0.0001 {
                    testAxes.append(cross.normalized)
                }
            }
        }
        
        for axis in testAxes {
            let (overlap, depth) = projectAndOverlap(obb1, obb2, axis: axis)
            
            if !overlap {
                return CollisionResult(
                    isColliding: false,
                    penetrationDepth: 0,
                    correctionVector: SCNVector3Zero
                )
            }
            
            if depth < minPenetration {
                minPenetration = depth
                minAxis = axis
            }
        }
        
        let direction = (obb2.center - obb1.center).dot(minAxis) > 0 ? minAxis : minAxis * -1
        
        return CollisionResult(
            isColliding: true,
            penetrationDepth: minPenetration,
            correctionVector: direction * minPenetration
        )
    }
    
    private func projectAndOverlap(_ obb1: OBB, _ obb2: OBB, axis: SCNVector3) -> (overlap: Bool, depth: Float) {
        let proj1 = projectOBB(obb1, onto: axis)
        let proj2 = projectOBB(obb2, onto: axis)
        
        let overlap = proj1.max >= proj2.min && proj2.max >= proj1.min
        
        if !overlap {
            return (false, 0)
        }
        
        let depth = min(proj1.max - proj2.min, proj2.max - proj1.min)
        return (true, depth)
    }
    
    private func projectOBB(_ obb: OBB, onto axis: SCNVector3) -> (min: Float, max: Float) {
        let corners = obb.getCorners()
        let projections = corners.map { $0.dot(axis) }
        
        return (projections.min()!, projections.max()!)
    }
    
    func detectAllCollisions(in nodes: [SCNNode]) -> [(SCNNode, SCNNode, CollisionResult)] {
        var results: [(SCNNode, SCNNode, CollisionResult)] = []
        
        let grid = buildSpatialHash(nodes: nodes, cellSize: 0.02)
        
        for (_, cellNodes) in grid {
            for i in 0..<cellNodes.count {
                for j in (i+1)..<cellNodes.count {
                    let obb1 = OBB(from: cellNodes[i])
                    let obb2 = OBB(from: cellNodes[j])
                    
                    let result = testIntersection(obb1, obb2)
                    if result.isColliding {
                        results.append((cellNodes[i], cellNodes[j], result))
                    }
                }
            }
        }
        
        return results
    }
    
    private func buildSpatialHash(nodes: [SCNNode], cellSize: Float) -> [SIMD3<Int>: [SCNNode]] {
        var grid: [SIMD3<Int>: [SCNNode]] = [:]
        
        for node in nodes {
            let pos = node.worldPosition
            let cell = SIMD3<Int>(
                Int(Float(pos.x) / cellSize),
                Int(Float(pos.y) / cellSize),
                Int(Float(pos.z) / cellSize)
            )
            grid[cell, default: []].append(node)
            
            for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        if dx == 0 && dy == 0 && dz == 0 { continue }
                        let adjacentCell = SIMD3<Int>(cell.x + dx, cell.y + dy, cell.z + dz)
                        grid[adjacentCell, default: []].append(node)
                    }
                }
            }
        }
        
        return grid
    }
}
