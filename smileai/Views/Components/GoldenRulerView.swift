import SwiftUI

// MARK: - Expanded State Model
struct GoldenRulerState: Equatable {
    var start: CGPoint = .zero
    var end: CGPoint = .zero
    var isVisible: Bool = false
    
    // New Features
    var opacity: Double = 1.0
    var activeRatios: [CGFloat] = [0.382, 0.5, 0.618] // Defaults: Golden Section & Midline
    var showLabels: Bool = true
    
    /// Helper to set standard dental ratios
    mutating func setRatioType(_ type: RatioType) {
        switch type {
        case .goldenRatio:
            // The classic Phi split (Short/Long = 0.618)
            // Visualized as 38.2% and 61.8% of the total length
            self.activeRatios = [0.382, 0.618]
        case .halves:
            self.activeRatios = [0.5]
        case .thirds:
            self.activeRatios = [0.333, 0.666]
        case .dentalWidths:
            // Approximate esthetic widths (Central > Lateral > Canine)
            self.activeRatios = [0.12, 0.27, 0.50, 0.73, 0.88]
        }
    }
    
    enum RatioType {
        case goldenRatio
        case halves
        case thirds
        case dentalWidths
    }
}

// MARK: - Main Overlay View
struct GoldenRulerOverlay: View {
    var isActive: Bool
    var isLocked: Bool
    @Binding var state: GoldenRulerState
    
    var body: some View {
        ZStack {
            // Invisible Drag Layer (Only active when creating the ruler)
            Color.clear
                .contentShape(Rectangle())
                .allowsHitTesting(isActive && !state.isVisible)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            if !state.isVisible {
                                state.start = val.startLocation
                                state.end = val.location
                            }
                        }
                        .onEnded { val in
                            state.end = val.location
                            // Only confirm creation if drag length > 20px
                            if hypot(state.end.x - state.start.x, state.end.y - state.start.y) > 20 {
                                state.isVisible = true
                                state.opacity = 1.0 // Reset opacity on new creation
                            }
                        }
                )
            
            // The Ruler Visuals
            if state.isVisible {
                RulerGraphic(
                    start: state.start,
                    end: state.end,
                    ratios: state.activeRatios,
                    opacity: state.opacity,
                    showLabels: state.showLabels
                )
                // Add Context Menu for quick adjustments
                .contextMenu {
                    ControlGroup {
                        Button("50%") { state.setRatioType(.halves) }
                        Button("Golden Ratio") { state.setRatioType(.goldenRatio) }
                        Button("Dental") { state.setRatioType(.dentalWidths) }
                    }
                    Divider()
                    Text("Opacity")
                    Button("100%") { state.opacity = 1.0 }
                    Button("50%") { state.opacity = 0.5 }
                    Button("25%") { state.opacity = 0.25 }
                }
                
                // Handles for manipulating endpoints
                if !isLocked {
                    RulerHandle(pos: $state.start, color: .yellow)
                    RulerHandle(pos: $state.end, color: .yellow)
                }
            }
        }
    }
}

// MARK: - Draggable Handle
struct RulerHandle: View {
    @Binding var pos: CGPoint
    var color: Color
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
            .position(pos)
            .gesture(
                DragGesture()
                    .onChanged { val in
                        pos = val.location
                    }
            )
    }
}

// MARK: - Drawing Logic
struct RulerGraphic: View {
    var start: CGPoint
    var end: CGPoint
    var ratios: [CGFloat]
    var opacity: Double
    var showLabels: Bool
    
    var body: some View {
        Canvas { context, size in
            // 1. Calculate Geometry
            let dx = end.x - start.x
            let dy = end.y - start.y
            let len = sqrt(dx*dx + dy*dy)
            
            // Perpendicular unit vector for tick marks
            let px = -dy / len
            let py = dx / len
            
            // 2. Main Line
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(.yellow.opacity(opacity)), lineWidth: 2)
            
            // 3. End Caps
            drawTick(context: context, at: 0.0, px: px, py: py, length: 15)
            drawTick(context: context, at: 1.0, px: px, py: py, length: 15)
            
            // 4. Ratio Ticks
            for ratio in ratios {
                let isMajor = (ratio == 0.5 || ratio == 0.618 || ratio == 0.382)
                let tickLen: CGFloat = isMajor ? 12 : 8
                drawTick(context: context, at: ratio, px: px, py: py, length: tickLen, width: isMajor ? 2 : 1)
                
                // Optional: Draw percentage text
                if showLabels && isMajor {
                    let tx = start.x + dx * ratio
                    let ty = start.y + dy * ratio
                    // Offset text slightly away from line
                    let textPos = CGPoint(x: tx + px * 20, y: ty + py * 20)
                    
                    let percent = Int(ratio * 100)
                    context.draw(
                        Text("\(percent)%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.yellow.opacity(opacity)),
                        at: textPos,
                        anchor: .center
                    )
                }
            }
            
            // 5. Total Length Label (Center)
            if showLabels {
                let midX = start.x + dx * 0.5
                let midY = start.y + dy * 0.5
                // Offset below the line
                let labelPos = CGPoint(x: midX - px * 25, y: midY - py * 25)
                
                // Convert pixels to pseudo-mm (assuming standard screen DPI, approximate)
                // This is purely relative unless calibrated, but useful for ratio checks.
                let displayLen = String(format: "%.0f px", len)
                
                context.draw(
                    Text(displayLen)
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.6 * opacity))
                        .foregroundColor(.white.opacity(opacity))
                        .cornerRadius(4),
                    at: labelPos,
                    anchor: .center
                )
            }
        }
        .allowsHitTesting(false) // Let touches pass through to the drag layer
    }
    
    private func drawTick(context: GraphicsContext, at ratio: CGFloat, px: CGFloat, py: CGFloat, length: CGFloat, width: CGFloat = 2) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        
        let tx = start.x + dx * ratio
        let ty = start.y + dy * ratio
        
        var path = Path()
        path.move(to: CGPoint(x: tx - px * length, y: ty - py * length))
        path.addLine(to: CGPoint(x: tx + px * length, y: ty + py * length))
        
        context.stroke(path, with: .color(.yellow.opacity(opacity)), lineWidth: width)
    }
}
