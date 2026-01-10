//
//  LibraryProjector.swift
//  smileai
//
//  2D Smile Overlay System - 3D to 2D Projection Engine
//  Phase 2: Projection System
//

import Foundation
import SceneKit
import CoreGraphics

/// Projects 3D tooth library meshes to 2D photo space
class LibraryProjector {
    
    // MARK: - Properties
    
    /// Camera calibration parameters
    private let calibration: CameraCalibrationData
    
    /// Cache for projected silhouettes
    private var silhouetteCache: [String: [SCNVector3]] = [:]
    
    // MARK: - Initialization
    
    init(calibration: CameraCalibrationData) {
        self.calibration = calibration
    }
    
    // MARK: - Main Projection Method
    
    /// Project 3D tooth mesh to 2D outline
    func project(
        tooth: SCNNode,
        toPhotoSize photoSize: CGSize
    ) -> ToothOverlay2D {
        
        guard let geometry = tooth.geometry else {
            fatalError("Tooth node has no geometry")
        }
        
        // 1. Extract or retrieve cached contour vertices
        let contour3D: [SCNVector3]
        if let cached = silhouetteCache[tooth.name ?? ""] {
            contour3D = cached
        } else {
            contour3D = extractSilhouette(from: geometry, node: tooth)
            silhouetteCache[tooth.name ?? ""] = contour3D
        }
        
        // 2. Apply camera projection to each 3D point
        let contour2D = contour3D.map { vertex in
            project3DPoint(vertex, toPhotoSize: photoSize)
        }
        
        // 3. Calculate real-world dimensions
        let dimensions = calculateDimensions(from: contour3D)
        
        // 4. Find center in 2D space
        let center = calculateCenter(from: contour2D)
        
        // 5. Detect tooth type from node name
        let toothType = detectToothType(from: tooth)
        
        // 6. Create overlay
        return ToothOverlay2D(
            toothNumber: tooth.name ?? "Unknown",
            toothType: toothType,
            position: center,
            width: dimensions.width,
            height: dimensions.height,
            thickness: dimensions.depth,
            outlinePoints: contour2D,
            sourceMeshName: tooth.name
        )
    }
    
    /// Project multiple teeth as complete arch
    func projectArch(
        teeth: [SCNNode],
        toPhotoSize photoSize: CGSize
    ) -> [ToothOverlay2D] {
        
        return teeth.map { tooth in
            project(tooth: tooth, toPhotoSize: photoSize)
        }
    }
    
    // MARK: - 3D Point Projection
    
    /// Project single 3D point to 2D photo coordinates
    private func project3DPoint(
        _ point: SCNVector3,
        toPhotoSize photoSize: CGSize
    ) -> CGPoint {
        
        let distance = calibration.distanceToSubject
        let angle = calibration.angle
        
        // 1. Apply camera rotation (pitch down)
        let rotatedY = Float(point.y) * cos(angle) - Float(point.z) * sin(angle)
        let rotatedZ = Float(point.y) * sin(angle) + Float(point.z) * cos(angle)
        
        // 2. Perspective projection
        // Scale factor based on distance from camera
        let depthScale = calibration.focalLength / (distance + rotatedZ)
        
        let projectedX = Float(point.x) * depthScale
        let projectedY = rotatedY * depthScale
        
        // 3. Convert millimeters to pixels
        let pixelsPerMM = calibration.pixelsPerMM(photoWidth: photoSize.width)
        
        // 4. Transform to photo coordinate system
        // Origin at center, Y-axis flipped (screen coordinates)
        let pixelX = CGFloat(projectedX * pixelsPerMM) + photoSize.width / 2
        let pixelY = CGFloat(-projectedY * pixelsPerMM) + photoSize.height / 2
        
        return CGPoint(x: pixelX, y: pixelY)
    }
    
    // MARK: - Silhouette Extraction
    
