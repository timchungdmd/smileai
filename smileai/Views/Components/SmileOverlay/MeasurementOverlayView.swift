//
//  MeasurementOverlayView.swift
//  smileai
//
//  2D Smile Overlay System - Measurement Grid Overlay
//  Phase 4: UI Components
//

import SwiftUI

/// Renders measurement grid, reference lines, and annotations
struct MeasurementOverlayView: View {
    
    // MARK: - Properties
    
    let grid: MeasurementGrid
    let bounds: CGSize
    
    // MARK: - Body
    
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: bounds)
            
            // 1. Draw grid lines
            drawGridLines(in: context, rect: rect)
            
            // 2. Draw reference lines
            drawReferenceLines(in: context, rect: rect)
            
            // 3. Draw annotations
            drawAnnotations(in: context)
        }
    }
    
    // MARK: - Grid Lines
    
    private func drawGridLines(in context: GraphicsContext, rect: CGRect) {
        let gridLines = grid.generateGridLines(in: rect)
        
        for line in gridLines {
            var path = Path()
            path.move(to: line.start)
            path.addLine(to: line.end)
            
            context.stroke(
                path,
                with: .color(grid.lineColor.opacity(grid.lineOpacity)),
                style: StrokeStyle(
                    lineWidth: grid.lineWidth,
                    lineCap: .round
                )
            )
            
            // Draw labels
            if grid.showLabels && !line.label.isEmpty {
                let labelPosition = calculateLabelPosition(for: line)
                
                let labelText = Text(line.label)
                    .font(.system(size: grid.labelFontSize, design: .monospaced))
                    .foregroundColor(grid.lineColor)
                
                // Background for label
                let bgRect = RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 40, height: 16)
                
                var labelContext = context
                labelContext.translateBy(x: labelPosition.x, y: labelPosition.y)
                labelContext.draw(bgRect.offset(x: -20, y: -8), at: .zero)
                
                context.draw(labelText, at: labelPosition)
            }
        }
    }
    
    private func calculateLabelPosition(for line: GridLine) -> CGPoint {
        switch line.orientation {
        case .horizontal:
            // Place label on left side
            return CGPoint(x: 30, y: line.start.y)
        case .vertical:
            // Place label on top
            return CGPoint(x: line.start.x, y: 20)
        }
    }
    
    // MARK: - Reference Lines
    
    private func drawReferenceLines(in context: GraphicsContext, rect: CGRect) {
        let referenceLines = grid.generateReferenceLines(in: rect)
        
        for refLine in referenceLines {
            if refLine.points.isEmpty {
                // Straight line
                drawStraightReferenceLine(refLine, in: context)
            } else {
                // Curve (e.g., smile line)
                drawCurvedReferenceLine(refLine, in: context)
            }
        }
    }
    
    private func drawStraightReferenceLine(
        _ line: ReferenceLine,
        in context: GraphicsContext
    ) {
        var path = Path()
        path.move(to: line.start)
        path.addLine(to: line.end)
        
        // Color based on type
        let color = colorForReferenceType(line.type)
        
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: grid.referenceLineWidth,
                lineCap: .round,
                dash: grid.referenceDashPattern
            )
        )
        
        // Draw label
        if !line.label.isEmpty {
            let midPoint = CGPoint(
                x: (line.start.x + line.end.x) / 2,
                y: (line.start.y + line.end.y) / 2
            )
            
            drawReferenceLabel(line.label, at: midPoint, in: context, color: color)
        }
    }
    
    private func drawCurvedReferenceLine(
        _ line: ReferenceLine,
        in context: GraphicsContext
    ) {
        guard line.points.count >= 2 else { return }
        
        var path = Path()
        path.move(to: line.points[0])
        
        // Use smooth curve through points
        for i in 1..<line.points.count {
            path.addLine(to: line.points[i])
        }
        
        let color = colorForReferenceType(line.type)
        
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: grid.referenceLineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
        
        // Draw label at midpoint
        if !line.label.isEmpty {
            let midIndex = line.points.count / 2
            let midPoint = line.points[midIndex]
            drawReferenceLabel(line.label, at: midPoint, in: context, color: color)
        }
    }
    
    private func colorForReferenceType(_ type: ReferenceLine.ReferenceType) -> Color {
        switch type {
        case .midline:
            return .cyan
        case .occlusalPlane:
            return .yellow
        case .pupillaryLine:
            return .orange
        case .smileLine:
            return .pink
        case .custom:
            return grid.referenceLineColor
        }
    }
    
    private func drawReferenceLabel(
        _ text: String,
        at position: CGPoint,
        in context: GraphicsContext,
        color: Color
    ) {
        let label = Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(color)
        
        // Background
        let bgRect = RoundedRectangle(cornerRadius: 4)
            .fill(Color.black.opacity(0.8))
            .frame(width: CGFloat(text.count * 8 + 10), height: 20)
        
        var labelContext = context
        labelContext.translateBy(x: position.x, y: position.y - 10)
        labelContext.draw(
            bgRect.offset(x: -CGFloat(text.count * 4 + 5), y: 0),
            at: .zero
        )
        
        context.draw(label, at: CGPoint(x: position.x, y: position.y))
    }
    
    // MARK: - Annotations
    
    private func drawAnnotations(in context: GraphicsContext) {
        for annotation in grid.annotations {
            switch annotation.type {
            case .distance, .dimension:
                drawDistanceAnnotation(annotation, in: context)
            case .angle:
                drawAngleAnnotation(annotation, in: context)
            case .ratio:
                drawRatioAnnotation(annotation, in: context)
            case .note:
                drawNoteAnnotation(annotation, in: context)
            case .area:
                drawAreaAnnotation(annotation, in: context)
            }
        }
    }
    
    private func drawDistanceAnnotation(
        _ annotation: MeasurementAnnotation,
        in context: GraphicsContext
    ) {
        guard annotation.points.count >= 2 else { return }
        
        let start = annotation.points[0]
        let end = annotation.points[1]
        
        // Draw line
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        
        let color = annotation.color ?? .yellow
        
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: 2,
                lineCap: .round
            )
        )
        
        // Draw endpoints
        context.fill(
            Circle().path(in: CGRect(
                x: start.x - 4,
                y: start.y - 4,
                width: 8,
                height: 8
            )),
            with: .color(color)
        )
        
        context.fill(
            Circle().path(in: CGRect(
                x: end.x - 4,
                y: end.y - 4,
                width: 8,
                height: 8
            )),
            with: .color(color)
        )
        
        // Draw label
        let midPoint = CGPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2
        )
        
        drawAnnotationLabel(
            annotation.valueString,
            at: midPoint,
            in: context,
            color: color
        )
    }
    
    private func drawAngleAnnotation(
        _ annotation: MeasurementAnnotation,
        in context: GraphicsContext
    ) {
        guard annotation.points.count >= 3 else { return }
        
        let point1 = annotation.points[0]
        let vertex = annotation.points[1]
        let point2 = annotation.points[2]
        
        // Draw lines
        var path = Path()
        path.move(to: vertex)
        path.addLine(to: point1)
        path.move(to: vertex)
        path.addLine(to: point2)
        
        let color = annotation.color ?? .orange
        
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: 2,
                lineCap: .round
            )
        )
        
        // Draw arc at vertex
        let radius: CGFloat = 20
        let angle1 = atan2(point1.y - vertex.y, point1.x - vertex.x)
        let angle2 = atan2(point2.y - vertex.y, point2.x - vertex.x)
        
        var arcPath = Path()
        arcPath.addArc(
            center: vertex,
            radius: radius,
            startAngle: Angle(radians: Double(angle1)),
            endAngle: Angle(radians: Double(angle2)),
            clockwise: false
        )
        
        context.stroke(
            arcPath,
            with: .color(color.opacity(0.7)),
            lineWidth: 2
        )
        
        // Draw label
        drawAnnotationLabel(
            annotation.valueString,
            at: vertex,
            in: context,
            color: color
        )
    }
    
    private func drawRatioAnnotation(
        _ annotation: MeasurementAnnotation,
        in context: GraphicsContext
    ) {
        guard annotation.points.count >= 2 else { return }
        
        let point1 = annotation.points[0]
        let point2 = annotation.points[1]
        
        // Draw connection line
        var path = Path()
        path.move(to: point1)
        path.addLine(to: point2)
        
        let color = annotation.color ?? .purple
        
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: 2,
                lineCap: .round,
                dash: [4, 4]
            )
        )
        
        // Draw label
        let midPoint = CGPoint(
            x: (point1.x + point2.x) / 2,
            y: (point1.y + point2.y) / 2
        )
        
        let labelText = "\(annotation.label): \(annotation.valueString)"
        drawAnnotationLabel(labelText, at: midPoint, in: context, color: color)
    }
    
    private func drawNoteAnnotation(
        _ annotation: MeasurementAnnotation,
        in context: GraphicsContext
    ) {
        guard let position = annotation.points.first else { return }
        
        let color = annotation.color ?? .white
        
        // Draw marker
        context.fill(
            Circle().path(in: CGRect(
                x: position.x - 6,
                y: position.y - 6,
                width: 12,
                height: 12
            )),
            with: .color(color)
        )
        
        // Draw label
        drawAnnotationLabel(
            annotation.label,
            at: CGPoint(x: position.x, y: position.y - 20),
            in: context,
            color: color
        )
    }
    
    private func drawAreaAnnotation(
        _ annotation: MeasurementAnnotation,
        in context: GraphicsContext
    ) {
        guard annotation.points.count >= 3 else { return }
        
        // Draw polygon
        var path = Path()
        path.move(to: annotation.points[0])
        for point in annotation.points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        
        let color = annotation.color ?? .green
        
        // Fill with semi-transparent color
        context.fill(path, with: .color(color.opacity(0.2)))
        
        // Stroke outline
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: 2,
                lineCap: .round,
                lineJoin: .round
            )
        )
        
        // Draw label at center
        let center = annotation.centerPoint
        drawAnnotationLabel(
            annotation.valueString,
            at: center,
            in: context,
            color: color
        )
    }
    
    private func drawAnnotationLabel(
        _ text: String,
        at position: CGPoint,
        in context: GraphicsContext,
        color: Color
    ) {
        let label = Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(color)
        
        // Background
        let textWidth = CGFloat(text.count * 7 + 8)
        let bgRect = RoundedRectangle(cornerRadius: 4)
            .fill(Color.black.opacity(0.85))
            .frame(width: textWidth, height: 20)
        
        var labelContext = context
        labelContext.translateBy(x: position.x, y: position.y)
        labelContext.draw(bgRect.offset(x: -textWidth/2, y: -10), at: .zero)
        
        context.draw(label, at: position)
    }
}

// MARK: - Preview

#if DEBUG
struct MeasurementOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            MeasurementOverlayView(
                grid: createMockGrid(),
                bounds: CGSize(width: 800, height: 600)
            )
        }
        .frame(width: 800, height: 600)
    }
    
    static func createMockGrid() -> MeasurementGrid {
        var grid = MeasurementGrid(
            origin: CGPoint(x: 400, y: 300),
            spacing: 10.0,
            pixelsPerMM: 5.0
        )
        
        // Add midline
        grid.midline = 400
        
        // Add occlusal plane
        grid.occlusalPlane = 300
        
        // Add annotations
        let distAnnotation = MeasurementAnnotation.distance(
            from: CGPoint(x: 300, y: 250),
            to: CGPoint(x: 500, y: 250),
            pixelsPerMM: 5.0
        )
        grid.addAnnotation(distAnnotation)
        
        let angleAnnotation = MeasurementAnnotation.angle(
            point1: CGPoint(x: 350, y: 350),
            vertex: CGPoint(x: 400, y: 350),
            point2: CGPoint(x: 450, y: 320)
        )
        grid.addAnnotation(angleAnnotation)
        
        return grid
    }
}
#endif
