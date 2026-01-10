//
//  MeasurementGrid.swift
//  smileai
//
//  2D Smile Overlay System - Measurement Grid & Annotations
//  Phase 1: Core Models
//

import Foundation
import SwiftUI

/// Measurement grid configuration and annotations
struct MeasurementGrid: Codable, Equatable {
    
    // MARK: - Grid Properties
    
    /// Grid origin in photo pixel coordinates
    var origin: CGPoint = .zero
    
    /// Spacing between grid lines in millimeters
    var spacing: Float = 5.0
    
    /// Pixels per millimeter (from calibration)
    var pixelsPerMM: Float = 10.0
    
    // MARK: - Reference Lines
    
    /// X position of dental midline (if set)
    var midline: CGFloat? = nil
    
    /// Y position of occlusal plane (if set)
    var occlusalPlane: CGFloat? = nil
    
    /// Smile line curve points
    var smileLine: [CGPoint] = []
    
    /// Pupillary line (horizontal reference)
    var pupillaryLine: CGFloat? = nil
    
    // MARK: - Measurements & Annotations
    
    /// Collection of measurement annotations
    var annotations: [MeasurementAnnotation] = []
    
    // MARK: - Visual Style
    
    /// Grid line color
    var lineColor: Color = .yellow
    
    /// Grid line opacity
    var lineOpacity: Double = 0.5
    
    /// Grid line width
    var lineWidth: CGFloat = 1.0
    
    /// Show dimension labels
    var showLabels: Bool = true
    
    /// Label font size
    var labelFontSize: CGFloat = 10
    
    /// Reference line color
    var referenceLineColor: Color = .cyan
    
    /// Reference line width
    var referenceLineWidth: CGFloat = 2.0
    
    /// Reference line dash pattern
    var referenceDashPattern: [CGFloat] = [5, 5]
    
    // MARK: - Initialization
    
    init(
        origin: CGPoint = .zero,
        spacing: Float = 5.0,
        pixelsPerMM: Float = 10.0
    ) {
        self.origin = origin
        self.spacing = spacing
        self.pixelsPerMM = pixelsPerMM
    }
    
    // MARK: - Unit Conversion
    
    /// Convert millimeters to pixels
    func mmToPixels(_ mm: Float) -> CGFloat {
        return CGFloat(mm * pixelsPerMM)
    }
    
    /// Convert pixels to millimeters
    func pixelsToMM(_ pixels: CGFloat) -> Float {
        return Float(pixels) / pixelsPerMM
    }
    
    // MARK: - Grid Generation
    
    /// Generate grid lines for given bounds
    func generateGridLines(in rect: CGRect) -> [GridLine] {
        var lines: [GridLine] = []
        
        let spacingPx = mmToPixels(spacing)
        
        // Vertical lines (from origin)
        var x = origin.x
        var index = 0
        
        // Lines to the right
        while x <= rect.maxX {
            let distance = pixelsToMM(x - origin.x)
            lines.append(GridLine(
                start: CGPoint(x: x, y: rect.minY),
                end: CGPoint(x: x, y: rect.maxY),
                label: showLabels ? "\(Int(distance))mm" : "",
                orientation: .vertical
            ))
            x += spacingPx
            index += 1
        }
        
        // Lines to the left
        x = origin.x - spacingPx
        index = -1
        while x >= rect.minX {
            let distance = pixelsToMM(origin.x - x)
            lines.append(GridLine(
                start: CGPoint(x: x, y: rect.minY),
                end: CGPoint(x: x, y: rect.maxY),
                label: showLabels ? "\(Int(distance))mm" : "",
                orientation: .vertical
            ))
            x -= spacingPx
            index -= 1
        }
        
        // Horizontal lines (from origin)
        var y = origin.y
        index = 0
        
        // Lines downward
        while y <= rect.maxY {
            let distance = pixelsToMM(y - origin.y)
            lines.append(GridLine(
                start: CGPoint(x: rect.minX, y: y),
                end: CGPoint(x: rect.maxX, y: y),
                label: showLabels ? "\(Int(distance))mm" : "",
                orientation: .horizontal
            ))
            y += spacingPx
            index += 1
        }
        
        // Lines upward
        y = origin.y - spacingPx
        index = -1
        while y >= rect.minY {
            let distance = pixelsToMM(origin.y - y)
            lines.append(GridLine(
                start: CGPoint(x: rect.minX, y: y),
                end: CGPoint(x: rect.maxX, y: y),
                label: showLabels ? "\(Int(distance))mm" : "",
                orientation: .horizontal
            ))
            y -= spacingPx
            index -= 1
        }
        
        return lines
    }
    
    // MARK: - Reference Lines
    
