//
//  CollisionValidator.swift
//  smileai
//
//  Created by Tim Chung on 1/7/26.
//
import Foundation
import SceneKit

struct CollisionResult {
    var isColliding: Bool
    var penetrationDepth: Float
    var correctionVector: SCNVector3
}

class CollisionValidator {
    func checkToothCollision(_ tooth1: SCNNode, _ tooth2: SCNNode) -> CollisionResult {
        let bounds1 = tooth1.boundingBox
        let bounds2 = tooth2.boundingBox
        
        let world1Min = tooth1.convertPosition(bounds1.min, to: nil)
        let world1Max = tooth1.convertPosition(bounds1.max, to: nil)
        let world2Min = tooth2.convertPosition(bounds2.min, to: nil)
        let world2Max = tooth2.convertPosition(bounds2.max, to: nil)
        
        let overlapX = min(world1Max.x, world2Max.x) - max(world1Min.x, world2Min.x)
        let overlapY = min(world1Max.y, world2Max.y) - max(world1Min.y, world2Min.y)
        let overlapZ = min(world1Max.z, world2Max.z) - max(world1Min.z, world2Min.z)
        
        let isColliding = overlapX > 0 && overlapY > 0 && overlapZ > 0
        
        if isColliding {
            let minOverlap = min(overlapX, overlapY, overlapZ)
            var correctionVector = SCNVector3Zero
            
            if minOverlap == overlapX {
                // FIX: Keep as CGFloat (SCNVector3 uses CGFloat, not Float)
                correctionVector.x = (world1Max.x + world1Min.x > world2Max.x + world2Min.x) ? overlapX : -overlapX
            } else if minOverlap == overlapY {
                correctionVector.y = (world1Max.y + world1Min.y > world2Max.y + world2Min.y) ? overlapY : -overlapY
            } else {
                correctionVector.z = (world1Max.z + world1Min.z > world2Max.z + world2Min.z) ? overlapZ : -overlapZ
            }
            
            return CollisionResult(
                isColliding: true,
                penetrationDepth: Float(minOverlap),
                correctionVector: correctionVector
            )
        }
        
        return CollisionResult(isColliding: false, penetrationDepth: 0, correctionVector: SCNVector3Zero)
    }
    
    func validateArchIntegrity(teeth: [SCNNode]) -> Bool {
        guard teeth.count >= 6 else { return false }
        
        let xPositions = teeth.map { Float($0.worldPosition.x) }
        let archWidth = (xPositions.max() ?? 0) - (xPositions.min() ?? 0)
        
        return DentalConstraints.archWidthRange.contains(archWidth)
    }
}
