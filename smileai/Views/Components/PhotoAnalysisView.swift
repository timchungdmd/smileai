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

    // Proportional guides (controlled by parent view)
    @Binding var enabledGuides: Set<GuideType>

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
                    .onTapGesture { tapLocation in
                        // Convert tap location from view space to image space
                        let imagePoint = convertToImageCoordinates(
                            tapLocation: tapLocation,
                            viewSize: geometry.size,
                            imageSize: image.size,
                            scale: currentMagnification,
                            offset: position + dragOffset
                        )

                        // Handle tap BEFORE gestures to ensure marker placement works
                        if let callback = onTap {
                            callback(imagePoint)
                        } else if isPlacing, let type = activeType, !isLocked {
                            landmarks[type] = imagePoint
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isLocked && !isPlacing {
                                    dragOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                if !isLocked && !isPlacing {
                                    position += value.translation
                                    dragOffset = .zero
                                }
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                if !isLocked && !isPlacing {
                                    currentMagnification = max(1.0, value)
                                }
                            }
                    )
                
                // 2. Proportional Guides Layer
                if !enabledGuides.isEmpty {
                    ProportionalGuidesView(
                        landmarks: convertLandmarksToFacialLandmarks(),
                        imageSize: image.size,
                        enabledGuides: enabledGuides
                    )
                    .scaleEffect(currentMagnification)
                    .offset(position + dragOffset)
                    .allowsHitTesting(false)  // Allow taps to pass through to image layer
                }

                // 3. Landmark Overlay Layer
                ForEach(landmarks.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { type in
                    if let imagePoint = landmarks[type] {
                        // Convert from image coordinates back to view coordinates for display
                        let viewPoint = convertToViewCoordinates(
                            imagePoint: imagePoint,
                            viewSize: geometry.size,
                            imageSize: image.size,
                            scale: currentMagnification,
                            offset: position + dragOffset
                        )

                        Circle()
                            .fill(type.color)
                            .frame(width: 12, height: 12)
                            .position(viewPoint)
                            .overlay(
                                Text(type.rawValue.prefix(2).uppercased())
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .position(CGPoint(x: viewPoint.x, y: viewPoint.y - 15))
                            )
                    }
                }
            }
            .clipped()
            .background(Color.black)
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

    /// Convert tap location from view coordinates to image coordinates
    private func convertToImageCoordinates(
        tapLocation: CGPoint,
        viewSize: CGSize,
        imageSize: CGSize,
        scale: CGFloat,
        offset: CGSize
    ) -> CGPoint {
        // Calculate aspect-fit frame for the image
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        var displayedImageSize: CGSize
        if imageAspect > viewAspect {
            // Image is wider - fit to width
            displayedImageSize = CGSize(
                width: viewSize.width,
                height: viewSize.width / imageAspect
            )
        } else {
            // Image is taller - fit to height
            displayedImageSize = CGSize(
                width: viewSize.height * imageAspect,
                height: viewSize.height
            )
        }

        // Calculate the image's position in the view (centered)
        let imageOrigin = CGPoint(
            x: (viewSize.width - displayedImageSize.width) / 2,
            y: (viewSize.height - displayedImageSize.height) / 2
        )

        // Account for scale and offset
        let scaledSize = CGSize(
            width: displayedImageSize.width * scale,
            height: displayedImageSize.height * scale
        )

        // SwiftUI's scaleEffect scales from center, which shifts the origin
        let scaleShift = CGSize(
            width: displayedImageSize.width * (1 - scale) / 2,
            height: displayedImageSize.height * (1 - scale) / 2
        )

        let scaledOrigin = CGPoint(
            x: imageOrigin.x + scaleShift.width + offset.width,
            y: imageOrigin.y + scaleShift.height + offset.height
        )

        // Convert tap to image-relative coordinates
        let relativeX = (tapLocation.x - scaledOrigin.x) / scaledSize.width
        let relativeY = (tapLocation.y - scaledOrigin.y) / scaledSize.height

        // Convert to actual image pixel coordinates
        let imageX = relativeX * imageSize.width
        let imageY = relativeY * imageSize.height

        return CGPoint(x: imageX, y: imageY)
    }

    /// Convert image coordinates back to view coordinates for display
    private func convertToViewCoordinates(
        imagePoint: CGPoint,
        viewSize: CGSize,
        imageSize: CGSize,
        scale: CGFloat,
        offset: CGSize
    ) -> CGPoint {
        // Calculate aspect-fit frame for the image
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        var displayedImageSize: CGSize
        if imageAspect > viewAspect {
            displayedImageSize = CGSize(
                width: viewSize.width,
                height: viewSize.width / imageAspect
            )
        } else {
            displayedImageSize = CGSize(
                width: viewSize.height * imageAspect,
                height: viewSize.height
            )
        }

        // Calculate the image's position in the view (centered)
        let imageOrigin = CGPoint(
            x: (viewSize.width - displayedImageSize.width) / 2,
            y: (viewSize.height - displayedImageSize.height) / 2
        )

        // Convert from image pixel coordinates to relative coordinates
        let relativeX = imagePoint.x / imageSize.width
        let relativeY = imagePoint.y / imageSize.height

        // Account for scale
        let scaledSize = CGSize(
            width: displayedImageSize.width * scale,
            height: displayedImageSize.height * scale
        )

        // SwiftUI's scaleEffect scales from center, which shifts the origin
        let scaleShift = CGSize(
            width: displayedImageSize.width * (1 - scale) / 2,
            height: displayedImageSize.height * (1 - scale) / 2
        )

        // Convert to view coordinates
        let viewX = imageOrigin.x + scaleShift.width + (relativeX * scaledSize.width) + offset.width
        let viewY = imageOrigin.y + scaleShift.height + (relativeY * scaledSize.height) + offset.height

        return CGPoint(x: viewX, y: viewY)
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