    /// Extract visible contour from 3D mesh (silhouette edge detection)
    private func extractSilhouette(
        from geometry: SCNGeometry,
        node: SCNNode
    ) -> [SCNVector3] {
        
        guard let vertexSource = geometry.sources(for: .vertex).first,
              let normalSource = geometry.sources(for: .normal).first else {
            return []
        }
        
        var silhouetteVertices: [SCNVector3] = []
        
        // View direction (camera looking down Z axis)
        let viewDirection = SCNVector3(0, 0, 1)
        
        // Extract vertex and normal data
        let vertexData = vertexSource.data
        let normalData = normalSource.data
        
        let vertexStride = vertexSource.dataStride
        let normalStride = normalSource.dataStride
        let vertexCount = vertexSource.vectorCount
        
        vertexData.withUnsafeBytes { vertexBuffer in
            normalData.withUnsafeBytes { normalBuffer in
                
                for i in 0..<vertexCount {
                    let vOffset = i * vertexStride + vertexSource.dataOffset
                    let nOffset = i * normalStride + normalSource.dataOffset
                    
                    // Read vertex position
                    let x = vertexBuffer.load(fromByteOffset: vOffset, as: Float.self)
                    let y = vertexBuffer.load(fromByteOffset: vOffset + 4, as: Float.self)
                    let z = vertexBuffer.load(fromByteOffset: vOffset + 8, as: Float.self)
                    
                    // Read normal
                    let nx = normalBuffer.load(fromByteOffset: nOffset, as: Float.self)
                    let ny = normalBuffer.load(fromByteOffset: nOffset + 4, as: Float.self)
                    let nz = normalBuffer.load(fromByteOffset: nOffset + 8, as: Float.self)
                    
                    let vertex = SCNVector3(x, y, z)
                    let normal = SCNVector3(nx, ny, nz)
                    
                    // Check if this vertex is on the silhouette
                    // Silhouette condition: normal perpendicular to view direction
                    let dot = dotProduct(normal, viewDirection)
                    
                    // Threshold for silhouette detection (perpendicular = 0)
                    if abs(dot) < 0.2 {
                        // Apply node's transform
                        let worldVertex = node.convertPosition(vertex, to: nil)
                        silhouetteVertices.append(worldVertex)
                    }
                }
            }
        }
        
        // If silhouette extraction failed, fall back to boundary vertices
        if silhouetteVertices.isEmpty {
            silhouetteVertices = extractBoundaryVertices(from: geometry, node: node)
        }
        
        // Sort vertices to form continuous contour
        return orderContourPoints(silhouetteVertices)
    }
    
    /// Extract boundary vertices (fallback method)
    private func extractBoundaryVertices(
        from geometry: SCNGeometry,
        node: SCNNode
    ) -> [SCNVector3] {
        
        guard let vertexSource = geometry.sources(for: .vertex).first else {
            return []
        }
        
        var vertices: [SCNVector3] = []
        let vertexData = vertexSource.data
        let stride = vertexSource.dataStride
        let count = vertexSource.vectorCount
        
        vertexData.withUnsafeBytes { buffer in
            for i in 0..<count {
                let offset = i * stride + vertexSource.dataOffset
                
                let x = buffer.load(fromByteOffset: offset, as: Float.self)
                let y = buffer.load(fromByteOffset: offset + 4, as: Float.self)
                let z = buffer.load(fromByteOffset: offset + 8, as: Float.self)
                
                let vertex = SCNVector3(x, y, z)
                let worldVertex = node.convertPosition(vertex, to: nil)
                
                // Only include vertices near the front face (Z > 0)
                if worldVertex.z > -0.002 {
                    vertices.append(worldVertex)
                }
            }
        }
        
        return vertices
    }
    
    /// Order contour points to form continuous path
    private func orderContourPoints(_ points: [SCNVector3]) -> [SCNVector3] {
        guard !points.isEmpty else { return [] }
        guard points.count > 2 else { return points }
        
        var ordered: [SCNVector3] = [points[0]]
        var remaining = Array(points.dropFirst())
        
        // Greedy nearest-neighbor ordering
        while !remaining.isEmpty {
            let current = ordered.last!
            
            // Find nearest point
            var nearestIndex = 0
            var nearestDistance: Float = .infinity
            
            for (index, point) in remaining.enumerated() {
                let dist = distance(current, point)
                if dist < nearestDistance {
                    nearestDistance = dist
                    nearestIndex = index
                }
            }
            
            ordered.append(remaining[nearestIndex])
            remaining.remove(at: nearestIndex)
        }
        
        return ordered
    }
    
    // MARK: - Dimension Calculation
    
    /// Calculate real-world dimensions from 3D vertices
    private func calculateDimensions(from vertices: [SCNVector3]) -> (width: Float, height: Float, depth: Float) {
        guard !vertices.isEmpty else {
            return (0, 0, 0)
        }
        
        let xValues = vertices.map { Float($0.x) }
        let yValues = vertices.map { Float($0.y) }
        let zValues = vertices.map { Float($0.z) }
        
        let width = (xValues.max() ?? 0) - (xValues.min() ?? 0)
        let height = (yValues.max() ?? 0) - (yValues.min() ?? 0)
        let depth = (zValues.max() ?? 0) - (zValues.min() ?? 0)
        
        // Convert meters to millimeters
        return (
            width: width * 1000.0,
            height: height * 1000.0,
            depth: depth * 1000.0
        )
    }
    
    /// Calculate center point in 2D
    private func calculateCenter(from points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        
        return CGPoint(
            x: sumX / CGFloat(points.count),
            y: sumY / CGFloat(points.count)
        )
    }
    
    // MARK: - Tooth Type Detection
    
