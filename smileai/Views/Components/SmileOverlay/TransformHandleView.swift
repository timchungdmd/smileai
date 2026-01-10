//
//  TransformHandleView.swift
//  smileai
//
//  2D Smile Overlay System - Transform Handle Visualization
//  Phase 4: UI Components
//

import SwiftUI

/// Interactive drag handle visualization
struct TransformHandleView: View {
    
    // MARK: - Properties
    
    let handle: TransformHandleData
    let isActive: Bool
    
    @State private var isHovered: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Outer glow (when active)
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                handle.color.opacity(0.5),
                                handle.color.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: handle.size * 0.3,
                            endRadius: handle.size * 1.2
                        )
                    )
                    .frame(width: handle.size * 2.4, height: handle.size * 2.4)
                    .animation(.easeInOut(duration: 0.3), value: isActive)
            }
            
            // Main handle circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            handle.color.opacity(isHovered || isActive ? 1.0 : 0.8),
                            handle.color.opacity(isHovered || isActive ? 0.8 : 0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: handle.size, height: handle.size)
            
            // Border
            Circle()
                .strokeBorder(
                    Color.white.opacity(isHovered || isActive ? 1.0 : 0.8),
                    lineWidth: isActive ? 3 : 2
                )
                .frame(width: handle.size, height: handle.size)
            
            // Icon
            Image(systemName: handle.icon)
                .font(.system(
                    size: handle.size * 0.4,
                    weight: .bold
                ))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
        }
        .position(handle.position)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .shadow(
            color: handle.color.opacity(isActive ? 0.6 : 0.3),
            radius: isActive ? 8 : 4,
            x: 0,
            y: 2
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help(handleDescription)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
    }
    
    // MARK: - Description
    
    private var handleDescription: String {
        switch handle.type {
        case .center:
            return "Drag to move smile design"
        case .corner:
            return "Drag to scale uniformly"
        case .rotation:
            return "Drag to rotate"
        case .edge(let side):
            switch side {
            case .left, .right:
                return "Drag to adjust width"
            case .top, .bottom:
                return "Drag to adjust height"
            }
        }
    }
}

// MARK: - Animated Handle View

/// Enhanced handle with pulsing animation
struct AnimatedTransformHandleView: View {
    
    let handle: TransformHandleData
    let isActive: Bool
    
    @State private var isHovered: Bool = false
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Pulsing ring (when not active)
            if !isActive {
                Circle()
                    .stroke(handle.color.opacity(0.3), lineWidth: 2)
                    .frame(width: handle.size * pulseScale, height: handle.size * pulseScale)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                        value: pulseScale
                    )
            }
            
            // Active glow
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                handle.color.opacity(0.6),
                                handle.color.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: handle.size * 1.5
                        )
                    )
                    .frame(width: handle.size * 3, height: handle.size * 3)
            }
            
            // Main handle with gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            handle.color.opacity(0.9),
                            handle.color.opacity(0.7)
                        ],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: handle.size * 0.5
                    )
                )
                .frame(width: handle.size, height: handle.size)
            
            // Glass effect border
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.8),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: handle.size, height: handle.size)
            
            // Icon with shadow
            Image(systemName: handle.icon)
                .font(.system(
                    size: handle.size * 0.35,
                    weight: .semibold
                ))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color.white.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
        }
        .position(handle.position)
        .scaleEffect(isHovered ? 1.15 : 1.0)
        .shadow(
            color: handle.color.opacity(isActive ? 0.7 : 0.4),
            radius: isActive ? 12 : 6,
            x: 0,
            y: 3
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .onAppear {
            pulseScale = 1.2
        }
        .help(handleDescription)
    }
    
    private var handleDescription: String {
        switch handle.type {
        case .center:
            return "Move (Click and drag)"
        case .corner:
            return "Scale (Click and drag)"
        case .rotation:
            return "Rotate (Click and drag)"
        case .edge(let side):
            return "Resize \(side.rawValue) (Click and drag)"
        }
    }
}

// MARK: - Handle Connection Lines

/// Draws connection lines between handles
struct HandleConnectionLines: View {
    
    let handles: [TransformHandleData]
    let lineColor: Color
    let lineWidth: CGFloat
    
    init(
        handles: [TransformHandleData],
        lineColor: Color = .white.opacity(0.3),
        lineWidth: CGFloat = 1.0
    ) {
        self.handles = handles
        self.lineColor = lineColor
        self.lineWidth = lineWidth
    }
    
    var body: some View {
        Canvas { context, size in
            // Find corner handles
            let corners = handles.filter { handle in
                if case .corner = handle.type {
                    return true
                }
                return false
            }
            
            guard corners.count == 4 else { return }
            
            // Sort corners by position (top-left, top-right, bottom-right, bottom-left)
            let sorted = corners.sorted { h1, h2 in
                if abs(h1.position.y - h2.position.y) < 10 {
                    return h1.position.x < h2.position.x
                } else {
                    return h1.position.y < h2.position.y
                }
            }
            
            // Draw rectangle connecting corners
            var path = Path()
            path.move(to: sorted[0].position)
            path.addLine(to: sorted[1].position)
            path.addLine(to: sorted[3].position)
            path.addLine(to: sorted[2].position)
            path.closeSubpath()
            
            context.stroke(
                path,
                with: .color(lineColor),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    dash: [5, 5]
                )
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TransformHandleView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            VStack(spacing: 60) {
                // Basic handle
                TransformHandleView(
                    handle: TransformHandleData(
                        type: .center,
                        position: CGPoint(x: 200, y: 100),
                        size: 40,
                        color: .blue,
                        icon: "arrow.up.and.down.and.arrow.left.and.right"
                    ),
                    isActive: false
                )
                
                // Active handle
                TransformHandleView(
                    handle: TransformHandleData(
                        type: .corner,
                        position: CGPoint(x: 200, y: 200),
                        size: 30,
                        color: .green,
                        icon: "arrow.up.left.and.arrow.down.right"
                    ),
                    isActive: true
                )
                
                // Animated handle
                AnimatedTransformHandleView(
                    handle: TransformHandleData(
                        type: .rotation,
                        position: CGPoint(x: 200, y: 300),
                        size: 35,
                        color: .yellow,
                        icon: "arrow.triangle.2.circlepath"
                    ),
                    isActive: false
                )
            }
        }
        .frame(width: 400, height: 500)
    }
}
#endif
