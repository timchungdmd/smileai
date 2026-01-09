//
//  OcclusalAlignmentEngine.swift
//  smileai
//
//  Automatic occlusal alignment for crown placement
//

import Foundation
import SceneKit
import simd

// MARK: - Occlusal Contact Point

struct OcclusalContact {
    var position: SCNVector3      // 3D contact location
    var normal: SCNVector3        // Surface normal at contact
    var penetrationDepth: Float   // How deep the contact is
    var contactArea: Float        // Estimated contact area (mm²)
    
    var isValid: Bool {
        contactArea > 0.0001 && penetrationDepth < 0.001 // Max 1mm penetration
    }
}

// MARK: - Alignment Result

struct AlignmentResult {
    var adjustedPosition: SCNVector3
    var adjustedRotation: SCNVector4
    var contacts: [OcclusalContact]
    var score: Float // Quality metric (0-1, higher is better)
    
    var isAcceptable: Bool {
        score > 0.7 && contacts.count >= 2
    }
}

// MARK: - Occlusal Alignment Engine

class OcclusalAlignmentEngine {
    
    // MARK: - Configuration
    
    struct Config {
        var maxIterations: Int = 50
        var convergenceThreshold: Float = 0.0001 // 0.1mm
        var rayDensity: Int = 20 // Rays per crown surface
        var targetContactCount: Int = 3 // Ideal number of contact points
        var maxPenetration: Float = 0.0005 // 0.5mm max allowed penetration
    }
    
    private let config: Config
    
    init(config: Config = Config()) {
        self.config = config
    }
    
    // MARK: - Main Alignment Method
    
    /// Automatically align crown to antagonist arch
    func alignToAntagonist(
        crown: SCNNode,
        antagonist: SCNNode,
        occlusalPlane: OcclusalPlane? = nil
    ) -> AlignmentResult {
        
        // 1. Initial positioning based on occlusal plane
        if let plane = occlusalPlane {
            positionRelativeToPlane(crown, plane: plane)
        }
        
        // 2. Ray-cast from crown to antagonist to find contacts
        var contacts = detectContacts(crown: crown, antagonist: antagonist)
        
        // 3. Iterative optimization
        var currentPos = crown.position
        var currentRot = SCNVector4(0, 1, 0, 0)
        var bestScore: Float = 0.0
        
        for iteration in 0..<config.maxIterations {
            // Calculate current score
            let score = evaluateAlignment(contacts: contacts)
            
            if score > bestScore {
                bestScore = score
            }
            
            // Check convergence
            if contacts.allSatisfy({ $0.isValid }) && contacts.count >= config.targetContactCount {
                break
            }
            
            // Adjust position based on contact penetration
            let adjustment = calculateAdjustment(from: contacts)
            
            if adjustment.length < config.convergenceThreshold {
                break // Converged
            }
            
            // Apply adjustment
            currentPos = currentPos + adjustment
            crown.position = currentPos
            
            // Re-detect contacts
            contacts = detectContacts(crown: crown, antagonist: antagonist)
        }
        
        return AlignmentResult(
            adjustedPosition: currentPos,
            adjustedRotation: currentRot,
            contacts: contacts,
            score: bestScore
        )
    }
    
    // MARK: - Contact Detection
    
    /// Cast rays from crown surface toward antagonist
    private func detectContacts(crown: SCNNode, antagonist: SCNNode) -> [OcclusalContact] {
        var contacts: [OcclusalContact] = []
        
        // Get crown geometry
        guard let crownGeo = crown.geometry else { return contacts }
        
        // Sample points on occlusal surface (top 20% of crown)
        let samplePoints = sampleOcclusalSurface(crown)
        
        for point in samplePoints {
            // Cast ray downward (negative Y)
            let worldPoint = crown.convertPosition(point, to: nil)
            let direction = SCNVector3(0, -1, 0) // Downward
            
            // Perform hit test
            if let hit = raycastToNode(
                from: worldPoint,
                direction: direction,
                target: antagonist
            ) {
                // Calculate contact properties
                let penetration = Float((worldPoint - hit.position).length)
                
                // Estimate contact area (simplified as circular region)
                let contactRadius: Float = 0.0005 // 0.5mm default
                let area = Float.pi * contactRadius * contactRadius
                
                let contact = OcclusalContact(
                    position: hit.position,
                    normal: hit.normal,
                    penetrationDepth: penetration,
                    contactArea: area
                )
                
                contacts.append(contact)
            }
        }
        
        return contacts
    }
    
