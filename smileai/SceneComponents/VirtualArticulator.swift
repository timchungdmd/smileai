//
//  VirtualArticulator.swift
//  smileai
//
//  Virtual articulator with dynamic occlusion simulation
//  Competing with exocad Virtual Articulator Module
//

import Foundation
import SceneKit

/// Virtual articulator for dynamic occlusion simulation and jaw movement analysis
class VirtualArticulator {

    // MARK: - Properties

    var settings: ArticulatorSettings
    var upperArchNode: SCNNode?
    var lowerArchNode: SCNNode?

    private var currentPosition: ArticulatorPosition = .intercuspal
    private var movementPath: [ArticulatorPosition] = []

    // MARK: - Initialization

    init(settings: ArticulatorSettings = .default) {
        self.settings = settings
    }

    // MARK: - Articulator Setup

    /// Mount models in virtual articulator
    func mountModels(upperArch: SCNNode, lowerArch: SCNNode, mounting: MountingData) {
        self.upperArchNode = upperArch
        self.lowerArchNode = lowerArch

        // Apply mounting transformation
        applyMountingTransform(to: upperArch, mounting: mounting.upperMounting)
        applyMountingTransform(to: lowerArch, mounting: mounting.lowerMounting)

        // Set initial position to intercuspal
        setPosition(.intercuspal, animated: false)
    }

    private func applyMountingTransform(to node: SCNNode, mounting: MountTransform) {
        node.transform = SCNMatrix4Mult(node.transform, mounting.matrix)
    }

    // MARK: - Jaw Movement Simulation

