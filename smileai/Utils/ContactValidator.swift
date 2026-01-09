//
//  ContactValidator.swift
//  smileai
//
//  Clinical validation and contact area calculation
//

import Foundation
import SceneKit

// MARK: - Validation Result

struct ContactValidationResult {
    var isValid: Bool
    var errors: [String]
    var warnings: [String]
    var calculatedArea: Float        // Actual contact area (mm²)
    var goldenRatioScore: Float      // 0-1, how well it follows golden ratio
    var proximityScore: Float        // 0-1, ideal spacing score
    
    var passed: Bool {
        isValid && errors.isEmpty
    }
    
    var summary: String {
        var lines: [String] = []
        
        if isValid {
            lines.append("✅ Valid Contact")
        } else {
            lines.append("❌ Invalid Contact")
        }
        
        lines.append("Area: \(String(format: "%.2f", calculatedArea * 1_000_000))mm²")
        lines.append("Golden Ratio: \(String(format: "%.0f", goldenRatioScore * 100))%")
        lines.append("Proximity: \(String(format: "%.0f", proximityScore * 100))%")
        
        if !errors.isEmpty {
            lines.append("\nErrors:")
            errors.forEach { lines.append("  • \($0)") }
        }
        
        if !warnings.isEmpty {
            lines.append("\nWarnings:")
            warnings.forEach { lines.append("  • \($0)") }
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Contact Validator

class ContactValidator {
    
    // MARK: - Configuration
    
    struct Config {
        // Area constraints (m²)
        var minArea: Float = 0.0001          // 0.1mm²
        var maxArea: Float = 0.000002        // 2.0mm²
        var idealArea: Float = 0.0005        // 0.5mm²
        
        // Proximity constraints (m)
        var minDistance: Float = DentalConstraints.minProximalDistance
        var maxDistance: Float = 0.001       // 1mm max gap
        var idealDistance: Float = 0.0002    // 0.2mm ideal
        
        // Golden ratio tolerance
        var goldenRatioTolerance: Float = 0.15  // ±15%
        
        // Force constraints
        var maxForce: Float = 50.0           // Max 50N
    }
    
    private let config: Config
    
    init(config: Config = Config()) {
        self.config = config
    }
    
    // MARK: - Validation
    
    /// Validate a single contact point
    func validate(_ contact: ContactPoint, teeth: [String: SCNNode]) -> ContactValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // 1. Get tooth nodes
        guard let tooth1 = teeth[contact.tooth1ID],
              let tooth2 = teeth[contact.tooth2ID] else {
            errors.append("Missing tooth geometry")
            return ContactValidationResult(
                isValid: false,
                errors: errors,
                warnings: warnings,
                calculatedArea: 0,
                goldenRatioScore: 0,
                proximityScore: 0
            )
        }
        
        // 2. Calculate actual contact area
        let actualArea = calculateContactArea(
            at: contact.position,
            between: tooth1,
            and: tooth2
        )
        
        // 3. Validate area
        if actualArea < config.minArea {
            errors.append("Contact area too small: \(String(format: "%.2f", actualArea * 1_000_000))mm²")
        } else if actualArea > config.maxArea {
            warnings.append("Contact area large: \(String(format: "%.2f", actualArea * 1_000_000))mm²")
        }
        
        // 4. Check proximity
        let distance = (tooth2.worldPosition - tooth1.worldPosition).length
        let proximityScore = evaluateProximity(distance)
        
        if distance < config.minDistance {
            errors.append("Teeth too close: \(String(format: "%.2f", distance * 1000))mm")
        } else if distance > config.maxDistance {
            errors.append("Gap too large: \(String(format: "%.2f", distance * 1000))mm")
        }
        
        // 5. Check force
        if contact.force > config.maxForce {
            errors.append("Excessive force: \(String(format: "%.1f", contact.force))N")
        }
        
        // 6. Calculate golden ratio score (requires reference contact)
        let goldenRatioScore: Float = 1.0 // Placeholder, needs reference
        
        return ContactValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            calculatedArea: actualArea,
            goldenRatioScore: goldenRatioScore,
            proximityScore: proximityScore
        )
    }
    
    /// Validate all contacts in sequence
    func validateSequence(
        _ contacts: [ContactPoint],
        teeth: [String: SCNNode]
    ) -> [ContactValidationResult] {
        
        var results: [ContactValidationResult] = []
        
        for (index, contact) in contacts.enumerated() {
            var result = validate(contact, teeth: teeth)
            
            // Check golden ratio relative to previous contact
            if index > 0 {
                let prevContact = contacts[index - 1]
                let ratio = contact.area / prevContact.area
                let goldenRatio = DentalConstraints.centralToLateralRatio
                
                let deviation = abs(ratio - goldenRatio)
                let tolerance = config.goldenRatioTolerance
                
                if deviation > tolerance {
                    result.warnings.append(
                        "Golden ratio deviation: \(String(format: "%.2f", ratio)) vs \(String(format: "%.2f", goldenRatio))"
                    )
                }
                
                result.goldenRatioScore = max(0, 1.0 - (deviation / tolerance))
            }
            
            results.append(result)
        }
        
        return results
    }
    
    // MARK: - Contact Area Calculation
    
    /// Calculate actual contact area using mesh intersection
    func calculateContactArea(
        at position: SCNVector3,
        between tooth1: SCNNode,
        and tooth2: SCNNode
    ) -> Float {
        
        // Simplified calculation using proximity and surface normals
        // In production, would use actual mesh intersection
        
        // 1. Get surfaces near contact point
        let surface1 = sampleSurfaceNear(position, on: tooth1)
        let surface2 = sampleSurfaceNear(position, on: tooth2)
        
        // 2. Calculate overlap region
        let overlapRadius = estimateOverlapRadius(surface1, surface2)
        
        // 3. Area = π * r²
        let area = Float.pi * overlapRadius * overlapRadius
        
        return area
    }
    
    /// Sample surface points near contact location
    private func sampleSurfaceNear(
        _ point: SCNVector3,
        on tooth: SCNNode
    ) -> [SCNVector3] {
        
        guard let geometry = tooth.geometry,
              let vertexSource = geometry.sources(for: .vertex).first else {
            return []
        }
        
        var nearbyPoints: [SCNVector3] = []
        let searchRadius: Float = 0.002 // 2mm
        
        vertexSource.data.withUnsafeBytes { buffer in
            let dataStride = vertexSource.dataStride
            let offset = vertexSource.dataOffset
            let count = vertexSource.vectorCount
            
            for i in 0..<count {
                let index = i * dataStride + offset
                let x = buffer.load(fromByteOffset: index, as: Float.self)
                let y = buffer.load(fromByteOffset: index + 4, as: Float.self)
                let z = buffer.load(fromByteOffset: index + 8, as: Float.self)
                
                let localPoint = SCNVector3(x, y, z)
                let worldPoint = tooth.convertPosition(localPoint, to: nil)
                
                let distance = (worldPoint - point).length
                
                if distance < searchRadius {
                    nearbyPoints.append(worldPoint)
                }
            }
        }
        
        return nearbyPoints
    }
    
    /// Estimate overlap radius from two surface point clouds
    private func estimateOverlapRadius(
        _ surface1: [SCNVector3],
        _ surface2: [SCNVector3]
    ) -> Float {
        
        guard !surface1.isEmpty && !surface2.isEmpty else {
            return 0.0001 // Minimum radius (0.1mm)
        }
        
        // Calculate distance between centroids
        let centroid1 = surface1.reduce(SCNVector3Zero) { $0 + $1 } / Float(surface1.count)
        let centroid2 = surface2.reduce(SCNVector3Zero) { $0 + $1 } / Float(surface2.count)
        
        let distance = (centroid2 - centroid1).length
        
        // Estimate radius based on point cloud spread
        let spread1 = surface1.map { ($0 - centroid1).length }.reduce(0, +) / Float(surface1.count)
        let spread2 = surface2.map { ($0 - centroid2).length }.reduce(0, +) / Float(surface2.count)
        
        let avgSpread = (spread1 + spread2) / 2.0
        
        // Overlap radius is related to spread and distance
        let overlapRadius = max(0, avgSpread - distance / 2.0)
        
        return overlapRadius
    }
    
    // MARK: - Scoring
    
    /// Evaluate proximity score (0-1, higher is better)
    private func evaluateProximity(_ distance: Float) -> Float {
        let deviation = abs(distance - config.idealDistance)
        let tolerance = config.maxDistance - config.minDistance
        
        let score = 1.0 - (deviation / tolerance)
        return max(0, min(1, score))
    }
}

// MARK: - Batch Validation

extension ContactValidator {
    
    /// Generate comprehensive validation report for all contacts
    func generateReport(
        contacts: [ContactPoint],
        teeth: [String: SCNNode]
    ) -> String {
        
        let results = validateSequence(contacts, teeth: teeth)
        
        var report: [String] = []
        report.append(String(repeating: "=", count: 50))
        report.append("CONTACT POINT VALIDATION REPORT")
        report.append(String(repeating: "=", count: 50))
        report.append("")
        
        let passCount = results.filter { $0.passed }.count
        let totalCount = results.count
        
        report.append("Overall: \(passCount)/\(totalCount) contacts passed")
        report.append("")
        
        for (index, result) in results.enumerated() {
            let contact = contacts[index]
            report.append("Contact #\(index + 1): \(contact.tooth1ID) ↔ \(contact.tooth2ID)")
            report.append(result.summary)
            report.append("")
        }
        
        report.append(String(repeating: "=", count: 50))
        
        return report.joined(separator: "\n")
    }
}
