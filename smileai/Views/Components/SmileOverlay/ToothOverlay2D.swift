//
//  ToothOverlay2D.swift
//  smileai
//
//  2D Smile Overlay System - Tooth Representation
//  Phase 1: Core Models
//

import Foundation
import SwiftUI
import SceneKit

/// Individual tooth overlay in 2D photo space
struct ToothOverlay2D: Identifiable, Equatable {
    
    // MARK: - Identity
    
    let id: UUID
    
    /// FDI tooth notation (e.g., "11" for upper right central)
    var toothNumber: String
    
    /// Tooth type classification
    var toothType: ToothType
    
    // MARK: - Position & Transform
    
    /// Center position in photo pixel coordinates
    var position: CGPoint
    
    /// Individual rotation in radians
    var rotation: CGFloat
    
    /// Individual scale factor
    var scale: CGFloat
    
    // MARK: - Dimensions (Real-World)
    
    /// Real width in millimeters
    var width: Float
    
    /// Real height in millimeters
    var height: Float
    
    /// Real thickness in millimeters (labiolingual)
    var thickness: Float
    
    // MARK: - Visual Representation
    
    /// 2D contour points (projected from 3D mesh)
    var outlinePoints: [CGPoint]
    
    /// Visibility flag
    var visible: Bool
    
    /// Optional custom color
    var customColor: Color?
    
    /// Optional opacity override
    var customOpacity: Double?
    
    // MARK: - Metadata
    
    /// Source 3D mesh filename (for reference)
    var sourceMeshName: String?
    
    /// Timestamp of creation
    var createdAt: Date
    
    /// Last modified timestamp
    var modifiedAt: Date
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        toothNumber: String,
        toothType: ToothType,
        position: CGPoint,
        rotation: CGFloat = 0.0,
        scale: CGFloat = 1.0,
        width: Float,
        height: Float,
        thickness: Float = 0.007,
        outlinePoints: [CGPoint] = [],
        visible: Bool = true,
        sourceMeshName: String? = nil
    ) {
        self.id = id
        self.toothNumber = toothNumber
        self.toothType = toothType
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.width = width
        self.height = height
        self.thickness = thickness
        self.visible = visible
        self.sourceMeshName = sourceMeshName
        self.createdAt = Date()
        self.modifiedAt = Date()
        
        // FIX: Ensure outline points are initialized to prevent NaN errors
        if outlinePoints.isEmpty {
            let halfW = CGFloat(width) / 2
            let halfH = CGFloat(height) / 2
            
            self.outlinePoints = [
                CGPoint(x: position.x - halfW, y: position.y - halfH),
                CGPoint(x: position.x + halfW, y: position.y - halfH),
                CGPoint(x: position.x + halfW, y: position.y + halfH),
                CGPoint(x: position.x - halfW, y: position.y + halfH)
            ]
        } else {
            self.outlinePoints = outlinePoints
        }
    }
    
    // MARK: - Computed Properties
    
    /// Bounding box for hit testing
    var boundingRect: CGRect {
        guard !outlinePoints.isEmpty else {
            // Fallback: use dimensions
            let halfWidth = CGFloat(width) * scale / 2
            let halfHeight = CGFloat(height) * scale / 2
            
            return CGRect(
                x: position.x - halfWidth,
                y: position.y - halfHeight,
                width: CGFloat(width) * scale,
                height: CGFloat(height) * scale
            )
        }
        
        let minX = outlinePoints.map { $0.x }.min() ?? position.x
        let maxX = outlinePoints.map { $0.x }.max() ?? position.x
        let minY = outlinePoints.map { $0.y }.min() ?? position.y
        let maxY = outlinePoints.map { $0.y }.max() ?? position.y
        
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
    
    /// Centroid of outline points
    var centroid: CGPoint {
        guard !outlinePoints.isEmpty else { return position }
        
        let sumX = outlinePoints.reduce(0.0) { $0 + $1.x }
        let sumY = outlinePoints.reduce(0.0) { $0 + $1.y }
        
        return CGPoint(
            x: sumX / CGFloat(outlinePoints.count),
            y: sumY / CGFloat(outlinePoints.count)
        )
    }
    
    /// Actual width in pixels (scaled)
    var pixelWidth: CGFloat {
        return boundingRect.width
    }
    
    /// Actual height in pixels (scaled)
    var pixelHeight: CGFloat {
        return boundingRect.height
    }
    
    // MARK: - Transform Methods
    
    /// Apply additional transform
    mutating func applyTransform(_ transform: SmileTransform2D) {
        // Transform position
        self.position = transform.apply(to: position)
        
        // Combine rotations
        self.rotation += transform.rotation
        
        // Combine scales
        self.scale *= transform.scale
        
        // Transform outline points
        self.outlinePoints = outlinePoints.map { point in
            transform.apply(to: point)
        }
        
        self.modifiedAt = Date()
    }
    
    /// Reset to default transform
    mutating func resetTransform() {
        self.rotation = 0.0
        self.scale = 1.0
        self.modifiedAt = Date()
    }
    
    /// Move to new position
    mutating func moveTo(_ newPosition: CGPoint) {
        let delta = CGPoint(
            x: newPosition.x - position.x,
            y: newPosition.y - position.y
        )
        
        self.position = newPosition
        
        // Translate outline points
        self.outlinePoints = outlinePoints.map { point in
            CGPoint(x: point.x + delta.x, y: point.y + delta.y)
        }
        
        self.modifiedAt = Date()
    }
    
    // MARK: - Hit Testing
    
    /// Check if point is inside tooth outline
    func contains(_ point: CGPoint) -> Bool {
        // Quick reject: check bounding box first
        guard boundingRect.contains(point) else {
            return false
        }
        
        // Precise check: point-in-polygon test
        guard outlinePoints.count >= 3 else {
            return boundingRect.contains(point)
        }
        
        return pointInPolygon(point, polygon: outlinePoints)
    }
    
    /// Point-in-polygon algorithm (ray casting)
    private func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            let xi = polygon[i].x
            let yi = polygon[i].y
            let xj = polygon[j].x
            let yj = polygon[j].y
            
            if ((yi > point.y) != (yj > point.y)) &&
               (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) {
                inside = !inside
            }
            
            j = i
        }
        
        return inside
    }
    
    // MARK: - Validation
    
    /// Check if tooth data is valid
    var isValid: Bool {
        return width > 0 &&
               height > 0 &&
               !toothNumber.isEmpty &&
               !outlinePoints.isEmpty
    }
    
    /// Validation errors
    func validate() -> [String] {
        var errors: [String] = []
        
        if width <= 0 {
            errors.append("Invalid width: \(width)")
        }
        
        if height <= 0 {
            errors.append("Invalid height: \(height)")
        }
        
        if toothNumber.isEmpty {
            errors.append("Missing tooth number")
        }
        
        if outlinePoints.isEmpty {
            errors.append("No outline points")
        }
        
        if outlinePoints.count < 3 {
            errors.append("Insufficient outline points: \(outlinePoints.count)")
        }
        
        return errors
    }
}