    /// Generate reference lines (midline, occlusal plane, etc.)
    func generateReferenceLines(in rect: CGRect) -> [ReferenceLine] {
        var lines: [ReferenceLine] = []
        
        // Midline (vertical)
        if let midline = midline {
            lines.append(ReferenceLine(
                type: .midline,
                start: CGPoint(x: midline, y: rect.minY),
                end: CGPoint(x: midline, y: rect.maxY),
                label: "Midline"
            ))
        }
        
        // Occlusal plane (horizontal)
        if let occlusalPlane = occlusalPlane {
            lines.append(ReferenceLine(
                type: .occlusalPlane,
                start: CGPoint(x: rect.minX, y: occlusalPlane),
                end: CGPoint(x: rect.maxX, y: occlusalPlane),
                label: "Occlusal Plane"
            ))
        }
        
        // Pupillary line (horizontal)
        if let pupillaryLine = pupillaryLine {
            lines.append(ReferenceLine(
                type: .pupillaryLine,
                start: CGPoint(x: rect.minX, y: pupillaryLine),
                end: CGPoint(x: rect.maxX, y: pupillaryLine),
                label: "Pupillary Line"
            ))
        }
        
        // Smile line (curve)
        if smileLine.count >= 2 {
            lines.append(ReferenceLine(
                type: .smileLine,
                points: smileLine,
                label: "Smile Line"
            ))
        }
        
        return lines
    }
    
    // MARK: - Annotation Management
    
    /// Add measurement annotation
    mutating func addAnnotation(_ annotation: MeasurementAnnotation) {
        annotations.append(annotation)
    }
    
    /// Remove annotation by ID
    mutating func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
    }
    
    /// Clear all annotations
    mutating func clearAnnotations() {
        annotations.removeAll()
    }
    
    /// Find annotation at point
    func annotationAt(_ point: CGPoint, tolerance: CGFloat = 20) -> MeasurementAnnotation? {
        for annotation in annotations {
            // Check if any point in annotation is close to target point
            for annotationPoint in annotation.points {
                let distance = hypot(
                    point.x - annotationPoint.x,
                    point.y - annotationPoint.y
                )
                
                if distance < tolerance {
                    return annotation
                }
            }
        }
        
        return nil
    }
}

// MARK: - Grid Line

/// Single grid line
struct GridLine: Identifiable, Equatable {
    let id = UUID()
    var start: CGPoint
    var end: CGPoint
    var label: String
    var orientation: Orientation
    
    enum Orientation {
        case horizontal
        case vertical
    }
}

// MARK: - Reference Line

/// Reference line (midline, occlusal plane, etc.)
struct ReferenceLine: Identifiable, Equatable {
    let id = UUID()
    var type: ReferenceType
    var start: CGPoint = .zero
    var end: CGPoint = .zero
    var points: [CGPoint] = []
    var label: String
    
    enum ReferenceType: String, Codable {
        case midline
        case occlusalPlane
        case pupillaryLine
        case smileLine
        case custom
    }
    
    /// Initialize as line segment
    init(type: ReferenceType, start: CGPoint, end: CGPoint, label: String) {
        self.type = type
        self.start = start
        self.end = end
        self.label = label
    }
    
    /// Initialize as polyline/curve
    init(type: ReferenceType, points: [CGPoint], label: String) {
        self.type = type
        self.points = points
        self.label = label
        if !points.isEmpty {
            self.start = points.first!
            self.end = points.last!
        }
    }
}

// MARK: - Measurement Annotation

/// Measurement annotation (dimension, angle, note, etc.)
struct MeasurementAnnotation: Identifiable, Codable, Equatable {
    
    let id: UUID
    
    /// Annotation type
    var type: AnnotationType
    
    /// Points defining the measurement
    var points: [CGPoint]
    
    /// Label text
    var label: String
    
    /// Measured value (in millimeters or degrees)
    var value: Float
    
    /// Optional color
    var color: Color?
    
