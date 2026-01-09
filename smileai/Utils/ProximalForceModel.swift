//
//  MorphableToothModel.swift
//  smileai
//
//  Parametric tooth morphology system for clinical crown design
//

import Foundation
import SceneKit
import simd

// MARK: - Morphology Parameters

/// Clinical parameters defining tooth crown morphology
struct ToothMorphologyParams: Codable, Equatable {
    // Primary Dimensions (meters)
    var height: Float = 0.011        // Crown height (typical incisor: 10-11mm)
    var width: Float = 0.0085        // Mesiodistal width
    var thickness: Float = 0.007     // Labiolingual thickness
    
    // Shape Parameters (0.0 - 1.0)
    var convexity: Float = 0.5       // Labial surface curvature
    var incisalCurvature: Float = 0.3 // Incisal edge roundness
    var cervicalBulge: Float = 0.4   // Gingival third prominence
    
    // Angulation (radians)
    var mesialAngle: Float = 0.0     // Mesial surface angle
    var distalAngle: Float = 0.0     // Distal surface angle
    var labialInclination: Float = 0.0 // Labial face tilt
    
    // Surface Detail
    var mammelonDepth: Float = 0.0002 // Incisal ridges (0.2mm)
    var developmentalGrooves: Float = 0.3 // Prominence of longitudinal grooves
    
    // Type-Specific Presets
    static func preset(for type: ToothType) -> ToothMorphologyParams {
        var params = ToothMorphologyParams()
        
        switch type {
        case .central:
            params.height = 0.0105
            params.width = 0.0085
            params.thickness = 0.007
            params.convexity = 0.6
            params.mammelonDepth = 0.0003
            
        case .lateral:
            params.height = 0.009
            params.width = 0.0065
            params.thickness = 0.006
            params.convexity = 0.7
            params.distalAngle = 0.087 // ~5°
            
        case .canine:
            params.height = 0.0095
            params.width = 0.0075
            params.thickness = 0.008
            params.convexity = 0.8
            params.incisalCurvature = 0.1 // Sharp cusp
            params.cervicalBulge = 0.5
            
        case .premolar:
            params.height = 0.008
            params.width = 0.007
            params.thickness = 0.009
            params.convexity = 0.4
            
        case .molar:
            params.height = 0.007
            params.width = 0.010
            params.thickness = 0.011
            params.convexity = 0.3
        }
        
        return params
    }
}

// MARK: - Morphable Tooth Model

class MorphableToothModel {
    
    private let baseTemplate: SCNNode
    private var params: ToothMorphologyParams
    private let type: ToothType
    
    // Cached geometry
    private var morphedGeometry: SCNGeometry?
    
    init(type: ToothType, baseTemplate: SCNNode? = nil) {
        self.type = type
        self.params = ToothMorphologyParams.preset(for: type)
        
        // Use provided template or generate procedural base
        if let template = baseTemplate {
            self.baseTemplate = template.clone()
        } else {
            self.baseTemplate = Self.generateProceduralBase(for: type)
        }
    }
    
    // MARK: - Geometry Generation
    
    /// Generate morphed crown geometry based on current parameters
    func generateGeometry() -> SCNGeometry {
        // Check cache
        if let cached = morphedGeometry {
            return cached
        }
        
        // Get base mesh
        guard let baseGeo = baseTemplate.geometry else {
            return SCNGeometry() // Fallback
        }
        
        // Extract vertex data
        guard let vertexSource = baseGeo.sources(for: .vertex).first else {
            return baseGeo
        }
        
        let vertexCount = vertexSource.vectorCount
        var vertices: [SCNVector3] = []
        
        vertexSource.data.withUnsafeBytes { buffer in
            let stride = vertexSource.dataStride
            let offset = vertexSource.dataOffset
            
            for i in 0..<vertexCount {
                let index = i * stride + offset
                let x = buffer.load(fromByteOffset: index, as: Float.self)
                let y = buffer.load(fromByteOffset: index + 4, as: Float.self)
                let z = buffer.load(fromByteOffset: index + 8, as: Float.self)
                
                vertices.append(SCNVector3(x, y, z))
            }
        }
        
        // Apply morphological deformation
        let morphedVertices = applyMorphology(to: vertices)
        
        // Create new geometry
        let newVertexSource = SCNGeometrySource(vertices: morphedVertices)
        
        // Preserve original elements (faces)
        let elements = baseGeo.elements
        
        let newGeometry = SCNGeometry(sources: [newVertexSource], elements: elements)
        newGeometry.materials = baseGeo.materials
        
        // Cache result
        morphedGeometry = newGeometry
        
        return newGeometry
    }
    
    // MARK: - Morphological Deformation
    
