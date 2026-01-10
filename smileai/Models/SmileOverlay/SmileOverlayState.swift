//
//  SmileOverlayState.swift
//  smileai
//
//  2D Smile Overlay System - Main State Container
//  Phase 1: Core Models
//

import Foundation
import SwiftUI
import SceneKit

/// Main state container for the 2D smile overlay system
@MainActor
class SmileOverlayState: ObservableObject {
    
    // MARK: - Photo Properties
    
    /// Source intraoral photograph
    @Published var sourcePhoto: NSImage?
    
    /// Photo dimensions in pixels
    @Published var photoSize: CGSize = .zero
    
    // MARK: - Smile Design Transform
    
    /// Global transform applied to entire smile design
    @Published var smileTransform: SmileTransform2D = SmileTransform2D()
    
    // MARK: - Tooth Templates
    
    /// Collection of 2D tooth overlays
    @Published var toothOverlays: [ToothOverlay2D] = []
    
    // MARK: - Measurement Grid
    
    /// Show/hide measurement grid
    @Published var showGrid: Bool = true
    
    /// Show/hide dimension labels
    @Published var showMeasurements: Bool = true
    
    /// Grid spacing in millimeters
    @Published var gridSpacing: Float = 5.0
    
    // MARK: - Visual Settings
    
    /// Opacity of tooth overlays (0.0 - 1.0)
    @Published var overlayOpacity: Double = 0.8
    
    /// Color of tooth outlines
    @Published var outlineColor: Color = .white
    
    /// Thickness of tooth outlines
    @Published var outlineThickness: CGFloat = 2.0
    
    /// Show filled teeth (semi-transparent)
    @Published var showFill: Bool = false
    
    /// Fill opacity
    @Published var fillOpacity: Double = 0.1
    
    // MARK: - Interaction State
    
    /// Currently selected transform handle
    @Published var selectedHandle: TransformHandle? = nil
    
    /// Lock transforms to prevent accidental changes
    @Published var isLocked: Bool = false
    
    /// Currently selected tooth (for individual editing)
    @Published var selectedToothID: UUID? = nil
    
    // MARK: - Calibration
    
    /// Pixels per millimeter (from camera calibration)
    @Published var pixelsPerMM: Float = 10.0
    
    /// Camera calibration data
    @Published var cameraCalibration: CameraCalibrationData? = nil
    
    // MARK: - Measurement Grid Data
    
    /// Measurement grid configuration
    @Published var measurementGrid: MeasurementGrid = MeasurementGrid()
    
    // MARK: - Undo/Redo Support
    
    /// History of transform states
    private var transformHistory: [SmileTransform2D] = []
    
    /// Current position in history
    private var historyIndex: Int = -1
    
    // MARK: - Computed Properties
    
    /// Teeth with global transform applied
    var transformedTeeth: [ToothOverlay2D] {
        return toothOverlays.map { tooth in
            var transformed = tooth
            transformed.position = smileTransform.apply(to: tooth.position)
            transformed.rotation += smileTransform.rotation
            transformed.scale *= smileTransform.scale
            return transformed
        }
    }
    
    /// Selected tooth (if any)
    var selectedTooth: ToothOverlay2D? {
        guard let id = selectedToothID else { return nil }
        return toothOverlays.first { $0.id == id }
    }
    
    /// Is there any content to display?
    var hasContent: Bool {
        return sourcePhoto != nil && !toothOverlays.isEmpty
    }
    
