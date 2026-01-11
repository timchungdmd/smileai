import SwiftUI

// MARK: - Photo Analysis View
struct PhotoAnalysisView: View {
    
    // MARK: - Properties
    let image: NSImage
    @Binding var landmarks: [LandmarkType: CGPoint]
    var isPlacing: Bool
    var isLocked: Bool
    var activeType: LandmarkType?
    
    // NEW: Optional tap handler for alignment
    var onTap: ((CGPoint) -> Void)? = nil
    
    @State private var dragOffset: CGSize = .zero
    @State private var currentMagnification: CGFloat = 1.0
    @State private var position: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Image Layer
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(currentMagnification)
                    .offset(position + dragOffset)
                    .gesture(
                        // Pan Gesture
                        DragGesture()
                            .onChanged { value in
                                if !isLocked {
                                    dragOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                if !isLocked {
                                    position += value.translation
                                    dragOffset = .zero
                                }
                            }
                    )
                    .gesture(
                        // Zoom Gesture (Magnification)
                        MagnificationGesture()
                            .onChanged { value in
                                if !isLocked {
                                    currentMagnification = max(1.0, value)
                                }
                            }
                    )
                    // FIX: Add Tap Gesture to detect clicks on image
                    .onTapGesture { location in
                        // Convert location if necessary based on zoom/pan
                        // For simplicity in this view, we pass the raw location relative to the view
                        // Ideally, we inverse transform to get image coordinates.
                        // Here we assume the parent handles coordinate mapping or use normalized coords.
                        
                        if let callback = onTap {
                            callback(location)
                        } else if isPlacing, let type = activeType, !isLocked {
                            // Default landmark placement behavior if no custom tap handler
                            landmarks[type] = location
                        }
                    }
                
                // 2. Landmark Overlay Layer
                ForEach(landmarks.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { type in
                    if let point = landmarks[type] {
                        LandmarkPointView(
                            type: type,
                            point: point,
                            zoom: currentMagnification,
                            offset: position
                        )
                    }
                }
            }
            .clipped()
            .background(Color.black)
        }
    }
}

// MARK: - Helper View
struct LandmarkPointView: View {
    let type: LandmarkType
    let point: CGPoint
    let zoom: CGFloat
    let offset: CGSize
    
    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 10, height: 10)
            .position(
                x: point.x * zoom + offset.width,
                y: point.y * zoom + offset.height
            )
            .overlay(
                Text(type.rawValue.prefix(2).uppercased())
                    .font(.caption2)
                    .foregroundColor(.white)
                    .position(
                        x: point.x * zoom + offset.width,
                        y: point.y * zoom + offset.height - 15
                    )
            )
    }
}

// Extension to allow + operator on CGSize
extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        return CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
    static func += (lhs: inout CGSize, rhs: CGSize) {
        lhs = lhs + rhs
    }
}