    /// Apply parametric deformation to vertex positions
    private func applyMorphology(to vertices: [SCNVector3]) -> [SCNVector3] {
        guard !vertices.isEmpty else { return vertices }
        
        // Calculate bounding box for normalization
        let minX = vertices.map { Float($0.x) }.min() ?? 0
        let maxX = vertices.map { Float($0.x) }.max() ?? 0
        let minY = vertices.map { Float($0.y) }.min() ?? 0
        let maxY = vertices.map { Float($0.y) }.max() ?? 0
        let minZ = vertices.map { Float($0.z) }.min() ?? 0
        let maxZ = vertices.map { Float($0.z) }.max() ?? 0
        
        let center = SCNVector3(
            (minX + maxX) / 2,
            (minY + maxY) / 2,
            (minZ + maxZ) / 2
        )
        
        let baseHeight = maxY - minY
        let baseWidth = maxX - minX
        let baseThickness = maxZ - minZ
        
        return vertices.map { vertex in
            // Normalize position (0-1 range)
            let nx = (Float(vertex.x) - minX) / baseWidth
            let ny = (Float(vertex.y) - minY) / baseHeight
            let nz = (Float(vertex.z) - minZ) / baseThickness
            
            // Apply scaling
            var x = Float(vertex.x - center.x)
            var y = Float(vertex.y - center.y)
            var z = Float(vertex.z - center.z)
            
            // 1. Primary Dimension Scaling
            x *= (params.width / baseWidth)
            y *= (params.height / baseHeight)
            z *= (params.thickness / baseThickness)
            
            // 2. Convexity Deformation (labial curvature)
            if nz > 0.5 { // Labial side
                let curvature = params.convexity * 0.002 // 2mm max bulge
                let heightFactor = sin(ny * Float.pi) // Peak at mid-height
                z += curvature * heightFactor
            }
            
            // 3. Cervical Bulge
            if ny < 0.3 { // Gingival third
                let bulgeFactor = (0.3 - ny) / 0.3
                let bulge = params.cervicalBulge * 0.0008 * bulgeFactor
                x *= (1.0 + bulge)
                z *= (1.0 + bulge)
            }
            
            // 4. Incisal Edge Curvature
            if ny > 0.9 { // Incisal edge
                let edgeFactor = (ny - 0.9) / 0.1
                let rounding = params.incisalCurvature * 0.0003
                y -= rounding * edgeFactor * edgeFactor // Quadratic falloff
            }
            
            // 5. Mesial/Distal Angulation
            if nx < 0.5 { // Mesial side
                let angleFactor = (0.5 - nx) * 2.0
                x += tan(params.mesialAngle) * y * angleFactor
            } else { // Distal side
                let angleFactor = (nx - 0.5) * 2.0
                x += tan(params.distalAngle) * y * angleFactor
            }
            
            // 6. Labial Inclination
            if nz > 0.5 {
                let inclineFactor = (nz - 0.5) * 2.0
                z += tan(params.labialInclination) * y * inclineFactor
            }
            
            // Recenter
            return SCNVector3(
                CGFloat(x + Float(center.x)),
                CGFloat(y + Float(center.y)),
                CGFloat(z + Float(center.z))
            )
        }
    }
    
    // MARK: - Procedural Base Generation
    
    /// Generate a simple parametric crown base (fallback when no template exists)
    private static func generateProceduralBase(for type: ToothType) -> SCNNode {
        let preset = ToothMorphologyParams.preset(for: type)
        
        // Create a simple box as base topology
        let box = SCNBox(
            width: CGFloat(preset.width),
            height: CGFloat(preset.height),
            length: CGFloat(preset.thickness),
            chamferRadius: CGFloat(preset.width * 0.1)
        )
        
        box.segmentCount = 8 // Enough for deformation
        
        let node = SCNNode(geometry: box)
        return node
    }
    
    // MARK: - Public API
    
    func updateParameters(_ newParams: ToothMorphologyParams) {
        self.params = newParams
        self.morphedGeometry = nil // Invalidate cache
    }
    
    func getParameters() -> ToothMorphologyParams {
        return params
    }
    
    func instantiate() -> SCNNode {
        let node = SCNNode(geometry: generateGeometry())
        node.name = "MORPHABLE_\(type.rawValue.uppercased())"
        return node
    }
}

// MARK: - Tooth Library Extension

extension ToothLibraryManager {
    
    /// Create a morphable tooth with smart fitting to preparation
    func instantiateMorphableTooth(
        type: ToothType,
        targetPreparation: SCNNode? = nil
    ) -> SCNNode? {
        
        // Load base template from library
        guard let baseTemplate = self.instantiateTooth(type: type) else {
            return nil
        }
        
        // Create morphable model
        let morphable = MorphableToothModel(type: type, baseTemplate: baseTemplate)
        
        // If target preparation exists, auto-fit
        if let prep = targetPreparation {
            let fittedParams = autoFitToPreparation(
                prep,
                baseParams: morphable.getParameters()
            )
            morphable.updateParameters(fittedParams)
        }
        
        return morphable.instantiate()
    }
    
    /// Automatically adjust parameters to fit preparation geometry
    private func autoFitToPreparation(
        _ preparation: SCNNode,
        baseParams: ToothMorphologyParams
    ) -> ToothMorphologyParams {
        
        var params = baseParams
        
        // Calculate preparation dimensions
        let (min, max) = preparation.boundingBox
        
        let prepHeight = Float(max.y - min.y)
        let prepWidth = Float(max.x - min.x)
        let prepThickness = Float(max.z - min.z)
        
        // Scale to match preparation (with clearance)
        let clearance: Float = 0.0001 // 0.1mm
        params.height = prepHeight + clearance
        params.width = prepWidth * 1.05 // Slight overhang for contact
        params.thickness = prepThickness * 1.05
        
        return params
    }
}
