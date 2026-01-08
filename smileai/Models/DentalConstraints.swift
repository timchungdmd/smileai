//
//  DentalConstraingts.swift
//  smileai
//
//  Created by Tim Chung on 1/7/26.
//

import Foundation
import SceneKit

struct DentalConstraints {
    // Inter-tooth spacing (meters)
    static let minContactArea: Float = 0.0001 // 0.1mm²
    static let maxOverlap: Float = 0.0 // No interpenetration allowed
    static let minProximalDistance: Float = 0.0002 // 0.2mm minimum gap
    
    // Angulation limits (degrees relative to occlusal plane)
    static let maxInclination: Float = 15.0
    static let maxRotation: Float = 30.0
    static let maxTip: Float = 10.0
    
    // Arch dimensional constraints (meters)
    static let archWidthRange: ClosedRange<Float> = 0.025...0.045 // 25-45mm
    static let archDepthRange: ClosedRange<Float> = 0.015...0.030 // 15-30mm
    
    // Tooth size ratios (Golden Proportion)
    static let centralToLateralRatio: Float = 0.618
    static let lateralToCanineRatio: Float = 0.618
    
    // Spee curve parameters
    static let speeDepthRange: ClosedRange<Float> = 0.0005...0.0025 // 0.5-2.5mm
}

struct SnapSettings {
    var gridSize: Float = 0.001 // 1mm
    var angleStep: Float = 5.0 // degrees
    var enableProximitySnap: Bool = true
    var snapTolerance: Float = 0.0005 // 0.5mm
    var enabled: Bool = true
}

extension ToothState {
    mutating func applySnapping(_ settings: SnapSettings) {
        guard settings.enabled else { return }
        
        // Position snapping
        position.x = round(position.x / settings.gridSize) * settings.gridSize
        position.y = round(position.y / settings.gridSize) * settings.gridSize
        position.z = round(position.z / settings.gridSize) * settings.gridSize
        
        // Rotation snapping (convert to degrees, snap, convert back)
        let angleRad = settings.angleStep * .pi / 180.0
        rotation.w = round(rotation.w / angleRad) * angleRad
    }
}
