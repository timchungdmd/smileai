import Foundation
import SwiftUI
import Combine

/// Manages interactive transform handles and gesture processing
@MainActor
class TransformController: ObservableObject {
    
    @Published var handles: [TransformHandleData] = []
    @Published var isDragging: Bool = false
    @Published var dragStartPoint: CGPoint = .zero
    @Published var activeHandle: TransformHandle? = nil
    @Published var snapToGrid: Bool = false
    var snapTolerance: CGFloat = 10.0
    
    private weak var state: SmileOverlayState?
    private var transformAtDragStart: SmileTransform2D?
    
    init(state: SmileOverlayState) {
        self.state = state
        updateHandles()
    }
    
    func updateHandles() {
        guard let state = state else { return }
        
        let bounds = calculateBounds(for: state.transformedTeeth)
        let center = state.smileTransform.center
        
        let topLeft = CGPoint(x: bounds.minX, y: bounds.minY)
        let topRight = CGPoint(x: bounds.maxX, y: bounds.minY)
        let bottomLeft = CGPoint(x: bounds.minX, y: bounds.maxY)
        let bottomRight = CGPoint(x: bounds.maxX, y: bounds.maxY)
        
        let midTop = CGPoint(x: center.x, y: bounds.minY)
        let midBottom = CGPoint(x: center.x, y: bounds.maxY)
        let midLeft = CGPoint(x: bounds.minX, y: center.y)
        let midRight = CGPoint(x: bounds.maxX, y: center.y)
        
        handles = [
            TransformHandleData(type: .center, position: center, size: 40, color: .blue, icon: "arrow.up.and.down.and.arrow.left.and.right"),
            TransformHandleData(type: .corner, position: topLeft, size: 20, color: .green, icon: "arrow.up.left.and.arrow.down.right"),
            TransformHandleData(type: .corner, position: topRight, size: 20, color: .green, icon: "arrow.up.left.and.arrow.down.right"),
            TransformHandleData(type: .corner, position: bottomLeft, size: 20, color: .green, icon: "arrow.up.left.and.arrow.down.right"),
            TransformHandleData(type: .corner, position: bottomRight, size: 20, color: .green, icon: "arrow.up.left.and.arrow.down.right"),
            TransformHandleData(type: .edge(.left), position: midLeft, size: 16, color: .cyan, icon: "arrow.left.and.right"),
            TransformHandleData(type: .edge(.right), position: midRight, size: 16, color: .cyan, icon: "arrow.left.and.right"),
            TransformHandleData(type: .edge(.top), position: midTop, size: 16, color: .cyan, icon: "arrow.up.and.down"),
            TransformHandleData(type: .edge(.bottom), position: midBottom, size: 16, color: .cyan, icon: "arrow.up.and.down"),
            TransformHandleData(type: .rotation, position: CGPoint(x: bounds.maxX + 50, y: center.y), size: 30, color: .yellow, icon: "arrow.triangle.2.circlepath")
        ]
    }
    
    private func calculateBounds(for teeth: [ToothOverlay2D]) -> CGRect {
        // Safe default if no teeth exist
        guard !teeth.isEmpty else { return CGRect(x: -50, y: -50, width: 100, height: 100) }
        
        var minX: CGFloat = .infinity; var maxX: CGFloat = -.infinity
        var minY: CGFloat = .infinity; var maxY: CGFloat = -.infinity
        
        for tooth in teeth where tooth.visible {
            for point in tooth.outlinePoints {
                minX = min(minX, point.x); maxX = max(maxX, point.x)
                minY = min(minY, point.y); maxY = max(maxY, point.y)
            }
        }
        
        // FIX: Check if bounds are still infinite (e.g. teeth exist but have no points)
        // This prevents the NaN crash when calculating width/height
        if minX == .infinity || maxX == -.infinity || minY == .infinity || maxY == -.infinity {
             return CGRect(x: -50, y: -50, width: 100, height: 100)
        }
        
        let padding: CGFloat = 10
        return CGRect(x: minX - padding, y: minY - padding, width: (maxX - minX) + 2 * padding, height: (maxY - minY) + 2 * padding)
    }
    