    /// Simulate jaw movement along a specific path
    func simulateMovement(
        type: MovementType,
        duration: TimeInterval = 2.0,
        completion: ((CollisionReport) -> Void)? = nil
    ) {
        guard lowerArchNode != nil else { return }

        let path = generateMovementPath(type: type)
        movementPath = path

        // Animate through path
        var collisions: [CollisionEvent] = []

        for (index, position) in path.enumerated() {
            let delay = duration * Double(index) / Double(path.count)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.setPosition(position, animated: true)

                // Check for collisions at this position
                if let collision = self.detectCollision(at: position) {
                    collisions.append(collision)
                }

                // Final callback
                if index == path.count - 1 {
                    let report = CollisionReport(
                        movementType: type,
                        collisions: collisions,
                        maxPenetration: collisions.map { $0.penetrationDepth }.max() ?? 0.0,
                        collisionCount: collisions.count
                    )
                    completion?(report)
                }
            }
        }
    }

    /// Generate movement path based on type
    private func generateMovementPath(type: MovementType) -> [ArticulatorPosition] {
        var path: [ArticulatorPosition] = []
        let steps = 60 // 60 frames for smooth animation

        switch type {
        case .protrusion:
            // Forward movement
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let xVal = CGFloat(t * Double(settings.protrusiveGuidance))
                let yVal = CGFloat(-t * Double(settings.condylarAngle) * 0.1)
                let translation = SCNVector3(x: xVal, y: yVal, z: 0)
                let rotation = SCNVector3(x: 0, y: 0, z: 0)
                path.append(ArticulatorPosition(translation: translation, rotation: rotation))
            }

        case .retrusion:
            // Backward movement
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let xVal = CGFloat(-t * 3.0)
                let yVal = CGFloat(-t * Double(settings.condylarAngle) * 0.1)
                let translation = SCNVector3(x: xVal, y: yVal, z: 0)
                let rotation = SCNVector3(x: 0, y: 0, z: 0)
                path.append(ArticulatorPosition(translation: translation, rotation: rotation))
            }

        case .lateralRight:
            // Right lateral movement
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let xVal = CGFloat(t * Double(settings.bennettAngle) * 0.5)
                let zVal = CGFloat(t * 5.0)
                let translation = SCNVector3(x: xVal, y: 0, z: zVal)
                let rotVal = CGFloat(-t * 0.2)
                let rotation = SCNVector3(0, rotVal, 0)
                path.append(ArticulatorPosition(translation: translation, rotation: rotation))
            }

        case .lateralLeft:
            // Left lateral movement
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let xVal = CGFloat(-t * Double(settings.bennettAngle) * 0.5)
                let zVal = CGFloat(t * 5.0)
                let translation = SCNVector3(x: xVal, y: 0, z: zVal)
                let rotVal = CGFloat(t * 0.2)
                let rotation = SCNVector3(0, rotVal, 0)
                path.append(ArticulatorPosition(translation: translation, rotation: rotation))
            }

        case .opening:
            // Opening movement
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let maxOpening = 40.0 // mm
                let xVal = CGFloat(t * 2.0) // Slight forward movement
                let yVal = CGFloat(-t * maxOpening)
                let translation = SCNVector3(x: xVal, y: yVal, z: 0)
                let rotVal = CGFloat(-t * 0.5)
                let rotation = SCNVector3(rotVal, 0, 0) // Rotation around TMJ
                path.append(ArticulatorPosition(translation: translation, rotation: rotation))
            }

        case .closing:
            // Closing movement (reverse of opening)
            let openPath = generateMovementPath(type: .opening)
            path = openPath.reversed()

        case .custom:
            // Custom movement would be set externally
            break
        }

        return path
    }

    /// Set articulator position
    func setPosition(_ position: ArticulatorPosition, animated: Bool) {
        guard let lowerArch = lowerArchNode else { return }

        currentPosition = position

        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.033 // ~30 fps
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)

            applyPosition(position, to: lowerArch)

            SCNTransaction.commit()
        } else {
            applyPosition(position, to: lowerArch)
        }
    }

    private func applyPosition(_ position: ArticulatorPosition, to node: SCNNode) {
        // Apply translation
        node.position = position.translation

        // Apply rotation
        let rotation = position.rotation
        node.eulerAngles = rotation
    }

    // MARK: - Collision Detection

    /// Detect collisions at current position
    func detectCollision(at position: ArticulatorPosition) -> CollisionEvent? {
        guard let upperArch = upperArchNode,
              let lowerArch = lowerArchNode else {
            return nil
        }

        // Get all tooth nodes
        let upperTeeth = getAllToothNodes(from: upperArch)
        let lowerTeeth = getAllToothNodes(from: lowerArch)

        var collisions: [ToothCollision] = []

        // Check each upper tooth against each lower tooth
        for upperTooth in upperTeeth {
            for lowerTooth in lowerTeeth {
                if let collision = checkToothCollision(upper: upperTooth, lower: lowerTooth, position: position) {
                    collisions.append(collision)
                }
            }
        }

        if collisions.isEmpty {
            return nil
        }

        return CollisionEvent(
            position: position,
            toothCollisions: collisions,
            penetrationDepth: collisions.map { $0.penetrationDepth }.max() ?? 0.0,
            timestamp: Date()
        )
    }

    /// Check collision between two teeth
    private func checkToothCollision(
        upper: SCNNode,
        lower: SCNNode,
        position: ArticulatorPosition
    ) -> ToothCollision? {

        // Check that nodes have geometries
        guard upper.geometry != nil,
              lower.geometry != nil else {
            return nil
        }

        // Get bounding boxes in world space
        let upperBBox = upper.boundingBox
        let lowerBBox = lower.boundingBox

        // Convert to world coordinates
        let upperMin = upper.convertPosition(SCNVector3(upperBBox.min.x, upperBBox.min.y, upperBBox.min.z), to: nil)
        let upperMax = upper.convertPosition(SCNVector3(upperBBox.max.x, upperBBox.max.y, upperBBox.max.z), to: nil)
        let lowerMin = lower.convertPosition(SCNVector3(lowerBBox.min.x, lowerBBox.min.y, lowerBBox.min.z), to: nil)
        let lowerMax = lower.convertPosition(SCNVector3(lowerBBox.max.x, lowerBBox.max.y, lowerBBox.max.z), to: nil)

        // Check for bounding box overlap
        if !boxesIntersect(min1: upperMin, max1: upperMax, min2: lowerMin, max2: lowerMax) {
            return nil
        }

        // Detailed collision detection using ray casting
        let penetration = calculatePenetrationDepth(
            upperNode: upper,
            lowerNode: lower,
            position: position
        )

        if penetration > 0.01 { // 0.01mm threshold
            return ToothCollision(
                upperTooth: upper.name ?? "Unknown",
                lowerTooth: lower.name ?? "Unknown",
                penetrationDepth: penetration,
                contactPoint: calculateContactPoint(upper: upper, lower: lower)
            )
        }

        return nil
    }

    /// Calculate penetration depth
    private func calculatePenetrationDepth(
        upperNode: SCNNode,
        lowerNode: SCNNode,
        position: ArticulatorPosition
    ) -> CGFloat {

        // Sample points on upper surface
        let samplePoints = generateSurfaceSamplePoints(for: upperNode, count: 20)

        var maxPenetration: CGFloat = 0.0

        for point in samplePoints {
            let worldPoint = upperNode.convertPosition(point, to: nil)

            // Ray cast downward to check if it intersects lower tooth
            let rayDirection = SCNVector3(0, -1, 0)
            let rayOrigin = worldPoint

            let hitResults = lowerNode.hitTestWithSegment(
                from: rayOrigin,
                to: rayOrigin + rayDirection * 100
            )

            if let hit = hitResults.first {
                let distance = (hit.worldCoordinates - worldPoint).length
                maxPenetration = max(maxPenetration, CGFloat(distance))
            }
        }

        return maxPenetration
    }

    /// Generate sample points on tooth surface
    private func generateSurfaceSamplePoints(for node: SCNNode, count: Int) -> [SCNVector3] {
        var points: [SCNVector3] = []

        let bbox = node.boundingBox
        let min = SCNVector3(bbox.min.x, bbox.min.y, bbox.min.z)
        let max = SCNVector3(bbox.max.x, bbox.max.y, bbox.max.z)

        for _ in 0..<count {
            let x = CGFloat.random(in: min.x...max.x)
            let y = max.y // Sample from top surface
            let z = CGFloat.random(in: min.z...max.z)

            points.append(SCNVector3(x, y, z))
        }

        return points
    }

    /// Calculate contact point between teeth
    private func calculateContactPoint(upper: SCNNode, lower: SCNNode) -> SCNVector3 {
        // Simplified: use center point between bounding boxes
        let upperBBox = upper.boundingBox
        let lowerBBox = lower.boundingBox

        let upperCenter = upper.convertPosition(
            SCNVector3(
                (upperBBox.min.x + upperBBox.max.x) / 2,
                upperBBox.min.y,
                (upperBBox.min.z + upperBBox.max.z) / 2
            ),
            to: nil
        )

        let lowerCenter = lower.convertPosition(
            SCNVector3(
                (lowerBBox.min.x + lowerBBox.max.x) / 2,
                lowerBBox.max.y,
                (lowerBBox.min.z + lowerBBox.max.z) / 2
            ),
            to: nil
        )

        return (upperCenter + lowerCenter) * 0.5
    }

    /// Check if two bounding boxes intersect
    private func boxesIntersect(
        min1: SCNVector3,
        max1: SCNVector3,
        min2: SCNVector3,
        max2: SCNVector3
    ) -> Bool {
        return (min1.x <= max2.x && max1.x >= min2.x) &&
               (min1.y <= max2.y && max1.y >= min2.y) &&
               (min1.z <= max2.z && max1.z >= min2.z)
    }

    // MARK: - Helper Methods

    /// Get all tooth nodes from arch
    private func getAllToothNodes(from archNode: SCNNode) -> [SCNNode] {
        var teeth: [SCNNode] = []

        archNode.enumerateChildNodes { node, _ in
            if node.geometry != nil && (node.name?.contains("tooth") ?? false || node.name?.contains("Tooth") ?? false) {
                teeth.append(node)
            }
        }

        return teeth
    }

    // MARK: - Analysis

    /// Analyze occlusion and generate report
    func analyzeOcclusion() -> OcclusalAnalysisReport {
        var reports: [MovementReport] = []

        let movements: [MovementType] = [.protrusion, .retrusion, .lateralRight, .lateralLeft]

        for movement in movements {
            let path = generateMovementPath(type: movement)
            var collisions: [CollisionEvent] = []

            for position in path {
                if let collision = detectCollision(at: position) {
                    collisions.append(collision)
                }
            }

            let report = MovementReport(
                type: movement,
                collisionCount: collisions.count,
                maxPenetration: collisions.map { $0.penetrationDepth }.max() ?? 0.0,
                problematicPhases: identifyProblematicPhases(collisions: collisions)
            )

            reports.append(report)
        }

        return OcclusalAnalysisReport(
            timestamp: Date(),
            movementReports: reports,
            overallScore: calculateOcclusalScore(from: reports),
            recommendations: generateRecommendations(from: reports)
        )
    }

    /// Identify problematic phases in movement
    private func identifyProblematicPhases(collisions: [CollisionEvent]) -> [String] {
        var phases: [String] = []

        if collisions.count > 10 {
            phases.append("Excessive collision throughout movement")
        }

        let maxPenetration = collisions.map { $0.penetrationDepth }.max() ?? 0.0
        if maxPenetration > 0.5 {
            phases.append("Severe penetration detected (>\(String(format: "%.2f", maxPenetration))mm)")
        }

        return phases
    }

    /// Calculate overall occlusal score
    private func calculateOcclusalScore(from reports: [MovementReport]) -> Double {
        let totalCollisions = reports.reduce(0) { $0 + $1.collisionCount }
        let maxPenetration = reports.map { $0.maxPenetration }.max() ?? 0.0

        // Perfect score = 100, deduct for issues
        var score = 100.0

        // Deduct for collisions
        score -= Double(totalCollisions) * 2.0

        // Deduct for penetration
        score -= Double(maxPenetration) * 20.0

        return max(score, 0.0)
    }

    /// Generate recommendations
    private func generateRecommendations(from reports: [MovementReport]) -> [String] {
        var recommendations: [String] = []

        for report in reports {
            if report.collisionCount > 5 {
                recommendations.append("Adjust \(report.type.rawValue) movement to reduce collisions")
            }

            if report.maxPenetration > 0.3 {
                recommendations.append("Critical penetration in \(report.type.rawValue) - modify tooth morphology")
            }
        }

        if recommendations.isEmpty {
            recommendations.append("Occlusion appears acceptable")
        }

        return recommendations
    }
}

