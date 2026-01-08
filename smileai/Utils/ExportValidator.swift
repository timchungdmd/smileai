//
//  ExportValidator.swift
//  smileai
//
//  Created by Tim Chung on 1/7/26.
//

import Foundation
import SceneKit

struct ValidationReport {
    var hasCollisions: Bool = false
    var collisionPairs: [(String, String)] = []
    
    var isSymmetric: Bool = true
    var symmetryErrors: [String] = []
    
    var archIntegrityValid: Bool = true
    var archErrors: [String] = []
    
    var passed: Bool {
        !hasCollisions && isSymmetric && archIntegrityValid
    }
    
    var summary: String {
        var lines: [String] = []
        
        if hasCollisions {
            lines.append("❌ Collisions Detected: \(collisionPairs.count)")
            collisionPairs.prefix(3).forEach { pair in
                lines.append("   • \(pair.0) ↔ \(pair.1)")
            }
            if collisionPairs.count > 3 {
                lines.append("   • ... and \(collisionPairs.count - 3) more")
            }
        } else {
            lines.append("✅ No Collisions")
        }
        
        if !isSymmetric {
            lines.append("⚠️ Symmetry Issues: \(symmetryErrors.count)")
            symmetryErrors.prefix(2).forEach { lines.append("   • \($0)") }
        } else {
            lines.append("✅ Bilateral Symmetry OK")
        }
        
        if !archIntegrityValid {
            lines.append("⚠️ Arch Issues: \(archErrors.count)")
            archErrors.forEach { lines.append("   • \($0)") }
        } else {
            lines.append("✅ Arch Integrity OK")
        }
        
        return lines.joined(separator: "\n")
    }
}

class ExportValidator {
    private let collisionDetector = OBBCollisionDetector()
    private let symmetryTolerance: Float = 0.002
    
    func validate(
        teeth: [String: SCNNode],
        states: [String: ToothState],
        landmarks: [LandmarkType: SCNVector3]
    ) -> ValidationReport {
        var report = ValidationReport()
        
        let toothNodes = Array(teeth.values)
        let collisions = collisionDetector.detectAllCollisions(in: toothNodes)
        
        if !collisions.isEmpty {
            report.hasCollisions = true
            report.collisionPairs = collisions.map {
                ($0.0.name ?? "Unknown", $0.1.name ?? "Unknown")
            }
        }
        
        let symmetryResults = checkBilateralSymmetry(
            teeth: teeth,
            states: states,
            landmarks: landmarks
        )
        report.isSymmetric = symmetryResults.isSymmetric
        report.symmetryErrors = symmetryResults.errors
        
        let archResults = checkArchIntegrity(
            teeth: teeth,
            states: states,
            landmarks: landmarks
        )
        report.archIntegrityValid = archResults.isValid
        report.archErrors = archResults.errors
        
        return report
    }
    
    private func checkBilateralSymmetry(
        teeth: [String: SCNNode],
        states: [String: ToothState],
        landmarks: [LandmarkType: SCNVector3]
    ) -> (isSymmetric: Bool, errors: [String]) {
        var errors: [String] = []
        
        guard let midline = landmarks[.midline] else {
            errors.append("Midline not defined")
            return (false, errors)
        }
        
        let midlineX = midline.x
        let pairs = [(1, "Central"), (2, "Lateral"), (3, "Canine")]
        
        for (id, name) in pairs {
            let rightID = "T_\(id)_R"
            let leftID = "T_\(id)_L"
            
            guard let rightNode = teeth[rightID],
                  let leftNode = teeth[leftID] else { continue }
            
            let rightPos = rightNode.worldPosition
            let leftPos = leftNode.worldPosition
            
            let rightDistFromMid = abs(rightPos.x - midlineX)
            let leftDistFromMid = abs(leftPos.x - midlineX)
            let distanceDiff = abs(rightDistFromMid - leftDistFromMid)
            
            if distanceDiff > symmetryTolerance {
                errors.append("\(name): Asymmetric position (\(distanceDiff * 1000)mm)")
            }
            
            let heightDiff = abs(rightPos.y - leftPos.y)
            if heightDiff > symmetryTolerance {
                errors.append("\(name): Asymmetric height (\(heightDiff * 1000)mm)")
            }
            
            if let rightState = states[rightID], let leftState = states[leftID] {
                let scaleDiff = abs(rightState.scale.y - leftState.scale.y)
                if scaleDiff > 0.1 {
                    errors.append("\(name): Asymmetric size")
                }
            }
        }
        
        return (errors.isEmpty, errors)
    }
    
    private func checkArchIntegrity(
        teeth: [String: SCNNode],
        states: [String: ToothState],
        landmarks: [LandmarkType: SCNVector3]
    ) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        guard let leftCanine = teeth["T_3_L"],
              let rightCanine = teeth["T_3_R"] else {
            errors.append("Canines not found")
            return (false, errors)
        }
        
        let leftPos = leftCanine.worldPosition
        let rightPos = rightCanine.worldPosition
        let archWidth = abs(rightPos.x - leftPos.x)
        
        if !DentalConstraints.archWidthRange.contains(archWidth) {
            errors.append("Arch width out of range: \(archWidth * 1000)mm (expected 25-45mm)")
        }
        
        let orderedTeeth = [
            "T_3_L", "T_2_L", "T_1_L", "T_1_R", "T_2_R", "T_3_R"
        ]
        
        for i in 0..<(orderedTeeth.count - 1) {
            guard let tooth1 = teeth[orderedTeeth[i]],
                  let tooth2 = teeth[orderedTeeth[i + 1]] else { continue }
            
            let distance = (tooth2.worldPosition - tooth1.worldPosition).length
            
            if distance < DentalConstraints.minProximalDistance {
                errors.append("Teeth too close: \(orderedTeeth[i]) - \(orderedTeeth[i+1])")
            }
            
            if distance > 0.02 {
                errors.append("Excessive gap: \(orderedTeeth[i]) - \(orderedTeeth[i+1])")
            }
        }
        
        return (errors.isEmpty, errors)
    }
}
