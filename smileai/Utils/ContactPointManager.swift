//
//  ContactPointManager.swift
//  smileai
//
//  Interactive contact point management for proximal tooth surfaces
//

import Foundation
import SceneKit
import Combine

// MARK: - Contact Point Model

class ContactPoint: ObservableObject, Identifiable {
    let id = UUID()
    
    @Published var position: SCNVector3
    @Published var normal: SCNVector3
    @Published var area: Float              // Contact area in mm²
    @Published var force: Float             // Spring force for optimization (N)
    
    let tooth1ID: String
    let tooth2ID: String
    
    // Visual node in scene
    var visualNode: SCNNode?
    
    init(
        position: SCNVector3,
        normal: SCNVector3 = SCNVector3(0, 1, 0),
        area: Float = 0.5,
        tooth1: String,
        tooth2: String
    ) {
        self.position = position
        self.normal = normal
        self.area = area
        self.force = 0.0
        self.tooth1ID = tooth1
        self.tooth2ID = tooth2
    }
    
    // MARK: - Validation
    
    var isValid: Bool {
        area >= DentalConstraints.minContactArea &&
        area <= 2.0 && // Max 2mm² for typical contacts
        force < 50.0    // Max 50N force (physiological limit)
    }
    
    func validate() -> [String] {
        var errors: [String] = []
        
        if area < DentalConstraints.minContactArea {
            errors.append("Contact area too small: \(String(format: "%.2f", area * 1_000_000))mm²")
        }
        
        if area > 2.0 {
            errors.append("Contact area too large: \(String(format: "%.2f", area * 1_000_000))mm²")
        }
        
        if force > 50.0 {
            errors.append("Excessive contact force: \(String(format: "%.1f", force))N")
        }
        
        return errors
    }
    
    // MARK: - Golden Proportion Check
    
    /// Check if contact follows golden ratio relative to reference
    func checkGoldenProportion(reference: ContactPoint) -> Bool {
        let ratio = area / reference.area
        let goldenRatio = DentalConstraints.centralToLateralRatio
        
        // Allow 10% tolerance
        let tolerance: Float = 0.1
        return abs(ratio - goldenRatio) < tolerance
    }
}

// MARK: - Contact Point Manager

@MainActor
class ContactPointManager: ObservableObject {
    
    @Published private(set) var contactPoints: [ContactPoint] = []
    @Published var selectedContactID: UUID?
    @Published var isEditing: Bool = false
    
    private weak var sceneRootNode: SCNNode?
    
    // Visualization settings
    private let contactSphereRadius: CGFloat = 0.001 // 1mm sphere
    
    init() {}
    
    func setup(in sceneRoot: SCNNode) {
        self.sceneRootNode = sceneRoot
    }
    
    // MARK: - Contact Management
    
    /// Add new contact point between two teeth
    func addContact(
        at position: SCNVector3,
        between tooth1: String,
        and tooth2: String,
        normal: SCNVector3 = SCNVector3(0, 1, 0)
    ) -> ContactPoint {
        
        let contact = ContactPoint(
            position: position,
            normal: normal,
            tooth1: tooth1,
            tooth2: tooth2
        )
        
        contactPoints.append(contact)
        createVisualNode(for: contact)
        
        objectWillChange.send()
        return contact
    }
    
    /// Remove contact point
    func removeContact(_ id: UUID) {
        guard let index = contactPoints.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        let contact = contactPoints[index]
        contact.visualNode?.removeFromParentNode()
        contactPoints.remove(at: index)
        
        if selectedContactID == id {
            selectedContactID = nil
        }
        
        objectWillChange.send()
    }
    
    /// Update contact position
    func updatePosition(_ id: UUID, to newPosition: SCNVector3) {
        guard let contact = contactPoints.first(where: { $0.id == id }) else {
            return
        }
        
        contact.position = newPosition
        contact.visualNode?.position = newPosition
    }
    
    /// Select contact for editing
    func selectContact(_ id: UUID) {
        selectedContactID = id
        updateVisualHighlights()
    }
    
    func deselectAll() {
        selectedContactID = nil
        updateVisualHighlights()
    }
    
    // MARK: - Automatic Detection
    
    /// Automatically detect contact points between adjacent teeth
    func detectContacts(
        from teeth: [String: SCNNode],
        tolerance: Float = 0.001 // 1mm proximity threshold
    ) {
        
        // Clear existing contacts
        clearAll()
        
        // Ordered tooth sequence (left to right)
        let sequence = [
            "T_3_L", "T_2_L", "T_1_L",
            "T_1_R", "T_2_R", "T_3_R"
        ]
        
        for i in 0..<(sequence.count - 1) {
            let id1 = sequence[i]
            let id2 = sequence[i + 1]
            
            guard let tooth1 = teeth[id1],
                  let tooth2 = teeth[id2] else {
                continue
            }
            
            // Find closest points between meshes
            if let (pos1, pos2) = findClosestPoints(tooth1, tooth2) {
                let distance = (pos2 - pos1).length
                
                if distance < tolerance {
                    // Valid contact found
                    let contactPos = SCNVector3(
                        (pos1.x + pos2.x) / 2,
                        (pos1.y + pos2.y) / 2,
                        (pos1.z + pos2.z) / 2
                    )
                    
                    let normal = (pos2 - pos1).normalized
                    
                    let contact = addContact(
                        at: contactPos,
                        between: id1,
                        and: id2,
                        normal: normal
                    )
                    
                    // Estimate contact area from proximity
                    contact.area = estimateContactArea(distance: distance)
                }
            }
        }
    }
    
