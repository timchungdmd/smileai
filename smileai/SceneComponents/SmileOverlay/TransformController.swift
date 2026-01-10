//
//  TransformController.swift
//  smileai
//
//  2D Smile Overlay System - Transform Handle Controller
//  Phase 3: Transform System
//

import Foundation
import SwiftUI
import Combine

/// Manages interactive transform handles and gesture processing
@MainActor
class TransformController: ObservableObject {
    
    // MARK: - Properties
    
    /// Transform handle data
    @Published var handles: [TransformHandleData] = []
    
    /// Currently active drag state
    @Published var isDragging: Bool = false
    
    /// Start point of current drag
    @Published var dragStartPoint: CGPoint = .zero
    
    /// Currently active handle
    @Published var activeHandle: TransformHandle? = nil
    
    /// Snap to grid during transform
    @Published var snapToGrid: Bool = false
    
    /// Grid snap tolerance (pixels)
    var snapTolerance: CGFloat = 10.0
    
    /// Reference to state
    private weak var state: SmileOverlayState?
    
    /// Transform at start of drag (for undo)
    private var transformAtDragStart: SmileTransform2D?
    
    // MARK: - Initialization
    
    init(state: SmileOverlayState) {
        self.state = state
        updateHandles()
    }
    
    // MARK: - Handle Management
    
    /// Regenerate handle positions based on current transform
    func updateHandles() {
        guard let state = state else { return }
        
        let bounds = calculateBounds(for: state.transformedTeeth)
        let center = state.smileTransform.center
        
        // Calculate handle positions
        let topLeft = CGPoint(x: bounds.minX, y: bounds.minY)
        let topRight = CGPoint(x: bounds.maxX, y: bounds.minY)
        let bottomLeft = CGPoint(x: bounds.minX, y: bounds.maxY)
        let bottomRight = CGPoint(x: bounds.maxX, y: bounds.maxY)
        
        let midTop = CGPoint(x: center.x, y: bounds.minY)
        let midBottom = CGPoint(x: center.x, y: bounds.maxY)
        let midLeft = CGPoint(x: bounds.minX, y: center.y)
        let midRight = CGPoint(x: bounds.maxX, y: center.y)
        
        handles = [
            // Center handle (move) - Blue
            TransformHandleData(
                type: .center,
                position: center,
                size: 40,
                color: .blue,
                icon: "arrow.up.and.down.and.arrow.left.and.right"
            ),
            
            // Corner handles (scale) - Green
            TransformHandleData(
                type: .corner,
                position: topLeft,
                size: 20,
                color: .green,
                icon: "arrow.up.left.and.arrow.down.right"
            ),
            TransformHandleData(
                type: .corner,
                position: topRight,
                size: 20,
                color: .green,
                icon: "arrow.up.left.and.arrow.down.right"
            ),
            TransformHandleData(
                type: .corner,
                position: bottomLeft,
                size: 20,
                color: .green,
                icon: "arrow.up.left.and.arrow.down.right"
            ),
            TransformHandleData(
                type: .corner,
                position: bottomRight,
                size: 20,
                color: .green,
                icon: "arrow.up.left.and.arrow.down.right"
            ),
            
            // Edge handles (width/height scale) - Cyan
            TransformHandleData(
                type: .edge(.left),
                position: midLeft,
                size: 16,
                color: .cyan,
                icon: "arrow.left.and.right"
            ),
            TransformHandleData(
                type: .edge(.right),
                position: midRight,
                size: 16,
                color: .cyan,
                icon: "arrow.left.and.right"
            ),
            TransformHandleData(
                type: .edge(.top),
                position: midTop,
                size: 16,
                color: .cyan,
                icon: "arrow.up.and.down"
            ),
            TransformHandleData(
                type: .edge(.bottom),
                position: midBottom,
                size: 16,
                color: .cyan,
                icon: "arrow.up.and.down"
            ),
            
            // Rotation handle (right side) - Yellow
            TransformHandleData(
                type: .rotation,
                position: CGPoint(x: bounds.maxX + 50, y: center.y),
                size: 30,
                color: .yellow,
                icon: "arrow.triangle.2.circlepath"
            )
        ]
    }
    