    /// Creation timestamp
    var createdAt: Date
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        type: AnnotationType,
        points: [CGPoint],
        label: String,
        value: Float,
        color: Color? = nil
    ) {
        self.id = id
        self.type = type
        self.points = points
        self.label = label
        self.value = value
        self.color = color
        self.createdAt = Date()
    }
    
    // MARK: - Annotation Types
    
    enum AnnotationType: String, Codable, CaseIterable {
        case distance      // Point-to-point distance
        case angle         // Three-point angle
        case ratio         // Width ratio (e.g., golden ratio)
        case area          // Enclosed area
        case note          // Text label only
        case dimension     // Distance with extension lines
    }
    
    // MARK: - Computed Properties
    
    /// Formatted value string
    var valueString: String {
        switch type {
        case .angle:
            return String(format: "%.1f°", value)
        case .distance, .dimension:
            return String(format: "%.2fmm", value)
        case .area:
            return String(format: "%.2fmm²", value)
        case .ratio:
            return String(format: "%.3f", value)
        case .note:
            return label
        }
    }
    
    /// Center point for label placement
    var centerPoint: CGPoint {
        guard !points.isEmpty else { return .zero }
        
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        
        return CGPoint(
            x: sumX / CGFloat(points.count),
            y: sumY / CGFloat(points.count)
        )
    }
    
    // MARK: - Factory Methods
    
    /// Create distance measurement
    static func distance(
        from start: CGPoint,
        to end: CGPoint,
        pixelsPerMM: Float
    ) -> MeasurementAnnotation {
        let dx = Float(end.x - start.x)
        let dy = Float(end.y - start.y)
        let distancePx = sqrt(dx * dx + dy * dy)
        let distanceMM = distancePx / pixelsPerMM
        
        return MeasurementAnnotation(
            type: .distance,
            points: [start, end],
            label: "Distance",
            value: distanceMM
        )
    }
    
    /// Create angle measurement
    static func angle(
        point1: CGPoint,
        vertex: CGPoint,
        point2: CGPoint
    ) -> MeasurementAnnotation {
        // Vector 1: vertex → point1
        let v1x = Float(point1.x - vertex.x)
        let v1y = Float(point1.y - vertex.y)
        
        // Vector 2: vertex → point2
        let v2x = Float(point2.x - vertex.x)
        let v2y = Float(point2.y - vertex.y)
        
        // Calculate angle
        let dot = v1x * v2x + v1y * v2y
        let mag1 = sqrt(v1x * v1x + v1y * v1y)
        let mag2 = sqrt(v2x * v2x + v2y * v2y)
        
        let angleRad = acos(dot / (mag1 * mag2))
        let angleDeg = angleRad * 180.0 / Float.pi
        
        return MeasurementAnnotation(
            type: .angle,
            points: [point1, vertex, point2],
            label: "Angle",
            value: angleDeg
        )
    }
    
    /// Create ratio measurement (width comparison)
    static func ratio(
        width1: Float,
        width2: Float,
        point1: CGPoint,
        point2: CGPoint
    ) -> MeasurementAnnotation {
        let ratio = width1 / width2
        
        return MeasurementAnnotation(
            type: .ratio,
            points: [point1, point2],
            label: "Ratio",
            value: ratio
        )
    }
    
    /// Create text note
    static func note(
        at point: CGPoint,
        text: String
    ) -> MeasurementAnnotation {
        return MeasurementAnnotation(
            type: .note,
            points: [point],
            label: text,
            value: 0
        )
    }
}

// MARK: - Golden Ratio Helpers

extension MeasurementGrid {
    
    /// Calculate if ratio matches golden ratio (within tolerance)
    func isGoldenRatio(_ ratio: Float, tolerance: Float = 0.05) -> Bool {
        let phi: Float = 1.618
        return abs(ratio - phi) < tolerance
    }
    
    /// Calculate expected golden ratio width
    func goldenRatioWidth(reference: Float) -> Float {
        return reference * 1.618
    }
    
    /// Generate golden ratio overlay points
    func goldenRatioPoints(
        archWidth: Float,
        center: CGPoint
    ) -> [CGPoint] {
        let widthPx = mmToPixels(archWidth)
        let halfWidth = widthPx / 2
        
        // Golden ratio divisions
        let phi: CGFloat = 1.618
        
        // Central incisor width (as proportion of total)
        let centralWidth = widthPx / (2 * (1 + phi + phi * phi))
        
        // Lateral incisor width
        let lateralWidth = centralWidth / phi
        
        // Canine width
        let canineWidth = lateralWidth / phi
        
        var points: [CGPoint] = []
        
        // Left side
        points.append(CGPoint(x: center.x - halfWidth, y: center.y)) // Left edge
        points.append(CGPoint(x: center.x - halfWidth + canineWidth, y: center.y))
        points.append(CGPoint(x: center.x - halfWidth + canineWidth + lateralWidth, y: center.y))
        points.append(CGPoint(x: center.x - centralWidth / 2, y: center.y))
        
        // Center
        points.append(CGPoint(x: center.x, y: center.y)) // Midline
        
        // Right side (mirror)
        points.append(CGPoint(x: center.x + centralWidth / 2, y: center.y))
        points.append(CGPoint(x: center.x + halfWidth - canineWidth - lateralWidth, y: center.y))
        points.append(CGPoint(x: center.x + halfWidth - canineWidth, y: center.y))
        points.append(CGPoint(x: center.x + halfWidth, y: center.y)) // Right edge
        
        return points
    }
}
