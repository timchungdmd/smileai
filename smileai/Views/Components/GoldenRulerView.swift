import SwiftUI

// MARK: - Reference Information View
struct DentalProportionsInfoView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        Text("Dental Esthetic Proportions")
                            .font(.title2.bold())
                        
                        Text("Dental esthetic proportions use mathematical ratios, primarily the Golden Ratio (1:1.618) and Recurring Esthetic Dental (RED) proportion, to guide smile design.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Key Proportions & Ratios").font(.headline)
                        
                        InfoRow(title: "Golden Ratio (1:1.618)", desc: "A classic guide where the lateral incisor is 1 unit wide, the central incisor is 1.618 units, and the canine is 0.618 units.")
                        
                        InfoRow(title: "Golden Percentage (Snow)", desc: "Suggests the central incisor is 25% of the total anterior width, lateral is 15%, and canine is 10%.")
                        
                        InfoRow(title: "Width-to-Height Ratio", desc: "Ideal central incisors have a width about 75-80% of their height.")
                        
                        InfoRow(title: "Contact Proportions", desc: "Ideal contact points decrease moving distally: 50% (Centrals), 40% (Cen/Lat), 30% (Lat/Can).")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Application in Smile Design").font(.headline)
                        
                        InfoRow(title: "Central Incisors", desc: "The foundation of the smile. Target 75-80% W/H ratio.")
                        InfoRow(title: "Lateral Incisors", desc: "Should appear narrower than centrals to maintain dominance of the centrals.")
                        InfoRow(title: "Smile Line", desc: "The curve of the upper front teeth should follow the curve of the lower lip.")
                    }
                }
                .padding()
            }
            .navigationTitle("Reference Guide")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 600)
    }
}

struct InfoRow: View {
    let title: String
    let desc: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).bold().foregroundStyle(.primary)
            Text(desc).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - State Model
struct GoldenRulerState: Equatable {
    var start: CGPoint = .zero
    var end: CGPoint = .zero
    var isVisible: Bool = false
    
    // Appearance
    var opacity: Double = 1.0
    var showLabels: Bool = true
    
    // The active ticks (0.0 to 1.0) and their display labels
    var activeRatios: [CGFloat] = [0.5]
    var activeLabels: [String] = []
    
    /// Calculate ticks based on dental concepts
    mutating func setRatioType(_ type: RatioType) {
        switch type {
        case .halves:
            self.activeRatios = [0.5]
            self.activeLabels = ["Mid"]
            
        case .goldenPercentage:
            // Request: 23% | 15% | 12% (Symmetrical from Midline)
            self.activeRatios = [0.12, 0.27, 0.50, 0.73, 0.88]
            self.activeLabels = ["12%", "15%", "23%", "23%", "15%", "12%"]
            
        case .goldenRatio:
            // Request: 1.618 : 1 : 0.618 (Symmetrical)
            self.activeRatios = [0.0955, 0.25, 0.50, 0.75, 0.9045]
            self.activeLabels = ["0.618", "1.0", "1.618", "1.618", "1.0", "0.618"]
            
        case .dentalWidths:
            // Standard average widths
            self.activeRatios = [0.12, 0.27, 0.50, 0.73, 0.88]
            self.activeLabels = []
        }
    }
    
    enum RatioType {
        case goldenRatio      // 1.618 : 1 : 0.618
        case goldenPercentage // 23% 15% 12%
        case halves           // 50%
        case dentalWidths     // Generic
    }
}

// MARK: - Main Overlay View
struct GoldenRulerOverlay: View {
    var isActive: Bool
    var isLocked: Bool
    @Binding var state: GoldenRulerState
    @State private var showInfoSheet = false
    
    var body: some View {
        ZStack {
            // Invisible Drag Layer (Creation)
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
                            if hypot(state.end.x - state.start.x, state.end.y - state.start.y) > 20 {
                                state.isVisible = true
                                state.opacity = 1.0
                            }
                        }
                )
            
            // The Ruler Visuals
            if state.isVisible {
                RulerGraphic(
                    start: state.start,
                    end: state.end,
                    ratios: state.activeRatios,
                    labels: state.activeLabels,
                    opacity: state.opacity,
                    showLabels: state.showLabels
                )
                .contextMenu {
                    Text("Ruler Settings")
                    
                    ControlGroup {
                        Button("Golden Ratio (φ)") { state.setRatioType(.goldenRatio) }
                        Button("Golden %") { state.setRatioType(.goldenPercentage) }
                        Button("Midline") { state.setRatioType(.halves) }
                    }
                    
                    Divider()
                    Button(action: { showInfoSheet = true }) {
                        Label("Esthetic Reference", systemImage: "book")
                    }
                    
                    Divider()
                    Button("Reset Ruler", role: .destructive) {
                        state.isVisible = false
                    }
                }
                .sheet(isPresented: $showInfoSheet) {
                    DentalProportionsInfoView()
                }
                
                // Handles
                if !isLocked {
                    // Start Handle
                    RulerHandle(pos: $state.start, color: .yellow)
                    // End Handle
                    RulerHandle(pos: $state.end, color: .yellow)
                    // Center Move Handle (New)
                    RulerMoveHandle(start: $state.start, end: $state.end)
                }
            }
        }
    }
}