    /// Find closest points between two tooth meshes
    private func findClosestPoints(
        _ tooth1: SCNNode,
        _ tooth2: SCNNode
    ) -> (SCNVector3, SCNVector3)? {
        
        // Simplified: use bounding box centers + mesial/distal faces
        let bounds1 = tooth1.boundingBox
        let bounds2 = tooth2.boundingBox
        
        let center1 = tooth1.worldPosition
        let center2 = tooth2.worldPosition
        
        // Determine which tooth is to the left
        let tooth1Left = center1.x < center2.x
        
        // Get proximal surface points
        let point1: SCNVector3
        let point2: SCNVector3
        
        if tooth1Left {
            // Tooth1 distal surface (right side)
            point1 = SCNVector3(
                center1.x + bounds1.max.x * CGFloat(tooth1.scale.x),
                center1.y,
                center1.z
            )
            
            // Tooth2 mesial surface (left side)
            point2 = SCNVector3(
                center2.x + bounds2.min.x * CGFloat(tooth2.scale.x),
                center2.y,
                center2.z
            )
        } else {
            // Reversed
            point1 = SCNVector3(
                center1.x + bounds1.min.x * CGFloat(tooth1.scale.x),
                center1.y,
                center1.z
            )
            
            point2 = SCNVector3(
                center2.x + bounds2.max.x * CGFloat(tooth2.scale.x),
                center2.y,
                center2.z
            )
        }
        
        return (point1, point2)
    }
    
    /// Estimate contact area from proximity distance
    private func estimateContactArea(distance: Float) -> Float {
        // Empirical model: closer teeth = larger contact
        let maxArea: Float = 2.0 // mm²
        let minArea: Float = 0.1 // mm²
        
        let normalized = max(0, min(1, distance / 0.002)) // Normalize to 2mm
        return maxArea - (normalized * (maxArea - minArea))
    }
    
    // MARK: - Visualization
    
    /// Create visual sphere for contact point
    private func createVisualNode(for contact: ContactPoint) {
        guard let root = sceneRootNode else { return }
        
        let sphere = SCNSphere(radius: contactSphereRadius)
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.yellow
        material.emission.contents = NSColor.yellow
        material.lightingModel = .constant
        sphere.firstMaterial = material
        
        let node = SCNNode(geometry: sphere)
        node.position = contact.position
        node.name = "CONTACT_\(contact.id.uuidString)"
        node.renderingOrder = 7000 // Render on top
        
        root.addChildNode(node)
        contact.visualNode = node
    }
    
    /// Update visual highlights based on selection
    private func updateVisualHighlights() {
        for contact in contactPoints {
            let isSelected = contact.id == selectedContactID
            let color = isSelected ? NSColor.cyan : NSColor.yellow
            
            contact.visualNode?.geometry?.firstMaterial?.diffuse.contents = color
            contact.visualNode?.geometry?.firstMaterial?.emission.contents = color
        }
    }
    
    /// Toggle visibility of all contact points
    func setVisibility(_ visible: Bool) {
        for contact in contactPoints {
            contact.visualNode?.isHidden = !visible
        }
    }
    
    // MARK: - Validation
    
    /// Validate all contact points against clinical constraints
    func validateAll() -> [String] {
        var allErrors: [String] = []
        
        for contact in contactPoints {
            let errors = contact.validate()
            if !errors.isEmpty {
                allErrors.append("[\(contact.tooth1ID) ↔ \(contact.tooth2ID)]:")
                allErrors.append(contentsOf: errors)
            }
        }
        
        // Check golden proportions between sequential contacts
        if contactPoints.count >= 2 {
            for i in 0..<(contactPoints.count - 1) {
                let c1 = contactPoints[i]
                let c2 = contactPoints[i + 1]
                
                if !c2.checkGoldenProportion(reference: c1) {
                    allErrors.append("Golden ratio violation: \(c1.tooth1ID)-\(c1.tooth2ID) vs \(c2.tooth1ID)-\(c2.tooth2ID)")
                }
            }
        }
        
        return allErrors
    }
    
    // MARK: - Utilities
    
    func clearAll() {
        for contact in contactPoints {
            contact.visualNode?.removeFromParentNode()
        }
        contactPoints.removeAll()
        selectedContactID = nil
        objectWillChange.send()
    }
    
    func getContact(at position: CGPoint, in view: SCNView) -> ContactPoint? {
        let hitResults = view.hitTest(position, options: [:])
        
        for hit in hitResults {
            if let name = hit.node.name,
               name.starts(with: "CONTACT_"),
               let idString = name.split(separator: "_").last,
               let uuid = UUID(uuidString: String(idString)) {
                
                return contactPoints.first { $0.id == uuid }
            }
        }
        
        return nil
    }
}