    /// Bounding box of all teeth
    var toothBounds: CGRect {
        guard !transformedTeeth.isEmpty else { return .zero }
        
        var minX: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var minY: CGFloat = .infinity
        var maxY: CGFloat = -.infinity
        
        for tooth in transformedTeeth {
            for point in tooth.outlinePoints {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
        }
        
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
    
    // MARK: - Initialization
    
    init() {
        // Set default transform center to photo center
        self.smileTransform.center = CGPoint(
            x: photoSize.width / 2,
            y: photoSize.height / 2
        )
    }
    
    // MARK: - Photo Management
    
    /// Load photo and initialize state
    func loadPhoto(_ photo: NSImage) {
        self.sourcePhoto = photo
        self.photoSize = photo.size
        
        // Update transform center to photo center
        self.smileTransform.center = CGPoint(
            x: photoSize.width / 2,
            y: photoSize.height / 2
        )
        
        // Update measurement grid origin
        self.measurementGrid.origin = smileTransform.center
        
        // Estimate calibration if not provided
        if cameraCalibration == nil {
            cameraCalibration = CameraCalibrationData.estimate(from: photo)
            pixelsPerMM = cameraCalibration?.pixelsPerMM(photoWidth: photoSize.width) ?? 10.0
        }
    }
    
    // MARK: - Tooth Management
    
    /// Add tooth overlay
    func addTooth(_ tooth: ToothOverlay2D) {
        toothOverlays.append(tooth)
        objectWillChange.send()
    }
    
    /// Remove tooth overlay
    func removeTooth(id: UUID) {
        toothOverlays.removeAll { $0.id == id }
        if selectedToothID == id {
            selectedToothID = nil
        }
        objectWillChange.send()
    }
    
    /// Clear all teeth
    func clearAllTeeth() {
        toothOverlays.removeAll()
        selectedToothID = nil
        objectWillChange.send()
    }
    
    // MARK: - Transform Management
    
    /// Apply new transform and record in history
    func applyTransform(_ transform: SmileTransform2D) {
        // Truncate history after current position
        if historyIndex < transformHistory.count - 1 {
            transformHistory.removeSubrange((historyIndex + 1)...)
        }
        
        // Add current transform to history
        transformHistory.append(smileTransform)
        historyIndex += 1
        
        // Apply new transform
        smileTransform = transform
        
        // Limit history size
        if transformHistory.count > 50 {
            transformHistory.removeFirst()
            historyIndex -= 1
        }
        
        objectWillChange.send()
    }
    
    /// Reset transform to identity
    func resetTransform() {
        let identity = SmileTransform2D()
        identity.center = smileTransform.center
        applyTransform(identity)
    }
    
    /// Undo last transform
    func undoTransform() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        smileTransform = transformHistory[historyIndex]
        objectWillChange.send()
    }
    
    /// Redo transform
    func redoTransform() {
        guard historyIndex < transformHistory.count - 1 else { return }
        historyIndex += 1
        smileTransform = transformHistory[historyIndex]
        objectWillChange.send()
    }
    
    var canUndo: Bool { historyIndex > 0 }
    var canRedo: Bool { historyIndex < transformHistory.count - 1 }
    
    // MARK: - Selection
    
    /// Select tooth at point
    func selectTooth(at point: CGPoint) -> Bool {
        for tooth in transformedTeeth {
            if tooth.boundingRect.contains(point) {
                selectedToothID = tooth.id
                objectWillChange.send()
                return true
            }
        }
        
        selectedToothID = nil
        objectWillChange.send()
        return false
    }
    
    // MARK: - Export
    
    /// Export state to JSON
    func exportState() -> Data? {
        let export = ExportableState(
            transform: smileTransform,
            teeth: toothOverlays,
            grid: measurementGrid,
            calibration: cameraCalibration
        )
        
        return try? JSONEncoder().encode(export)
    }
    
    /// Import state from JSON
    func importState(_ data: Data) {
        guard let export = try? JSONDecoder().decode(ExportableState.self, from: data) else {
            return
        }
        
        smileTransform = export.transform
        toothOverlays = export.teeth
        measurementGrid = export.grid
        cameraCalibration = export.calibration
        
        objectWillChange.send()
    }
}

// MARK: - Exportable State

/// Serializable state for save/load
struct ExportableState: Codable {
    var transform: SmileTransform2D
    var teeth: [ToothOverlay2D]
    var grid: MeasurementGrid
    var calibration: CameraCalibrationData?
}

// MARK: - 2D Transform

/// 2D Transform for entire smile design
struct SmileTransform2D: Codable, Equatable {
    
    /// Translation offset in pixels
    var translation: CGPoint = .zero
    
    /// Rotation in radians around center
    var rotation: CGFloat = 0.0
    
    /// Uniform scale factor
    var scale: CGFloat = 1.0
    
    /// Center point for rotation/scale
    var center: CGPoint = .zero
    
    // MARK: - Application
    