// MARK: - Draggable Handle (Endpoint)
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
            .gesture(DragGesture().onChanged { val in pos = val.location })
    }
}

// MARK: - Move Handle (Center)
struct RulerMoveHandle: View {
    @Binding var start: CGPoint
    @Binding var end: CGPoint
    
    // Track drag state
    @State private var dragStartP0: CGPoint?
    @State private var dragStartP1: CGPoint?
    
    // Computed Center
    var center: CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }
    
    var body: some View {
        ZStack {
            // Visual indicator for the handle
            Circle()
                .fill(Color.white.opacity(0.01)) // Mostly transparent hit area
                .frame(width: 40, height: 40) // Larger hit target
                .overlay(
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                )
        }
        .position(center)
        .gesture(
            DragGesture()
                .onChanged { val in
                    // 1. Snapshot initial positions at start of drag
                    if dragStartP0 == nil {
                        dragStartP0 = start
                        dragStartP1 = end
                    }
                    
                    // 2. Apply translation delta to both points
                    let tx = val.translation.width
                    let ty = val.translation.height
                    
                    if let p0 = dragStartP0, let p1 = dragStartP1 {
                        start = CGPoint(x: p0.x + tx, y: p0.y + ty)
                        end = CGPoint(x: p1.x + tx, y: p1.y + ty)
                    }
                }
                .onEnded { _ in
                    // 3. Reset state
                    dragStartP0 = nil
                    dragStartP1 = nil
                }
        )
    }
}

// MARK: - Drawing Logic
struct RulerGraphic: View {
    var start: CGPoint
    var end: CGPoint
    var ratios: [CGFloat]
    var labels: [String]
    var opacity: Double
    var showLabels: Bool
    
    var body: some View {
        Canvas { context, size in
            let dx = end.x - start.x
            let dy = end.y - start.y
            let len = sqrt(dx*dx + dy*dy)
            
            let px = len > 0 ? -dy / len : 0
            let py = len > 0 ? dx / len : 0
            
            // 1. Main Line
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(.yellow.opacity(opacity)), lineWidth: 2)
            
            // 2. End Caps
            drawTick(context: context, at: 0.0, px: px, py: py, length: 15, width: 2)
            drawTick(context: context, at: 1.0, px: px, py: py, length: 15, width: 2)
            
            // 3. Ratio Ticks
            for ratio in ratios {
                let isMid = abs(ratio - 0.5) < 0.01
                let tickLen: CGFloat = isMid ? 20 : 12
                let width: CGFloat = isMid ? 3 : 1.5
                
                // Draw Tick
                drawTick(context: context, at: ratio, px: px, py: py, length: tickLen, width: width)
            }
            
            // 4. Segment Labels
            if showLabels && !labels.isEmpty {
                var allPoints = [0.0] + ratios + [1.0]
                let loopCount = min(labels.count, allPoints.count - 1)
                
                for i in 0..<loopCount {
                    let p1 = allPoints[i]
                    let p2 = allPoints[i+1]
                    let mid = (p1 + p2) / 2.0
                    
                    let tx = start.x + dx * mid
                    let ty = start.y + dy * mid
                    
                    let textPos = CGPoint(x: tx + px * 20, y: ty + py * 20)
                    
                    let text = Text(labels[i])
                        .font(.system(size: 10, weight: .bold))
                    
                    var resolved = context.resolve(text)
                    resolved.shading = .color(.yellow.opacity(opacity))
                    context.draw(resolved, at: textPos, anchor: .center)
                }
            }
            
            // 5. Total Length Label
            if showLabels {
                let midX = start.x + dx * 0.5
                let midY = start.y + dy * 0.5
                let labelPos = CGPoint(x: midX - px * 35, y: midY - py * 35)
                
                let displayLen = String(format: "%.0f px", len)
                let text = Text(displayLen).font(.caption2)
                
                var resolved = context.resolve(text)
                resolved.shading = .color(.white.opacity(opacity))
                
                let textSize = resolved.measure(in: CGSize(width: 200, height: 50))
                let bgRect = CGRect(x: labelPos.x - textSize.width/2 - 2, y: labelPos.y - textSize.height/2 - 2, width: textSize.width + 4, height: textSize.height + 4)
                
                context.fill(Path(roundedRect: bgRect, cornerRadius: 4), with: .color(.black.opacity(0.6 * opacity)))
                context.draw(resolved, at: labelPos, anchor: .center)
            }
        }
        .allowsHitTesting(false)
    }
    
    private func drawTick(context: GraphicsContext, at ratio: CGFloat, px: CGFloat, py: CGFloat, length: CGFloat, width: CGFloat) {
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