    // MARK: - Surface Sampling
    
    /// Extract sample points from occlusal (top) surface of crown
    private func sampleOcclusalSurface(_ crown: SCNNode) -> [SCNVector3] {
        guard let geometry = crown.geometry,
              let vertexSource = geometry.sources(for: .vertex).first else {
            return []
        }
        
        var samples: [SCNVector3] = []
        let vertexCount = vertexSource.vectorCount
        
        // Extract all vertices
        var vertices: [SCNVector3] = []
        vertexSource.data.withUnsafeBytes { buffer in
            let dataStride = vertexSource.dataStride
            let offset = vertexSource.dataOffset
            
            for i in 0..<vertexCount {
                let index = i * dataStride + offset
                let x = buffer.load(fromByteOffset: index, as: Float.self)
                let y = buffer.load(fromByteOffset: index + 4, as: Float.self)
                let z = buffer.load(fromByteOffset: index + 8, as: Float.self)
                
                vertices.append(SCNVector3(x, y, z))
            }
        }
        
        // Find top 20% by Y coordinate (occlusal surface)
        let sortedByHeight = vertices.sorted { Float($0.y) > Float($1.y) }
        let topCount = max(config.rayDensity, vertexCount / 5)
        
        samples = Array(sortedByHeight.prefix(topCount))
        
        return samples
    }
    
    // MARK: - Raycasting
    
    private struct HitResult {
        var position: SCNVector3
        var normal: SCNVector3
    }
    
    /// Cast ray from origin in direction, check intersection with target node
    private func raycastToNode(
        from origin: SCNVector3,
        direction: SCNVector3,
        target: SCNNode
    ) -> HitResult? {
        
        // Create far point for ray
        let rayLength: Float = 0.1 // 100mm max search distance
        let endpoint = SCNVector3(
            origin.x + direction.x * CGFloat(rayLength),
            origin.y + direction.y * CGFloat(rayLength),
            origin.z + direction.z * CGFloat(rayLength)
        )
        
        // Perform hit test on target geometry
        guard let scene = target.scene else { return nil }
        
        // Manual intersection test (SceneKit's hitTest requires a view)
        // Simplified: check bounding box intersection
        let targetBounds = target.boundingBox
        
        // Check if ray intersects AABB
        if let intersection = rayAABBIntersection(
            rayOrigin: origin,
            rayDir: direction,
            boxMin: targetBounds.min,
            boxMax: targetBounds.max,
            transform: target.worldTransform
        ) {
            // Estimate normal (simplified as upward for antagonist)
            let normal = SCNVector3(0, 1, 0)
            
            return HitResult(position: intersection, normal: normal)
        }
        
        return nil
    }
    
    /// Ray-AABB intersection (Axis-Aligned Bounding Box)
    private func rayAABBIntersection(
        rayOrigin: SCNVector3,
        rayDir: SCNVector3,
        boxMin: SCNVector3,
        boxMax: SCNVector3,
        transform: SCNMatrix4
    ) -> SCNVector3? {
        
        // Transform box to world space
        let worldMin = SCNVector3(
            transform.m41 + boxMin.x,
            transform.m42 + boxMin.y,
            transform.m43 + boxMin.z
        )
        let worldMax = SCNVector3(
            transform.m41 + boxMax.x,
            transform.m42 + boxMax.y,
            transform.m43 + boxMax.z
        )
        
        // Slab method for ray-box intersection
        let invDir = SCNVector3(
            1.0 / rayDir.x,
            1.0 / rayDir.y,
            1.0 / rayDir.z
        )
        
        let t1 = (worldMin.x - rayOrigin.x) * invDir.x
        let t2 = (worldMax.x - rayOrigin.x) * invDir.x
        let t3 = (worldMin.y - rayOrigin.y) * invDir.y
        let t4 = (worldMax.y - rayOrigin.y) * invDir.y
        let t5 = (worldMin.z - rayOrigin.z) * invDir.z
        let t6 = (worldMax.z - rayOrigin.z) * invDir.z
        
        let tmin = max(max(min(t1, t2), min(t3, t4)), min(t5, t6))
        let tmax = min(min(max(t1, t2), max(t3, t4)), max(t5, t6))
        
        // No intersection if tmax < 0 or tmin > tmax
        guard tmax >= 0 && tmin <= tmax else { return nil }
        
        let t = tmin > 0 ? tmin : tmax
        
        return SCNVector3(
            rayOrigin.x + rayDir.x * t,
            rayOrigin.y + rayDir.y * t,
            rayOrigin.z + rayDir.z * t
        )
    }
    