    /// Apply transform to a point
    func apply(to point: CGPoint) -> CGPoint {
        // 1. Translate to origin
        var p = CGPoint(
            x: point.x - center.x,
            y: point.y - center.y
        )
        
        // 2. Scale
        p.x *= scale
        p.y *= scale
        
        // 3. Rotate
        let cosTheta = cos(rotation)
        let sinTheta = sin(rotation)
        
        let rotated = CGPoint(
            x: p.x * cosTheta - p.y * sinTheta,
            y: p.x * sinTheta + p.y * cosTheta
        )
        
        // 4. Translate back + apply offset
        return CGPoint(
            x: rotated.x + center.x + translation.x,
            y: rotated.y + center.y + translation.y
        )
    }
    
    /// Create inverse transform
    func inverted() -> SmileTransform2D {
        var inverse = SmileTransform2D()
        inverse.center = center
        inverse.scale = 1.0 / scale
        inverse.rotation = -rotation
        inverse.translation = CGPoint(
            x: -translation.x / scale,
            y: -translation.y / scale
        )
        return inverse
    }
    
    // MARK: - Factory Methods
    
    /// Create transform from drag gesture
    static func fromDrag(
        start: CGPoint,
        end: CGPoint,
        handle: TransformHandle,
        currentTransform: SmileTransform2D
    ) -> SmileTransform2D {
        
        var transform = currentTransform
        
        switch handle {
        case .center:
            // Pure translation
            let delta = CGPoint(
                x: end.x - start.x,
                y: end.y - start.y
            )
            transform.translation.x += delta.x
            transform.translation.y += delta.y
            
        case .corner:
            // Uniform scale
            let startDist = hypot(
                start.x - transform.center.x,
                start.y - transform.center.y
            )
            let endDist = hypot(
                end.x - transform.center.x,
                end.y - transform.center.y
            )
            
            if startDist > 0 {
                let scaleFactor = endDist / startDist
                transform.scale *= scaleFactor
            }
            
        case .rotation:
            // Rotation around center
            let startAngle = atan2(
                start.y - transform.center.y,
                start.x - transform.center.x
            )
            let endAngle = atan2(
                end.y - transform.center.y,
                end.x - transform.center.x
            )
            
            transform.rotation += (endAngle - startAngle)
            
        case .edge(let side):
            // Anisotropic scale (width or height)
            switch side {
            case .left, .right:
                let startDist = abs(start.x - transform.center.x)
                let endDist = abs(end.x - transform.center.x)
                if startDist > 0 {
                    transform.scale *= endDist / startDist
                }
            case .top, .bottom:
                let startDist = abs(start.y - transform.center.y)
                let endDist = abs(end.y - transform.center.y)
                if startDist > 0 {
                    transform.scale *= endDist / startDist
                }
            }
        }
        
        return transform
    }
}

// MARK: - Transform Handle Types

enum TransformHandle: Equatable, Codable {
    case center              // Move entire design
    case corner              // Scale uniformly
    case rotation            // Rotate around center
    case edge(EdgeSide)      // Scale width or height
    
    enum EdgeSide: String, Codable {
        case left
        case right
        case top
        case bottom
    }
}

// MARK: - Camera Calibration Data

/// Camera calibration parameters
struct CameraCalibrationData: Codable, Equatable {
    
    /// Focal length in millimeters
    var focalLength: Float
    
    /// Sensor width in millimeters
    var sensorWidth: Float
    
    /// Distance to subject in millimeters
    var distanceToSubject: Float
    
    /// Camera pitch angle in radians (downward tilt)
    var angle: Float
    
    // MARK: - Factory Methods
    
    /// Estimate calibration from photo (if EXIF unavailable)
    static func estimate(from photo: NSImage) -> CameraCalibrationData {
        // Typical intraoral camera specs
        return CameraCalibrationData(
            focalLength: 85.0,      // mm (macro lens)
            sensorWidth: 36.0,      // mm (full frame)
            distanceToSubject: 300.0, // mm (typical working distance)
            angle: 0.1              // ~6 degrees downward tilt
        )
    }
    
    /// Calculate pixels per millimeter at subject distance
    func pixelsPerMM(photoWidth: CGFloat) -> Float {
        // Field of view width at subject distance
        let fovWidth = (sensorWidth * distanceToSubject) / focalLength
        return Float(photoWidth) / fovWidth
    }
}
