//
//  SmileOverlayState.swift
//  smileai
//
//  2D Smile Overlay System - Main State Container
//

import Foundation
import SwiftUI
import SceneKit
import Combine

/// Main state container for the 2D smile overlay system
@MainActor
class SmileOverlayState: ObservableObject {
    
    // MARK: - Photo Properties
    @Published var sourcePhoto: NSImage?
    @Published var photoSize: CGSize = .zero
    
    // MARK: - Smile Design Transform
    @Published var smileTransform: SmileTransform2D = SmileTransform2D()
    
    // MARK: - Tooth Templates
    @Published var toothOverlays: [ToothOverlay2D] = []
    
    // MARK: - Measurement Grid
    @Published var showGrid: Bool = true
    @Published var showMeasurements: Bool = true
    @Published var gridSpacing: Float = 5.0
    
    // MARK: - Visual Settings
    @Published var overlayOpacity: Double = 0.8
    @Published var outlineColor: Color = .white
    @Published var outlineThickness: CGFloat = 2.0
    @Published var showFill: Bool = false
    @Published var fillOpacity: Double = 0.1
    
    // MARK: - Interaction State
    @Published var selectedHandle: TransformHandle? = nil
    @Published var isLocked: Bool = false
    @Published var selectedToothID: UUID? = nil
    
    // MARK: - Calibration
    @Published var pixelsPerMM: Float = 10.0
    @Published var cameraCalibration: CameraCalibrationData? = nil
    @Published var measurementGrid: MeasurementGrid = MeasurementGrid()
    
    // MARK: - Undo/Redo
    private var transformHistory: [SmileTransform2D] = []
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
    
    var selectedTooth: ToothOverlay2D? {
        guard let id = selectedToothID else { return nil }
        return toothOverlays.first { $0.id == id }
    }
    
    var hasContent: Bool {
        return sourcePhoto != nil && !toothOverlays.isEmpty
    }
    
    // MARK: - Initialization
    init() {
        self.smileTransform.center = CGPoint(x: 0, y: 0)
    }
    
    // MARK: - Methods
    
    func loadPhoto(_ photo: NSImage) {
        self.sourcePhoto = photo
        self.photoSize = photo.size
        
        self.smileTransform.center = CGPoint(
            x: photoSize.width / 2,
            y: photoSize.height / 2
        )
        self.measurementGrid.origin = smileTransform.center
        
        if cameraCalibration == nil {
            cameraCalibration = CameraCalibrationData.estimate(from: photo)
            pixelsPerMM = cameraCalibration?.pixelsPerMM(photoWidth: photoSize.width) ?? 10.0
        }
    }
    
    func addTooth(_ tooth: ToothOverlay2D) {
        toothOverlays.append(tooth)
    }
    
    func removeTooth(id: UUID) {
        toothOverlays.removeAll { $0.id == id }
        if selectedToothID == id { selectedToothID = nil }
    }
    
    func clearAllTeeth() {
        toothOverlays.removeAll()
        selectedToothID = nil
    }
    
    // Select tooth at point
    func selectTooth(at point: CGPoint) -> Bool {
        // Simple hit test logic
        for tooth in transformedTeeth.reversed() {
            // Approximation for hit testing
            let rect = CGRect(
                x: tooth.position.x - tooth.scale.width/2,
                y: tooth.position.y - tooth.scale.height/2,
                width: tooth.scale.width,
                height: tooth.scale.height
            )
            if rect.contains(point) {
                selectedToothID = tooth.id
                return true
            }
        }
        selectedToothID = nil
        return false
    }
}

// MARK: - Data Structures

struct SmileTransform2D: Equatable {
    var translation: CGPoint = .zero
    var rotation: CGFloat = 0.0
    var scale: CGFloat = 1.0
    var center: CGPoint = .zero
    
    func apply(to point: CGPoint) -> CGPoint {
        var p = CGPoint(x: point.x - center.x, y: point.y - center.y)
        p.x *= scale; p.y *= scale
        let cosT = cos(rotation); let sinT = sin(rotation)
        let rot = CGPoint(x: p.x * cosT - p.y * sinT, y: p.x * sinT + p.y * cosT)
        return CGPoint(x: rot.x + center.x + translation.x, y: rot.y + center.y + translation.y)
    }
}

enum TransformHandle: Equatable {
    case center, corner, rotation
    case edge(EdgeSide)
    enum EdgeSide: String { case left, right, top, bottom }
}

struct CameraCalibrationData: Equatable {
    var focalLength: Float
    var sensorWidth: Float
    var distanceToSubject: Float
    var angle: Float
    
    static func estimate(from photo: NSImage) -> CameraCalibrationData {
        return CameraCalibrationData(focalLength: 85.0, sensorWidth: 36.0, distanceToSubject: 300.0, angle: 0.1)
    }
    
    func pixelsPerMM(photoWidth: CGFloat) -> Float {
        let fovWidth = (sensorWidth * distanceToSubject) / focalLength
        return Float(photoWidth) / fovWidth
    }
}
