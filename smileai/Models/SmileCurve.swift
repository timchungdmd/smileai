//
//  SmileCurve.swift
//  smileai
//
//  Created by Tim Chung on 1/7/26.
//

import Foundation
import SceneKit

struct SmileCurvePoint: Codable {
    var position: SCNVector3
    var normalizedX: Float  // -1 (left) to 1 (right)
}

struct SmileCurve: Codable {
    var controlPoints: [SmileCurvePoint] = []
    var curveType: CurveType = .natural
    
    enum CurveType: String, Codable, CaseIterable {
        case natural = "Natural"
        case parallel = "Parallel to Lip"
        case upturned = "Upturned"
        case straight = "Straight"
        case custom = "Custom"
    }
    
    // Generate curve based on facial landmarks
    static func generateFromLandmarks(
        _ landmarks: [LandmarkType: SCNVector3],
        type: CurveType
    ) -> SmileCurve {
        var curve = SmileCurve()
        curve.curveType = type
        
        guard let leftCommissure = landmarks[.leftCommissure],
              let rightCommissure = landmarks[.rightCommissure],
              let upperLipCenter = landmarks[.upperLipCenter],
              let leftCanine = landmarks[.leftCanine],
              let rightCanine = landmarks[.rightCanine],
              let midline = landmarks[.midline] else {
            return curve
        }
        
        let archWidth = abs(Float(rightCanine.x - leftCanine.x))
        
        switch type {
        case .natural:
            // Natural smile follows the lower lip curve
            curve.controlPoints = generateNaturalCurve(
                leftCommissure: leftCommissure,
                rightCommissure: rightCommissure,
                upperLipCenter: upperLipCenter,
                midline: midline,
                archWidth: archWidth
            )
            
        case .parallel:
            // Parallel to lower lip line
            let lipSlope = (rightCommissure.y - leftCommissure.y) / (rightCommissure.x - leftCommissure.x)
            curve.controlPoints = generateParallelCurve(
                leftCanine: leftCanine,
                rightCanine: rightCanine,
                midline: midline,
                lipSlope: Float(lipSlope)
            )
            
        case .upturned:
            // Hollywood smile - upturned at edges
            curve.controlPoints = generateUpturnedCurve(
                leftCanine: leftCanine,
                rightCanine: rightCanine,
                midline: midline,
                archWidth: archWidth
            )
            
        case .straight:
            // Straight horizontal line
            curve.controlPoints = generateStraightCurve(
                leftCanine: leftCanine,
                rightCanine: rightCanine,
                midline: midline
            )
            
        case .custom:
            // User-drawn curve
            break
        }
        
        return curve
    }
    
    private static func generateNaturalCurve(
        leftCommissure: SCNVector3,
        rightCommissure: SCNVector3,
        upperLipCenter: SCNVector3,
        midline: SCNVector3,
        archWidth: Float
    ) -> [SmileCurvePoint] {
        var points: [SmileCurvePoint] = []
        let numPoints = 15
        
        for i in 0..<numPoints {
            let t = Float(i) / Float(numPoints - 1) // 0 to 1
            let normalizedX = (t * 2) - 1 // -1 to 1
            
            // Catenary curve for natural smile
            let a: Float = 0.8
            let catenaryCurve = a * (cosh(normalizedX * 1.5 / a) - 1)
            
            // Position along the arch
            let x = Float(midline.x) + normalizedX * (archWidth / 2)
            
            // Height based on catenary and lip reference
            let baseHeight = Float(upperLipCenter.y) - 0.003
            let y = baseHeight - catenaryCurve * 0.002
            
            // Slight forward position
            let z = Float(upperLipCenter.z) + 0.002
            
            points.append(SmileCurvePoint(
                position: SCNVector3(x, y, z),
                normalizedX: normalizedX
            ))
        }
        
        return points
    }
    
    private static func generateParallelCurve(
        leftCanine: SCNVector3,
        rightCanine: SCNVector3,
        midline: SCNVector3,
        lipSlope: Float
    ) -> [SmileCurvePoint] {
        var points: [SmileCurvePoint] = []
        let numPoints = 15
        let archWidth = abs(Float(rightCanine.x - leftCanine.x))
        
        for i in 0..<numPoints {
            let t = Float(i) / Float(numPoints - 1)
            let normalizedX = (t * 2) - 1
            
            let x = Float(midline.x) + normalizedX * (archWidth / 2)
            let y = Float(rightCanine.y) + lipSlope * normalizedX * (archWidth / 2)
            let z = Float(rightCanine.z) + 0.002
            
            points.append(SmileCurvePoint(
                position: SCNVector3(x, y, z),
                normalizedX: normalizedX
            ))
        }
        
        return points
    }
    
    private static func generateUpturnedCurve(
        leftCanine: SCNVector3,
        rightCanine: SCNVector3,
        midline: SCNVector3,
        archWidth: Float
    ) -> [SmileCurvePoint] {
        var points: [SmileCurvePoint] = []
        let numPoints = 15
        
        for i in 0..<numPoints {
            let t = Float(i) / Float(numPoints - 1)
            let normalizedX = (t * 2) - 1
            
            // Parabola opening upward
            let upturn = normalizedX * normalizedX * 0.003
            
            let x = Float(midline.x) + normalizedX * (archWidth / 2)
            let y = Float(rightCanine.y) + upturn
            let z = Float(rightCanine.z) + 0.002
            
            points.append(SmileCurvePoint(
                position: SCNVector3(x, y, z),
                normalizedX: normalizedX
            ))
        }
        
        return points
    }
    
    private static func generateStraightCurve(
        leftCanine: SCNVector3,
        rightCanine: SCNVector3,
        midline: SCNVector3
    ) -> [SmileCurvePoint] {
        var points: [SmileCurvePoint] = []
        let numPoints = 15
        let archWidth = abs(Float(rightCanine.x - leftCanine.x))
        let avgY = (Float(leftCanine.y) + Float(rightCanine.y)) / 2
        
        for i in 0..<numPoints {
            let t = Float(i) / Float(numPoints - 1)
            let normalizedX = (t * 2) - 1
            
            let x = Float(midline.x) + normalizedX * (archWidth / 2)
            let y = avgY
            let z = Float(rightCanine.z) + 0.002
            
            points.append(SmileCurvePoint(
                position: SCNVector3(x, y, z),
                normalizedX: normalizedX
            ))
        }
        
        return points
    }
    
    // Interpolate curve to get position at any normalized X
    func interpolate(at normalizedX: Float) -> SCNVector3? {
        guard !controlPoints.isEmpty else { return nil }
        
        // Find the two control points to interpolate between
        var leftPoint = controlPoints.first!
        var rightPoint = controlPoints.last!
        
        for i in 0..<(controlPoints.count - 1) {
            if controlPoints[i].normalizedX <= normalizedX &&
               controlPoints[i + 1].normalizedX >= normalizedX {
                leftPoint = controlPoints[i]
                rightPoint = controlPoints[i + 1]
                break
            }
        }
        
        // Linear interpolation
        let range = rightPoint.normalizedX - leftPoint.normalizedX
        guard range > 0 else { return leftPoint.position }
        
        let t = CGFloat((normalizedX - leftPoint.normalizedX) / range)
        
        return SCNVector3(
            x: leftPoint.position.x + t * (rightPoint.position.x - leftPoint.position.x),
            y: leftPoint.position.y + t * (rightPoint.position.y - leftPoint.position.y),
            z: leftPoint.position.z + t * (rightPoint.position.z - leftPoint.position.z)
        )
    }
}