    /// Detect tooth type from node name
    private func detectToothType(from node: SCNNode) -> ToothType {
        guard let name = node.name?.lowercased() else { return .central }
        
        if name.contains("central") || name.contains("11") || name.contains("21") {
            return .central
        }
        if name.contains("lateral") || name.contains("12") || name.contains("22") {
            return .lateral
        }
        if name.contains("canine") || name.contains("13") || name.contains("23") {
            return .canine
        }
        if name.contains("premolar") || name.contains("14") || name.contains("15") ||
           name.contains("24") || name.contains("25") {
            return .premolar
        }
        if name.contains("molar") || name.contains("16") || name.contains("17") ||
           name.contains("26") || name.contains("27") {
            return .molar
        }
        
        return .central
    }
    
    // MARK: - Utility Methods
    
    /// Dot product of two vectors
    private func dotProduct(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        return Float(a.x) * Float(b.x) + Float(a.y) * Float(b.y) + Float(a.z) * Float(b.z)
    }
    
    /// Distance between two 3D points
    private func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        let dx = Float(a.x - b.x)
        let dy = Float(a.y - b.y)
        let dz = Float(a.z - b.z)
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
    
    // MARK: - Cache Management
    
    /// Clear silhouette cache
    func clearCache() {
        silhouetteCache.removeAll()
    }
    
    /// Preload silhouettes for multiple teeth
    func preloadSilhouettes(for nodes: [SCNNode]) {
        for node in nodes {
            guard let geometry = node.geometry else { continue }
            let silhouette = extractSilhouette(from: geometry, node: node)
            silhouetteCache[node.name ?? ""] = silhouette
        }
    }
}

// MARK: - Enhanced Camera Calibration

extension CameraCalibrationData {
    
    /// Calibrate from known reference dimension
    static func calibrateFromReference(
        photo: NSImage,
        referenceWidthMM: Float,
        referenceWidthPixels: CGFloat
    ) -> CameraCalibrationData {
        
        // Calculate pixels per millimeter
        let pixelsPerMM = Float(referenceWidthPixels) / referenceWidthMM
        
        // Estimate other parameters
        let focalLength: Float = 85.0  // Typical macro lens
        let sensorWidth: Float = 36.0  // Full frame
        
        // Back-calculate distance using known reference
        // pixelsPerMM = photoWidth / (sensorWidth * distance / focalLength)
        let photoWidth = Float(photo.size.width)
        let distance = (photoWidth * focalLength) / (pixelsPerMM * sensorWidth)
        
        return CameraCalibrationData(
            focalLength: focalLength,
            sensorWidth: sensorWidth,
            distanceToSubject: distance,
            angle: 0.1  // Typical slight downward tilt
        )
    }
    
    /// Extract calibration from EXIF data
    static func fromEXIF(_ exifData: [String: Any]) -> CameraCalibrationData? {
        // Check for required EXIF fields
        guard let focalLength = exifData["FocalLength"] as? Float else {
            return nil
        }
        
        // Sensor width (varies by camera model)
        let sensorWidth: Float = 36.0  // Assume full frame
        
        // Estimate working distance (not in EXIF)
        let distance: Float = 300.0  // mm
        
        return CameraCalibrationData(
            focalLength: focalLength,
            sensorWidth: sensorWidth,
            distanceToSubject: distance,
            angle: 0.1
        )
    }
}

// MARK: - Projection Quality Assessment

extension LibraryProjector {
    
    /// Assess quality of projection
    func assessProjectionQuality(tooth: ToothOverlay2D) -> ProjectionQuality {
        var score: Float = 1.0
        var issues: [String] = []
        
        // Check outline point count
        if tooth.outlinePoints.count < 10 {
            score *= 0.5
            issues.append("Insufficient outline points")
        }
        
        // Check dimensions
        if tooth.width < 4.0 || tooth.width > 15.0 {
            score *= 0.7
            issues.append("Unusual width: \(tooth.width)mm")
        }
        
        if tooth.height < 6.0 || tooth.height > 15.0 {
            score *= 0.7
            issues.append("Unusual height: \(tooth.height)mm")
        }
        
        // Check aspect ratio
        let aspectRatio = tooth.width / tooth.height
        if aspectRatio < 0.5 || aspectRatio > 1.5 {
            score *= 0.8
            issues.append("Unusual aspect ratio: \(aspectRatio)")
        }
        
        let quality: ProjectionQuality.Level
        if score > 0.9 {
            quality = .excellent
        } else if score > 0.7 {
            quality = .good
        } else if score > 0.5 {
            quality = .fair
        } else {
            quality = .poor
        }
        
        return ProjectionQuality(
            level: quality,
            score: score,
            issues: issues
        )
    }
}

/// Projection quality assessment
struct ProjectionQuality {
    enum Level {
        case excellent
        case good
        case fair
        case poor
    }
    
    let level: Level
    let score: Float
    let issues: [String]
}