    /// Calculate bounding box of all teeth
    private func calculateBounds(for teeth: [ToothOverlay2D]) -> CGRect {
        guard !teeth.isEmpty else {
            // Return default bounds around center
            return CGRect(x: -50, y: -50, width: 100, height: 100)
        }
        
        var minX: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var minY: CGFloat = .infinity
        var maxY: CGFloat = -.infinity
        
        for tooth in teeth where tooth.visible {
            for point in tooth.outlinePoints {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
        }
        
        // Add padding
        let padding: CGFloat = 10
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + 2 * padding,
            height: (maxY - minY) + 2 * padding
        )
    }
    
    // MARK: - Gesture Handling
    
    /// Handle drag gesture start
    func handleDragStart(at location: CGPoint) {
        guard let state = state else { return }
        
        // Don't start drag if locked
        guard !state.isLocked else { return }
        
        // Find which handle was clicked
        for handle in handles {
            let distance = hypot(
                location.x - handle.position.x,
                location.y - handle.position.y
            )
            
            if distance < handle.size {
                activeHandle = handle.type
                dragStartPoint = location
                transformAtDragStart = state.smileTransform
                isDragging = true
                
                // Haptic feedback
                #if os(macOS)
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .alignment,
                    performanceTime: .now
                )
                #endif
                
                return
            }
        }
    }
    
    /// Handle drag gesture changed
    func handleDragChanged(to location: CGPoint) {
        guard isDragging,
              let handle = activeHandle,
              let state = state,
              let startTransform = transformAtDragStart else {
            return
        }
        
        // Apply snap to grid if enabled
        var snappedLocation = location
        if snapToGrid, let grid = state.measurementGrid as MeasurementGrid? {
            snappedLocation = snapToGridPoint(location, grid: grid)
        }
        
        // Calculate new transform
        let newTransform = SmileTransform2D.fromDrag(
            start: dragStartPoint,
            end: snappedLocation,
            handle: handle,
            currentTransform: startTransform
        )
        
        // Apply constraints
        let constrainedTransform = applyConstraints(to: newTransform)
        
        state.smileTransform = constrainedTransform
        updateHandles()
    }
    
    /// Handle drag gesture ended
    func handleDragEnded() {
        guard isDragging else { return }
        
        // Record transform in history
        if let state = state {
            state.applyTransform(state.smileTransform)
        }
        
        isDragging = false
        activeHandle = nil
        transformAtDragStart = nil
        
        // Haptic feedback
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
        #endif
    }
    
    // MARK: - Transform Constraints
    
    /// Apply constraints to transform
    private func applyConstraints(to transform: SmileTransform2D) -> SmileTransform2D {
        var constrained = transform
        
        // Limit scale
        constrained.scale = max(0.1, min(5.0, constrained.scale))
        
        // Normalize rotation to [-π, π]
        while constrained.rotation > .pi {
            constrained.rotation -= 2 * .pi
        }
        while constrained.rotation < -.pi {
            constrained.rotation += 2 * .pi
        }
        
        return constrained
    }
    
    /// Snap point to grid
    private func snapToGridPoint(_ point: CGPoint, grid: MeasurementGrid) -> CGPoint {
        let spacingPx = grid.mmToPixels(grid.spacing)
        
        // Calculate nearest grid point
        let snappedX = round((point.x - grid.origin.x) / spacingPx) * spacingPx + grid.origin.x
        let snappedY = round((point.y - grid.origin.y) / spacingPx) * spacingPx + grid.origin.y
        
        // Only snap if within tolerance
        let dx = abs(point.x - snappedX)
        let dy = abs(point.y - snappedY)
        
        if dx < snapTolerance && dy < snapTolerance {
            return CGPoint(x: snappedX, y: snappedY)
        }
        
        return point
    }
    
    // MARK: - Keyboard Shortcuts
    
    /// Handle keyboard nudge
    func nudge(direction: NudgeDirection, amount: CGFloat = 1.0) {
        guard let state = state else { return }
        
        var transform = state.smileTransform
        
        switch direction {
        case .left:
            transform.translation.x -= amount
        case .right:
            transform.translation.x += amount
        case .up:
            transform.translation.y -= amount
        case .down:
            transform.translation.y += amount
        }
        
        state.applyTransform(transform)
        updateHandles()
    }
    
    /// Scale by keyboard
    func scaleBy(factor: CGFloat) {
        guard let state = state else { return }
        
        var transform = state.smileTransform
        transform.scale *= factor
        transform.scale = max(0.1, min(5.0, transform.scale))
        
        state.applyTransform(transform)
        updateHandles()
    }
    
    /// Rotate by keyboard
    func rotateBy(angle: CGFloat) {
        guard let state = state else { return }
        
        var transform = state.smileTransform
        transform.rotation += angle
        
        state.applyTransform(transform)
        updateHandles()
    }
    
    // MARK: - Smart Alignment
    
    /// Align to midline
    func alignToMidline() {
        guard let state = state,
              let midline = state.measurementGrid.midline else {
            return
        }
        
        var transform = state.smileTransform
        transform.translation.x = midline - transform.center.x
        
        state.applyTransform(transform)
        updateHandles()
    }
    
    /// Align to occlusal plane
    func alignToOcclusalPlane() {
        guard let state = state,
              let occlusalPlane = state.measurementGrid.occlusalPlane else {
            return
        }
        
        var transform = state.smileTransform
        transform.translation.y = occlusalPlane - transform.center.y
        
        state.applyTransform(transform)
        updateHandles()
    }
    
    /// Auto-level (set rotation to 0)
    func autoLevel() {
        guard let state = state else { return }
        
        var transform = state.smileTransform
        transform.rotation = 0
        
        state.applyTransform(transform)
        updateHandles()
    }
    
    /// Reset to identity transform
    func resetTransform() {
        guard let state = state else { return }
        state.resetTransform()
        updateHandles()
    }
}

