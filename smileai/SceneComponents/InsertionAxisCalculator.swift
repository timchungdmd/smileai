//
//  InsertionAxisCalculator.swift
//  smileai
//
//  Calculates optimal insertion axis for prosthetic crowns
//

import Foundation
import SceneKit
import simd

// MARK: - Insertion Axis Result

struct InsertionAxis {
    var direction: SCNVector3    // Unit vector representing insertion path
    var angle: Float             // Angle from vertical (radians)
    var clearance: Float         // Minimum clearance distance (meters)
    var score: Float             // Quality score (0-1, higher is better)
    
    var isViable: Bool {
        clearance > 0.0001 && angle < (45.0 * Float.pi / 180.0) // Max 45° from vertical
    }
    
    /// Convert to rotation quaternion for crown alignment
    func toRotation() -> SCNVector4 {
        let vertical = SCNVector3(0, 1, 0)
        let axis = vertical.cross(direction).normalized
        let angle = acos(vertical.dot(direction))
        
        return SCNVector4(axis.x, axis.y, axis.z, CGFloat(angle))
    }
}

// MARK: - Insertion Axis Calculator

class InsertionAxisCalculator {
    
    // MARK: - Configuration
    
    struct Config {
        var angularResolution: Float = 5.0  // Degrees per sample
        var maxDeviationAngle: Float = 45.0 // Max angle from vertical (degrees)
        var minClearance: Float = 0.0002    // 0.2mm minimum clearance
        var sampleDensity: Int = 50         // Points to test per axis
    }
    
    private let config: Config
    
    init(config: Config = Config()) {
        self.config = config
    }
    
    // MARK: - Main Calculation
    
    /// Calculate optimal insertion axis for crown relative to preparation
    func calculateInsertionAxis(
        crown: SCNNode,
        preparation: SCNNode,
        adjacentTeeth: [SCNNode] = []
    ) -> InsertionAxis? {
        
        // Generate candidate axes
        let candidates = generateCandidateAxes()
        
        var bestAxis: InsertionAxis?
        var bestScore: Float = 0.0
        
        for direction in candidates {
            // Test this axis
            if let axis = evaluateAxis(
                direction: direction,
                crown: crown,
                preparation: preparation,
                obstacles: adjacentTeeth
            ) {
                if axis.score > bestScore && axis.isViable {
                    bestScore = axis.score
                    bestAxis = axis
                }
            }
        }
        
        return bestAxis
    }
    
    // MARK: - Candidate Generation
    
    /// Generate spherical sample of potential insertion directions
    private func generateCandidateAxes() -> [SCNVector3] {
        var axes: [SCNVector3] = []
        
        let angularStep = config.angularResolution * Float.pi / 180.0
        let maxAngle = config.maxDeviationAngle * Float.pi / 180.0
        
        // Spherical sampling around vertical axis
        let thetaSteps = Int(maxAngle / angularStep)
        let phiSteps = Int((2.0 * Float.pi) / angularStep)
        
        for i in 0...thetaSteps {
            let theta = Float(i) * angularStep // Polar angle from vertical
            
            for j in 0..<phiSteps {
                let phi = Float(j) * angularStep // Azimuthal angle
                
                // Spherical to Cartesian
                let x = sin(theta) * cos(phi)
                let y = cos(theta) // Vertical component
                let z = sin(theta) * sin(phi)
                
                let direction = SCNVector3(x, y, z).normalized
                axes.append(direction)
            }
        }
        
        return axes
    }
    
    // MARK: - Axis Evaluation
    
    /// Test a single insertion axis candidate
    private func evaluateAxis(
        direction: SCNVector3,
        crown: SCNNode,
        preparation: SCNNode,
        obstacles: [SCNNode]
    ) -> InsertionAxis? {
        
        // 1. Calculate clearance by sweeping crown along axis
        let clearance = calculateClearance(
            crown: crown,
            direction: direction,
            obstacles: obstacles
        )
        
        guard clearance >= config.minClearance else {
            return nil // Insufficient clearance
        }
        
        // 2. Check if crown can reach preparation
        let canReachPrep = testReachability(
            crown: crown,
            preparation: preparation,
            direction: direction
        )
        
        guard canReachPrep else {
            return nil
        }
        
        // 3. Calculate angle from vertical
        let vertical = SCNVector3(0, 1, 0)
        let angle = acos(direction.dot(vertical))
        
        // 4. Calculate score
        let score = calculateAxisScore(
            angle: angle,
            clearance: clearance,
            direction: direction
        )
        
        return InsertionAxis(
            direction: direction,
            angle: angle,
            clearance: clearance,
            score: score
        )
    }
    
    // MARK: - Clearance Calculation
    