    func handleDragStart(at location: CGPoint) {
        guard let state = state, !state.isLocked else { return }
        for handle in handles {
            if hypot(location.x - handle.position.x, location.y - handle.position.y) < handle.size {
                activeHandle = handle.type
                dragStartPoint = location
                transformAtDragStart = state.smileTransform
                isDragging = true
                return
            }
        }
    }
    
    func handleDragChanged(to location: CGPoint) {
        guard isDragging, let handle = activeHandle, let state = state, let startTransform = transformAtDragStart else { return }
        var snapped = location
        if snapToGrid, let grid = state.measurementGrid as MeasurementGrid? { snapped = snapToGridPoint(location, grid: grid) }
        let newTransform = SmileTransform2D.fromDrag(start: dragStartPoint, end: snapped, handle: handle, currentTransform: startTransform)
        state.smileTransform = applyConstraints(to: newTransform)
        updateHandles()
    }
    
    func handleDragEnded() {
        guard isDragging else { return }
        state?.applyTransform(state!.smileTransform)
        isDragging = false; activeHandle = nil; transformAtDragStart = nil
    }
    
    private func applyConstraints(to transform: SmileTransform2D) -> SmileTransform2D {
        var constrained = transform
        constrained.scale = max(0.1, min(5.0, constrained.scale))
        return constrained
    }
    
    private func snapToGridPoint(_ point: CGPoint, grid: MeasurementGrid) -> CGPoint {
        let spacingPx = grid.mmToPixels(grid.spacing)
        let sx = round((point.x - grid.origin.x)/spacingPx)*spacingPx + grid.origin.x
        let sy = round((point.y - grid.origin.y)/spacingPx)*spacingPx + grid.origin.y
        if abs(point.x - sx) < snapTolerance && abs(point.y - sy) < snapTolerance { return CGPoint(x: sx, y: sy) }
        return point
    }
    
    func alignToMidline() {
        guard let state = state, let mid = state.measurementGrid.midline else { return }
        var t = state.smileTransform
        t.translation.x = mid - t.center.x
        state.applyTransform(t)
        updateHandles()
    }
    
    func autoLevel() {
        guard let state = state else { return }
        var t = state.smileTransform
        t.rotation = 0
        state.applyTransform(t)
        updateHandles()
    }
    
    func applyPreset(_ preset: TransformPreset) {
        guard let state = state else { return }
        var transform = state.smileTransform
        switch preset {
        case .fit:
            if let size = state.sourcePhoto?.size {
                let w = calculateBounds(for: state.toothOverlays).width
                transform.scale = (size.width * 0.8) / max(w, 1)
            }
        case .center:
            if let size = state.sourcePhoto?.size {
                transform.translation = .zero
                transform.center = CGPoint(x: size.width/2, y: size.height/2)
            }
        case .original:
            transform = SmileTransform2D()
            transform.center = state.smileTransform.center
        }
        state.applyTransform(transform)
        updateHandles()
    }
    
    func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in if !self.isDragging { self.handleDragStart(at: v.startLocation) }; self.handleDragChanged(to: v.location) }
            .onEnded { _ in self.handleDragEnded() }
    }
    
    func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { v in
                guard let state = self.state else { return }
                var t = state.smileTransform
                t.scale *= v
                t.scale = max(0.1, min(5.0, t.scale))
                state.smileTransform = t
                self.updateHandles()
            }
            .onEnded { _ in self.state?.applyTransform(self.state!.smileTransform) }
    }
    
    func rotationGesture() -> some Gesture {
        RotationGesture()
            .onChanged { v in
                guard let state = self.state else { return }
                var t = state.smileTransform
                t.rotation += v.radians
                state.smileTransform = t
                self.updateHandles()
            }
            .onEnded { _ in self.state?.applyTransform(self.state!.smileTransform) }
    }
}

struct TransformHandleData: Identifiable {
    let id = UUID()
    var type: TransformHandle
    var position: CGPoint
    var size: CGFloat
    var color: Color
    var icon: String
    var isHovered: Bool = false
    var hitRect: CGRect { let h = size/2; return CGRect(x: position.x - h, y: position.y - h, width: size, height: size) }
}

enum TransformPreset { case fit, center, original }