// MARK: - Factory Methods

extension ToothOverlay2D {
    
    /// Create from FDI notation and position
    static func create(
        fdi: String,
        position: CGPoint,
        width: Float,
        height: Float
    ) -> ToothOverlay2D {
        
        // Parse FDI to determine tooth type
        let type = ToothType.fromFDI(fdi)
        
        return ToothOverlay2D(
            toothNumber: fdi,
            toothType: type,
            position: position,
            width: width,
            height: height
        )
    }
    
    /// Create placeholder outline (rectangle)
    mutating func generatePlaceholderOutline() {
        let halfW = CGFloat(width) / 2
        let halfH = CGFloat(height) / 2
        
        self.outlinePoints = [
            CGPoint(x: position.x - halfW, y: position.y - halfH),
            CGPoint(x: position.x + halfW, y: position.y - halfH),
            CGPoint(x: position.x + halfW, y: position.y + halfH),
            CGPoint(x: position.x - halfW, y: position.y + halfH)
        ]
    }
}

// MARK: - ToothType Extension

extension ToothType {
    
    /// Parse FDI notation to determine tooth type
    static func fromFDI(_ fdi: String) -> ToothType {
        guard fdi.count == 2,
              let lastDigit = Int(String(fdi.last!)) else {
            return .central
        }
        
        switch lastDigit {
        case 1: return .central
        case 2: return .lateral
        case 3: return .canine
        case 4, 5: return .premolar
        case 6, 7, 8: return .molar
        default: return .central
        }
    }
    
    /// Get FDI number for tooth type in quadrant
    func fdiNumber(quadrant: Int, position: Int) -> String {
        return "\(quadrant)\(position)"
    }
    
    /// Typical dimensions for tooth type (in millimeters)
    var typicalDimensions: (width: Float, height: Float) {
        switch self {
        case .central:
            return (width: 8.5, height: 10.5)
        case .lateral:
            return (width: 6.5, height: 9.0)
        case .canine:
            return (width: 7.5, height: 10.0)
        case .premolar:
            return (width: 7.0, height: 8.5)
        case .molar:
            return (width: 10.0, height: 7.5)
        }
    }
}

// MARK: - Collection Extensions

extension Array where Element == ToothOverlay2D {
    
    /// Get tooth by FDI number
    func tooth(fdi: String) -> ToothOverlay2D? {
        return first { $0.toothNumber == fdi }
    }
    
    /// Get teeth by type
    func teeth(ofType type: ToothType) -> [ToothOverlay2D] {
        return filter { $0.toothType == type }
    }
    
    /// Get visible teeth only
    var visible: [ToothOverlay2D] {
        return filter { $0.visible }
    }
    
    /// Overall bounding box
    var boundingRect: CGRect {
        guard !isEmpty else { return .zero }
        
        let allRects = map { $0.boundingRect }
        
        let minX = allRects.map { $0.minX }.min() ?? 0
        let maxX = allRects.map { $0.maxX }.max() ?? 0
        let minY = allRects.map { $0.minY }.min() ?? 0
        let maxY = allRects.map { $0.maxY }.max() ?? 0
        
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
    
    /// Total arch width
    var archWidth: Float {
        guard !isEmpty else { return 0 }
        
        let leftmost = map { Float($0.position.x) }.min() ?? 0
        let rightmost = map { Float($0.position.x) }.max() ?? 0
        
        return rightmost - leftmost
    }
}