    /// Calculate minimum clearance when moving crown along axis
    private func calculateClearance(
        crown: SCNNode,
        direction: SCNVector3,
        obstacles: [SCNNode]
    ) -> Float {
        
        var minClearance: Float = .infinity
        
        // Sample points along crown surface
        let crownPoints = sampleSurfacePoints(crown)
        
        // Test each point against obstacles
        for point in crownPoints {
            let worldPoint = crown.convertPosition(point, to: nil)
            
            for obstacle in obstacles {
                let obstacleDist = distanceToNode(
                    from: worldPoint,
                    to: obstacle,
                    alongDirection: direction
                )
                
                minClearance = min(minClearance, obstacleDist)
            }
        }
        
        return minClearance
    }
    
    /// Sample points on crown surface
    private func sampleSurfacePoints(_ node: SCNNode) -> [SCNVector3] {
        guard let geometry = node.geometry,
              let vertexSource = geometry.sources(for: .vertex).first else {
            return []
        }
        
        var points: [SCNVector3] = []
        let vertexCount = vertexSource.vectorCount
        let sampleCount = min(config.sampleDensity, vertexCount)
        let step = max(1, vertexCount / sampleCount)
        
        vertexSource.data.withUnsafeBytes { buffer in
            let dataStride = vertexSource.dataStride
            let offset = vertexSource.dataOffset
            
            for i in stride(from: 0, to: vertexCount, by: step) {
                let index = i * dataStride + offset
                let x = buffer.load(fromByteOffset: index, as: Float.self)
                let y = buffer.load(fromByteOffset: index + 4, as: Float.self)
                let z = buffer.load(fromByteOffset: index + 8, as: Float.self)
                
                points.append(SCNVector3(x, y, z))
            }
        }
        
        return points
    }
    
    /// Calculate distance from point to node surface along direction
    private func distanceToNode(
        from point: SCNVector3,
        to node: SCNNode,
        alongDirection direction: SCNVector3
    ) -> Float {
        
        // Simplified: use bounding box distance
        let bounds = node.boundingBox
        let worldMin = node.convertPosition(bounds.min, to: nil)
        let worldMax = node.convertPosition(bounds.max, to: nil)
        
        // Simple AABB distance (could be refined with actual mesh intersection)
        let centerX = (worldMin.x + worldMax.x) / 2
        let centerY = (worldMin.y + worldMax.y) / 2
        let centerZ = (worldMin.z + worldMax.z) / 2
        
        let center = SCNVector3(centerX, centerY, centerZ)
        let distance = (point - center).length
        
        return max(0, distance - 0.005) // Subtract approximate node radius
    }
    
    // MARK: - Reachability Test
    
    /// Check if crown can reach preparation along axis without collision
    private func testReachability(
        crown: SCNNode,
        preparation: SCNNode,
        direction: SCNVector3
    ) -> Bool {
        
        // Get crown and prep centers
        let crownCenter = crown.worldPosition
        let prepCenter = preparation.worldPosition
        
        // Project movement along direction
        let movement = prepCenter - crownCenter
        let projectedLength = movement.dot(direction)
        
        // Must move "downward" (positive projection along insertion axis)
        guard projectedLength > 0 else {
            return false
        }
        
        // Check if final position is within prep bounds (simplified)
        let prepBounds = preparation.boundingBox
        let prepHeight = Float(prepBounds.max.y - prepBounds.min.y)
        
        // Crown must fit within preparation height tolerance
        let tolerance: Float = 0.002 // 2mm
        return projectedLength < prepHeight + tolerance
    }
    
    // MARK: - Scoring
    
    /// Calculate quality score for insertion axis
    private func calculateAxisScore(
        angle: Float,
        clearance: Float,
        direction: SCNVector3
    ) -> Float {
        
        var score: Float = 0.0
        
        // 1. Angle score (prefer vertical insertion)
        let maxAngleRad = config.maxDeviationAngle * Float.pi / 180.0
        let angleScore = 1.0 - (angle / maxAngleRad)
        score += angleScore * 0.5
        
        // 2. Clearance score (more clearance is better)
        let clearanceScore = min(1.0, clearance / 0.002) // Normalize to 2mm
        score += clearanceScore * 0.3
        
        // 3. Simplicity score (prefer cardinal directions)
        let vertical = SCNVector3(0, 1, 0)
        let alignmentScore = abs(direction.dot(vertical)) // 1.0 if perfectly vertical
        score += alignmentScore * 0.2
        
        return score
    }
}

// MARK: - Integration with Tooth Library

extension ToothLibraryManager {
    
    /// Instantiate tooth with optimal insertion axis
    func instantiateWithInsertionAxis(
        type: ToothType,
        preparation: SCNNode,
        adjacentTeeth: [SCNNode] = []
    ) -> (node: SCNNode, axis: InsertionAxis)? {
        
        guard let crown = self.instantiateTooth(type: type) else {
            return nil
        }
        
        let calculator = InsertionAxisCalculator()
        
        guard let axis = calculator.calculateInsertionAxis(
            crown: crown,
            preparation: preparation,
            adjacentTeeth: adjacentTeeth
        ) else {
            return nil
        }
        
        // Apply rotation to align crown with insertion axis
        let rotation = axis.toRotation()
        crown.rotation = rotation
        
        return (crown, axis)
    }
}
