//
//  ToothOverlayView.swift
//  smileai
//
//  2D Smile Overlay System - Tooth Overlay Rendering
//  Phase 4: UI Components
//

import SwiftUI

/// Renders individual tooth outline with optional fill
struct ToothOverlayView: View {
    
    // MARK: - Properties
    
    let tooth: ToothOverlay2D
    let outlineColor: Color
    let outlineThickness: CGFloat
    let fillOpacity: Double
    let isSelected: Bool
    
    // MARK: - Initialization
    
    init(
        tooth: ToothOverlay2D,
        outlineColor: Color = .white,
        outlineThickness: CGFloat = 2.0,
        fillOpacity: Double = 0.0,
        isSelected: Bool = false
    ) {
        self.tooth = tooth
        self.outlineColor = outlineColor
        self.outlineThickness = outlineThickness
        self.fillOpacity = fillOpacity
        self.isSelected = isSelected
    }
    
    // MARK: - Body
    
    var body: some View {
        Canvas { context, size in
            guard tooth.outlinePoints.count >= 3 else { return }
            
            // Create path from outline points
            var path = Path()
            path.move(to: tooth.outlinePoints[0])
            
            for point in tooth.outlinePoints.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
            
            // Draw fill (if enabled)
            if fillOpacity > 0 {
                let fillColor = tooth.customColor ?? outlineColor
                context.fill(
                    path,
                    with: .color(fillColor.opacity(fillOpacity))
                )
            }
            
            // Draw outline
            let strokeColor = isSelected ? Color.blue : (tooth.customColor ?? outlineColor)
            let strokeWidth = isSelected ? outlineThickness * 1.5 : outlineThickness
            
            context.stroke(
                path,
                with: .color(strokeColor),
                style: StrokeStyle(
                    lineWidth: strokeWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            
            // Draw selection highlight
            if isSelected {
                context.stroke(
                    path,
                    with: .color(.blue.opacity(0.3)),
                    style: StrokeStyle(
                        lineWidth: strokeWidth + 4,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
            
            // Draw tooth number label
            drawLabel(in: context, for: tooth)
        }
    }
    
    // MARK: - Label Drawing
    
    private func drawLabel(in context: GraphicsContext, for tooth: ToothOverlay2D) {
        let labelText = Text(tooth.toothNumber)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(outlineColor)
        
        // Position label at tooth center
        let labelPosition = tooth.position
        
        // Draw background circle
        let backgroundPath = Circle()
            .path(in: CGRect(x: labelPosition.x - 10, y: labelPosition.y - 10, width: 20, height: 20))
        
        context.fill(backgroundPath, with: .color(Color.black.opacity(0.6)))
        
        // Draw label text
        let resolvedText = context.resolve(labelText)
        context.draw(resolvedText, at: labelPosition)
    }
}

// MARK: - Advanced Rendering View

/// Advanced tooth overlay with shading and highlights
struct AdvancedToothOverlayView: View {
    
    let tooth: ToothOverlay2D
    let outlineColor: Color
    let outlineThickness: CGFloat
    let fillOpacity: Double
    let isSelected: Bool
    
    // Shading options
    let enableShading: Bool
    let shadingIntensity: Double
    
    init(
        tooth: ToothOverlay2D,
        outlineColor: Color = .white,
        outlineThickness: CGFloat = 2.0,
        fillOpacity: Double = 0.0,
        isSelected: Bool = false,
        enableShading: Bool = true,
        shadingIntensity: Double = 0.3
    ) {
        self.tooth = tooth
        self.outlineColor = outlineColor
        self.outlineThickness = outlineThickness
        self.fillOpacity = fillOpacity
        self.isSelected = isSelected
        self.enableShading = enableShading
        self.shadingIntensity = shadingIntensity
    }
    
    var body: some View {
        Canvas { context, size in
            guard tooth.outlinePoints.count >= 3 else { return }
            
            // Create path
            var path = Path()
            path.move(to: tooth.outlinePoints[0])
            for point in tooth.outlinePoints.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
            
            // Draw shading (gradient fill)
            if enableShading && fillOpacity > 0 {
                let gradient = Gradient(colors: [
                    outlineColor.opacity(fillOpacity * shadingIntensity),
                    outlineColor.opacity(fillOpacity)
                ])
                
                let center = tooth.centroid
                let radius = max(
                    tooth.boundingRect.width,
                    tooth.boundingRect.height
                ) / 2
                
                context.fill(
                    path,
                    with: .radialGradient(
                        gradient,
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            } else if fillOpacity > 0 {
                // Simple fill
                context.fill(
                    path,
                    with: .color(outlineColor.opacity(fillOpacity))
                )
            }
            
            // Draw outline with shadow
            if isSelected {
                // Selection glow
                context.stroke(
                    path,
                    with: .color(.blue.opacity(0.5)),
                    style: StrokeStyle(
                        lineWidth: outlineThickness + 6,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
            
            var shadowContext = context
            shadowContext.addFilter(.shadow(
                color: .black.opacity(0.5),
                radius: 2,
                x: 1,
                y: 1
            ))
            
            shadowContext.stroke(
                path,
                with: .color(isSelected ? .blue : outlineColor),
                style: StrokeStyle(
                    lineWidth: isSelected ? outlineThickness * 1.5 : outlineThickness,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            
            // Draw label
            drawAdvancedLabel(in: context, for: tooth)
        }
    }
    
    private func drawAdvancedLabel(in context: GraphicsContext, for tooth: ToothOverlay2D) {
        // Draw background rectangle
        let bgRect = CGRect(
            x: tooth.position.x - 15,
            y: tooth.position.y - 9,
            width: 30,
            height: 18
        )
        
        let bgPath = RoundedRectangle(cornerRadius: 8).path(in: bgRect)
        
        let gradient = Gradient(colors: [
            Color.black.opacity(0.8),
            Color.black.opacity(0.6)
        ])
        
        context.fill(bgPath, with: .linearGradient(
            gradient,
            startPoint: CGPoint(x: bgRect.minX, y: bgRect.minY),
            endPoint: CGPoint(x: bgRect.minX, y: bgRect.maxY)
        ))
        
        // Draw text
        let labelText = Text(tooth.toothNumber)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(.white)
        
        let resolvedText = context.resolve(labelText)
        context.draw(resolvedText, at: tooth.position)
    }
}

// MARK: - Preview

#if DEBUG
struct ToothOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            VStack(spacing: 40) {
                // Basic rendering
                basicToothPreview
                
                // Advanced rendering
                advancedToothPreview
            }
        }
        .frame(width: 800, height: 600)
    }
    
    static var basicToothPreview: some View {
        let tooth = createMockTooth(at: CGPoint(x: 200, y: 100))
        
        return ToothOverlayView(
            tooth: tooth,
            outlineColor: .white,
            outlineThickness: 2.0,
            fillOpacity: 0.1,
            isSelected: false
        )
    }
    
    static var advancedToothPreview: some View {
        let tooth = createMockTooth(at: CGPoint(x: 200, y: 250))
        
        return AdvancedToothOverlayView(
            tooth: tooth,
            outlineColor: .cyan,
            outlineThickness: 2.5,
            fillOpacity: 0.2,
            isSelected: true,
            enableShading: true,
            shadingIntensity: 0.4
        )
    }
    
    static func createMockTooth(at position: CGPoint) -> ToothOverlay2D {
        var tooth = ToothOverlay2D(
            toothNumber: "11",
            toothType: .central,
            position: position,
            width: 8.5,
            height: 10.5
        )
        
        // Create realistic tooth outline
        let width = CGFloat(tooth.width * 5) // Scale for visibility
        let height = CGFloat(tooth.height * 5)
        
        tooth.outlinePoints = [
            // Top (incisal edge) - slightly curved
            CGPoint(x: position.x - width/2, y: position.y - height/2),
            CGPoint(x: position.x - width/4, y: position.y - height/2 - 2),
            CGPoint(x: position.x, y: position.y - height/2 - 3),
            CGPoint(x: position.x + width/4, y: position.y - height/2 - 2),
            CGPoint(x: position.x + width/2, y: position.y - height/2),
            
            // Right side (mesial) - straight
            CGPoint(x: position.x + width/2, y: position.y),
            CGPoint(x: position.x + width/2 - 3, y: position.y + height/4),
            
            // Bottom (cervical) - curved inward
            CGPoint(x: position.x + width/3, y: position.y + height/2),
            CGPoint(x: position.x, y: position.y + height/2 + 5),
            CGPoint(x: position.x - width/3, y: position.y + height/2),
            
            // Left side (distal) - straight
            CGPoint(x: position.x - width/2 + 3, y: position.y + height/4),
            CGPoint(x: position.x - width/2, y: position.y)
        ]
        
        return tooth
    }
}
#endif
