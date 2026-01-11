//
//  AlignmentManager.swift
//  smileai
//
//  ENHANCED: Week 1, Task 1.1 - Auto Field-of-View Calculation
//  Created by Tim Chung on 1/7/26.
//

import Foundation
import SwiftUI
import SceneKit
import Combine
import Vision

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
    
    // MARK: - Published Properties
    
    @Published var pairs: [CorrespondencePair] = []
    @Published var activePairIndex: Int = 0
    @Published var alignmentType: AlignmentType = .photoToModel
    
    // NEW: FOV and Confidence
    @Published var estimatedFOV: Float?
    @Published var registrationConfidence: Float?
    
    // MARK: - Initialization
    
    init() {
        reset()
    }
    
    // MARK: - Actions
    
    func reset() {
        pairs = []
        // Start with 3 required points
        for i in 1...3 {
            pairs.append(CorrespondencePair(index: i))
        }
        activePairIndex = 0
        estimatedFOV = nil
        registrationConfidence = nil
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
    
    // MARK: - ✨ NEW: Auto Field-of-View Calculation (Task 1.1)
    
    /// Automatically estimate field of view from face landmarks
    /// Uses interpupillary distance (IPD) as real-world reference
    func estimateFieldOfView(
        from image: NSImage,
        faceLandmarks: FacialLandmarks
    ) -> Float {
        
        // STEP 1: Get interpupillary distance in pixels
        guard let leftPupil = faceLandmarks.leftPupil,
              let rightPupil = faceLandmarks.rightPupil else {
            print("⚠️ Cannot estimate FOV: Pupil landmarks missing")
            return 0.436 // Fallback: 25° (typical macro photography)
        }
        
        let pixelDistance = calculatePixelDistance(leftPupil, rightPupil)
        
        print("📏 IPD in pixels: \(pixelDistance)")
        
        // STEP 2: Known average IPD in reality = 63mm (scientific average)
        let realWorldIPD: Float = 0.063 // meters
        
        // STEP 3: Calculate pixels per meter
        let pixelsPerMeter = Float(pixelDistance) / realWorldIPD
        
        print("🔢 Pixels per meter: \(pixelsPerMeter)")
        
        // STEP 4: Estimate FOV using typical dental photography specs
        // Most dental photos use:
        // - Macro lens: 85-105mm focal length
        // - Full-frame sensor: 36mm width
        // - Working distance: ~300mm
        
        let focalLength: Float = 90.0      // Average macro lens
        let sensorWidth: Float = 36.0      // Full-frame sensor
        let imageWidth = Float(image.size.width)
        
        // Calculate real-world width of the image
        let realWorldImageWidth = imageWidth / pixelsPerMeter
        
        // FOV calculation (radians):
        // FOV = 2 * atan((realWorldWidth / 2) / focalLength_effective)
        // where focalLength_effective = focalLength * (sensorWidth / imageWidth_sensor)
        
        let focalLengthEffective = focalLength / (sensorWidth / realWorldImageWidth)
        let fov = 2.0 * atan(realWorldImageWidth / (2.0 * focalLengthEffective))
        
        // Convert to degrees for logging
        let fovDegrees = fov * 180.0 / Float.pi
        
        print("✅ Estimated FOV: \(String(format: "%.1f°", fovDegrees)) (\(String(format: "%.3f", fov)) radians)")
        
        // Sanity check: typical dental macro should be 15-35°
        if fovDegrees < 10 || fovDegrees > 50 {
            print("⚠️ FOV outside expected range (10-50°), using fallback")
            return 0.436 // 25° fallback
        }
        
        // Store for later use
        self.estimatedFOV = fov
        
        return fov
    }
    
    /// Helper: Calculate 2D distance between two points
    private func calculatePixelDistance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - ✨ NEW: Auto-Registration with FOV
    
    /// Perform automatic photo-to-scan registration
    /// This will be expanded in Tasks 1.2-1.4
    func performAutoRegistration(
        photo: NSImage,
        photoLandmarks: FacialLandmarks,
        scanURL: URL
    ) async throws -> RegistrationResult {
        
        print("🚀 Starting auto-registration...")
        
        // STEP 1: Estimate FOV
        let fov = estimateFieldOfView(from: photo, faceLandmarks: photoLandmarks)
        
        print("📸 Using FOV: \(String(format: "%.1f°", fov * 180 / .pi))")
        
        // STEP 2: Detect teeth in photo (Task 1.2 - to be implemented)
        // let photoTeeth = try await detectToothCenters(in: photo)
        
        // STEP 3: Detect incisal edges in 3D scan (Task 1.3 - to be implemented)
        // let scanEdges = try await detectIncisalEdges(from: scanURL)
        
        // STEP 4: Match correspondences (Task 1.4 - to be implemented)
        // let correspondences = matchCorrespondences(photoTeeth, scanEdges)
        
        // STEP 5: Solve PnP (Task 1.4 - to be implemented)
        // let transform = solvePnP(correspondences, fov: fov)
        
        // For now, return placeholder result
        let result = RegistrationResult(
            transformMatrix: matrix_float4x4.identity,
            fieldOfView: fov,
            correspondencePoints: [],
            confidence: 0.0,
            method: .automatic
        )
        
        self.registrationConfidence = result.confidence
        
        print("✅ Auto-registration complete (confidence: \(Int(result.confidence * 100))%)")
        
        return result
    }
    
    // MARK: - Manual Alignment (Existing)
    
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

// MARK: - Supporting Types

/// Facial landmarks extracted from Vision framework
struct FacialLandmarks {
    var leftPupil: CGPoint?
    var rightPupil: CGPoint?
    var noseTip: CGPoint?
    var leftMouthCorner: CGPoint?
    var rightMouthCorner: CGPoint?
    var chin: CGPoint?
    
    // Dental-specific landmarks
    var upperLipCenter: CGPoint?
    var lowerLipCenter: CGPoint?
    var leftCanineTip: CGPoint?
    var rightCanineTip: CGPoint?
    
    /// Create from VNFaceObservation
    static func from(_ observation: VNFaceObservation) -> FacialLandmarks? {
        guard let landmarks = observation.landmarks else {
            return nil
        }
        
        var result = FacialLandmarks()
        
        // Extract pupils
        if let leftEye = landmarks.leftPupil?.normalizedPoints.first {
            result.leftPupil = leftEye
        }
        
        if let rightEye = landmarks.rightPupil?.normalizedPoints.first {
            result.rightPupil = rightEye
        }
        
        // Extract nose
        if let nose = landmarks.nose?.normalizedPoints.first {
            result.noseTip = nose
        }
        
        // Extract mouth
        if let outerLips = landmarks.outerLips?.normalizedPoints {
            // Approximate corners (leftmost and rightmost points)
            if let leftCorner = outerLips.min(by: { $0.x < $1.x }) {
                result.leftMouthCorner = leftCorner
            }
            if let rightCorner = outerLips.max(by: { $0.x < $1.x }) {
                result.rightMouthCorner = rightCorner
            }
            
            // Approximate lip centers (topmost and bottommost)
            if let topCenter = outerLips.max(by: { $0.y < $1.y }) {
                result.upperLipCenter = topCenter
            }
            if let bottomCenter = outerLips.min(by: { $0.y < $1.y }) {
                result.lowerLipCenter = bottomCenter
            }
        }
        
        return result
    }
}

/// Registration result with confidence scoring
struct RegistrationResult {
    var transformMatrix: matrix_float4x4
    var fieldOfView: Float
    var correspondencePoints: [(photo: CGPoint, scan: SCNVector3)]
    var confidence: Float  // 0.0 - 1.0
    var method: RegistrationMethod
    
    enum RegistrationMethod {
        case automatic
        case manual
        case hybrid
    }
}

// MARK: - Matrix Extension

extension matrix_float4x4 {
    static var identity: matrix_float4x4 {
        return matrix_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
}