    // MARK: - Position Adjustment
    
    /// Calculate position adjustment based on contact penetration
    private func calculateAdjustment(from contacts: [OcclusalContact]) -> SCNVector3 {
        guard !contacts.isEmpty else { return SCNVector3Zero }
        
        // Average penetration vector
        var totalAdjustment = SCNVector3Zero
        var validCount: Float = 0
        
        for contact in contacts {
            if contact.penetrationDepth > config.maxPenetration {
                // Move up to reduce penetration
                let adjustment = contact.normal * contact.penetrationDepth * 0.5
                totalAdjustment = totalAdjustment + adjustment
                validCount += 1
            }
        }
        
        guard validCount > 0 else { return SCNVector3Zero }
        
        // Average
        return totalAdjustment / validCount
    }
    
    /// Position crown relative to occlusal plane
    private func positionRelativeToPlane(_ crown: SCNNode, plane: OcclusalPlane) {
        // Align crown's occlusal surface to plane
        let targetY = Float(plane.origin.y + 0.002) // 2mm above plane
        crown.position.y = CGFloat(targetY)
        
        // Rotate to align with plane normal (simplified)
        // In production, use quaternion rotation to align crown normal to plane normal
    }
    
    // MARK: - Scoring
    
    /// Evaluate alignment quality (0-1 score)
    private func evaluateAlignment(contacts: [OcclusalContact]) -> Float {
        guard !contacts.isEmpty else { return 0.0 }
        
        var score: Float = 0.0
        let validContacts = contacts.filter { $0.isValid }
        
        // 1. Contact count score (ideal: 3 contacts)
        let contactScore = min(Float(validContacts.count) / Float(config.targetContactCount), 1.0)
        score += contactScore * 0.4
        
        // 2. Penetration score (less penetration is better)
        let avgPenetration = validContacts.map { $0.penetrationDepth }.reduce(0, +) / Float(validContacts.count)
        let penetrationScore = max(0, 1.0 - (avgPenetration / config.maxPenetration))
        score += penetrationScore * 0.3
        
        // 3. Distribution score (contacts should be spread out)
        let distributionScore = calculateDistributionScore(validContacts)
        score += distributionScore * 0.3
        
        return score
    }
    
    /// Calculate how well contacts are distributed (avoid clustering)
    private func calculateDistributionScore(_ contacts: [OcclusalContact]) -> Float {
        guard contacts.count >= 2 else { return 0.0 }
        
        // Calculate average distance between contacts
        var totalDistance: Float = 0.0
        var pairCount: Float = 0.0
        
        for i in 0..<contacts.count {
            for j in (i+1)..<contacts.count {
                let dist = contacts[i].position.distance(to: contacts[j].position)
                totalDistance += dist
                pairCount += 1
            }
        }
        
        let avgDistance = totalDistance / pairCount
        
        // Ideal average distance: ~5mm between contacts
        let idealDistance: Float = 0.005
        let score = 1.0 - abs(avgDistance - idealDistance) / idealDistance
        
        return max(0, min(1, score))
    }
}

// MARK: - Convenience Extensions

extension ToothLibraryManager {
    
    /// Instantiate tooth with automatic occlusal alignment
    func instantiateWithAlignment(
        type: ToothType,
        antagonist: SCNNode,
        occlusalPlane: OcclusalPlane? = nil
    ) -> (node: SCNNode, alignment: AlignmentResult)? {
        
        guard let crown = self.instantiateTooth(type: type) else {
            return nil
        }
        
        let aligner = OcclusalAlignmentEngine()
        let result = aligner.alignToAntagonist(
            crown: crown,
            antagonist: antagonist,
            occlusalPlane: occlusalPlane
        )
        
        return (crown, result)
    }
}