// MARK: - Supporting Types

struct ArticulatorSettings {
    var condylarAngle: CGFloat // degrees
    var bennettAngle: CGFloat // degrees
    var bennettShift: CGFloat // mm
    var protrusiveGuidance: CGFloat // mm
    var tmjDistance: CGFloat // mm (distance between condyles)

    static let `default` = ArticulatorSettings(
        condylarAngle: 30.0,
        bennettAngle: 15.0,
        bennettShift: 0.5,
        protrusiveGuidance: 10.0,
        tmjDistance: 110.0
    )
}

struct MountingData {
    var upperMounting: MountTransform
    var lowerMounting: MountTransform
}

struct MountTransform {
    var matrix: SCNMatrix4

    static let identity = MountTransform(matrix: SCNMatrix4Identity)
}

struct ArticulatorPosition {
    var translation: SCNVector3
    var rotation: SCNVector3

    static let intercuspal = ArticulatorPosition(
        translation: SCNVector3(0, 0, 0),
        rotation: SCNVector3(0, 0, 0)
    )
}

enum MovementType: String {
    case protrusion = "Protrusion"
    case retrusion = "Retrusion"
    case lateralRight = "Lateral Right"
    case lateralLeft = "Lateral Left"
    case opening = "Opening"
    case closing = "Closing"
    case custom = "Custom"
}

struct CollisionEvent {
    var position: ArticulatorPosition
    var toothCollisions: [ToothCollision]
    var penetrationDepth: CGFloat
    var timestamp: Date
}

struct ToothCollision {
    var upperTooth: String
    var lowerTooth: String
    var penetrationDepth: CGFloat
    var contactPoint: SCNVector3
}

struct CollisionReport {
    var movementType: MovementType
    var collisions: [CollisionEvent]
    var maxPenetration: CGFloat
    var collisionCount: Int

    var severity: CollisionSeverity {
        if maxPenetration > 0.5 {
            return .severe
        } else if maxPenetration > 0.2 {
            return .moderate
        } else if collisionCount > 0 {
            return .mild
        } else {
            return .none
        }
    }
}

enum CollisionSeverity: String {
    case none = "No Collision"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
}

struct MovementReport {
    var type: MovementType
    var collisionCount: Int
    var maxPenetration: CGFloat
    var problematicPhases: [String]
}

struct OcclusalAnalysisReport {
    var timestamp: Date
    var movementReports: [MovementReport]
    var overallScore: Double
    var recommendations: [String]
}
