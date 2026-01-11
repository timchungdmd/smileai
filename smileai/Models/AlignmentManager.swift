import Foundation
import SwiftUI
import SceneKit
import Combine // FIX: Added Combine to resolve ObservableObject errors

class AlignmentManager: ObservableObject {
    
    struct CorrespondencePair: Identifiable {
        let id = UUID()
        var index: Int
        var point2D: CGPoint?      // For Photo (X, Y)
        var point3D: SCNVector3?   // For Model (X, Y, Z)
        
        // For 3D-3D alignment (Source vs Target)
        var target3D: SCNVector3?
        
        var isComplete: Bool {
            return (point2D != nil || target3D != nil) && point3D != nil
        }
    }
    
    enum AlignmentType {
        case photoToModel  // Align 3D Model to 2D Photo
        case modelToModel  // Align 3D Model to another 3D Model
    }
    
    @Published var pairs: [CorrespondencePair] = []
    @Published var activePairIndex: Int = 0
    @Published var alignmentType: AlignmentType = .photoToModel
    
    // MARK: - Actions
    
    init() {
        reset()
    }
    
    func reset() {
        pairs = []
        // Start with 3 required points
        for i in 1...3 {
            pairs.append(CorrespondencePair(index: i))
        }
        activePairIndex = 0
    }
    
    func addPair() {
        let nextIndex = pairs.count + 1
        pairs.append(CorrespondencePair(index: nextIndex))
    }
    
    // Call this when user taps on the 2D Photo
    func registerPoint2D(_ point: CGPoint) {
        guard activePairIndex < pairs.count else { return }
        pairs[activePairIndex].point2D = point
        checkAutoAdvance()
    }
    
    // Call this when user clicks on the 3D Model
    func registerPoint3D(_ point: SCNVector3) {
        guard activePairIndex < pairs.count else { return }
        pairs[activePairIndex].point3D = point
        checkAutoAdvance()
    }
    
    private func checkAutoAdvance() {
        if pairs[activePairIndex].isComplete {
            if activePairIndex < pairs.count - 1 {
                activePairIndex += 1
            }
        }
    }
    
    // MARK: - Calculation
    
    func performAlignment(on node: SCNNode, in view: SCNView) {
        let validPairs = pairs.filter { $0.isComplete }
        guard validPairs.count >= 3 else { return }
        
        // 1. Get Source Points (The points on the model we want to move)
        let modelPoints = validPairs.compactMap { $0.point3D }
        
        var transformMatrix: SCNMatrix4?
        
        if alignmentType == .photoToModel {
            // 2D -> 3D Alignment
            let screenPoints = validPairs.compactMap { $0.point2D }
            transformMatrix = AlignmentUtils.align3DTo2D(
                modelPoints: modelPoints,
                screenPoints: screenPoints,
                in: view
            )
        } else {
            // 3D -> 3D Alignment (Kabsch)
            let targetPoints = validPairs.compactMap { $0.target3D }
            if !targetPoints.isEmpty {
                transformMatrix = AlignmentUtils.calculateRigidBodyTransform(
                    from: modelPoints,
                    to: targetPoints
                )
            }
        }
        
        // 2. Apply Transform
        if let matrix = transformMatrix {
            let current = node.transform
            // Apply new transform ON TOP of existing
            node.transform = SCNMatrix4Mult(current, matrix)
        }
    }
}
