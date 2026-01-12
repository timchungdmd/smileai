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

    // NEW: Proportional guides
    @State private var enabledGuides: Set<GuideType> = [
        .facialMidline,
        .dentalMidline,
        .goldenProportion,
        .smileWidth
    ]
    @State private var showGuidesSettings = false
    
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
                        MagnificationGesture()
                            .onChanged { value in
                                if !isLocked {
                                    currentMagnification = max(1.0, value)
                                }
                            }
                    )
                    .onTapGesture { location in
                        if let callback = onTap {
                            callback(location)
                        } else if isPlacing, let type = activeType, !isLocked {
                            landmarks[type] = location
                        }
                    }
                
                // 2. Proportional Guides Layer
                if !enabledGuides.isEmpty {
                    ProportionalGuidesView(
                        landmarks: convertLandmarksToFacialLandmarks(),
                        imageSize: image.size,
                        enabledGuides: enabledGuides
                    )
                    .scaleEffect(currentMagnification)
                    .offset(position + dragOffset)
                }

                // 3. Landmark Overlay Layer
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

                // 4. Guide Settings Button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { showGuidesSettings.toggle() }) {
                            Image(systemName: "slider.horizontal.3")
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help("Proportional Guides Settings")
                        .padding()
                    }
                    Spacer()
                }
            }
            .clipped()
            .background(Color.black)
            .popover(isPresented: $showGuidesSettings) {
                GuideSettingsView(enabledGuides: $enabledGuides)
                    .frame(width: 400, height: 600)
            }
        }
    }

    // MARK: - Helper Methods

    /// Convert landmarks dictionary to FacialLandmarks struct
    private func convertLandmarksToFacialLandmarks() -> FacialLandmarks? {
        var facialLandmarks = FacialLandmarks()

        facialLandmarks.leftPupil = landmarks[.leftPupil]
        facialLandmarks.rightPupil = landmarks[.rightPupil]
        facialLandmarks.noseTip = landmarks[.subnasale]
        facialLandmarks.leftMouthCorner = landmarks[.leftCommissure]
        facialLandmarks.rightMouthCorner = landmarks[.rightCommissure]
        facialLandmarks.upperLipCenter = landmarks[.upperLipCenter]
        facialLandmarks.lowerLipCenter = landmarks[.lowerLipCenter]
        facialLandmarks.chin = landmarks[.menton]

        // Return nil if we don't have minimum required landmarks
        guard facialLandmarks.leftPupil != nil && facialLandmarks.rightPupil != nil else {
            return nil
        }

        return facialLandmarks
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
            // FIX: Use specific color
            .fill(type.color)
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