// MARK: - Transform Handle Data

/// Data for a single transform handle
struct TransformHandleData: Identifiable {
    let id = UUID()
    var type: TransformHandle
    var position: CGPoint
    var size: CGFloat
    var color: Color
    var icon: String
    
    /// Is this handle currently hovered
    var isHovered: Bool = false
    
    /// Hit test rect
    var hitRect: CGRect {
        let halfSize = size / 2
        return CGRect(
            x: position.x - halfSize,
            y: position.y - halfSize,
            width: size,
            height: size
        )
    }
}

// MARK: - Nudge Direction

enum NudgeDirection {
    case left
    case right
    case up
    case down
}

// MARK: - Transform Presets

extension TransformController {
    
    /// Apply preset transform
    func applyPreset(_ preset: TransformPreset) {
        guard let state = state else { return }
        
        var transform = state.smileTransform
        
        switch preset {
        case .fit:
            // Scale to fit photo
            if let photoSize = state.sourcePhoto?.size {
                let boundsWidth = calculateBounds(for: state.toothOverlays).width
                let targetWidth = photoSize.width * 0.8
                transform.scale = targetWidth / boundsWidth
            }
            
        case .center:
            // Center in photo
            if let photoSize = state.sourcePhoto?.size {
                transform.translation = .zero
                transform.center = CGPoint(
                    x: photoSize.width / 2,
                    y: photoSize.height / 2
                )
            }
            
        case .original:
            // Reset to original
            transform = SmileTransform2D()
            transform.center = state.smileTransform.center
        }
        
        state.applyTransform(transform)
        updateHandles()
    }
}

enum TransformPreset {
    case fit      // Scale to fit photo
    case center   // Center in photo
    case original // Reset to original size
}

// MARK: - Gesture Recognizer Integration

extension TransformController {
    
    /// Create drag gesture for SwiftUI
    func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !self.isDragging {
                    self.handleDragStart(at: value.startLocation)
                }
                self.handleDragChanged(to: value.location)
            }
            .onEnded { _ in
                self.handleDragEnded()
            }
    }
    
    /// Create magnification gesture for pinch-to-zoom
    func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard let state = self.state else { return }
                
                var transform = state.smileTransform
                transform.scale *= value
                transform.scale = max(0.1, min(5.0, transform.scale))
                
                state.smileTransform = transform
                self.updateHandles()
            }
            .onEnded { _ in
                if let state = self.state {
                    state.applyTransform(state.smileTransform)
                }
            }
    }
    
    /// Create rotation gesture
    func rotationGesture() -> some Gesture {
        RotationGesture()
            .onChanged { value in
                guard let state = self.state else { return }
                
                var transform = state.smileTransform
                transform.rotation += value.radians
                
                state.smileTransform = transform
                self.updateHandles()
            }
            .onEnded { _ in
                if let state = self.state {
                    state.applyTransform(state.smileTransform)
                }
            }
    }
}
