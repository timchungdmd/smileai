//
//  ProportionalGuidesView.swift
//  smileai
//
//  Advanced proportional guides and help lines for smile design
//  Competing with exocad's facial analysis guides
//

import SwiftUI
import AppKit

/// Advanced proportional guides overlay for smile design
struct ProportionalGuidesView: View {

    var landmarks: FacialLandmarks?
    var imageSize: CGSize
    var enabledGuides: Set<GuideType>

    var body: some View {
        Canvas { context, size in
            guard let landmarks = landmarks else { return }

            // Scale factor for coordinate conversion
            let scaleX = size.width / imageSize.width
            let scaleY = size.height / imageSize.height

            let scale = { (point: CGPoint) -> CGPoint in
                return CGPoint(x: point.x * scaleX, y: point.y * scaleY)
            }

            // Draw each enabled guide
            for guideType in enabledGuides {
                drawGuide(type: guideType, context: context, landmarks: landmarks, scale: scale)
            }
        }
    }

    private func drawGuide(
        type: GuideType,
        context: GraphicsContext,
        landmarks: FacialLandmarks,
        scale: (CGPoint) -> CGPoint
    ) {
        switch type {
        case .facialMidline:
            drawFacialMidline(context: context, landmarks: landmarks, scale: scale)
        case .dentalMidline:
            drawDentalMidline(context: context, landmarks: landmarks, scale: scale)
        case .goldenProportion:
            drawGoldenProportion(context: context, landmarks: landmarks, scale: scale)
        case .horizontalReference:
            drawHorizontalReference(context: context, landmarks: landmarks, scale: scale)
        case .verticalThirds:
            drawVerticalThirds(context: context, landmarks: landmarks, scale: scale)
        case .smileWidth:
            drawSmileWidth(context: context, landmarks: landmarks, scale: scale)
        case .lipLine:
            drawLipLine(context: context, landmarks: landmarks, scale: scale)
        case .interpupillaryLine:
            drawInterpupillaryLine(context: context, landmarks: landmarks, scale: scale)
        case .canineGuideline:
            drawCanineGuideline(context: context, landmarks: landmarks, scale: scale)
        case .bizygomatic:
            drawBizygomatic(context: context, landmarks: landmarks, scale: scale)
        }
    }

    // MARK: - Guide Drawing Methods

    private func drawFacialMidline(
        context: GraphicsContext,
        landmarks: FacialLandmarks,
        scale: (CGPoint) -> CGPoint
    ) {
        guard let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil else { return }

        let midX = (leftPupil.x + rightPupil.x) / 2
        let topPoint = scale(CGPoint(x: midX, y: 0))
        let bottomPoint = scale(CGPoint(x: midX, y: imageSize.height))

        var path = Path()
        path.move(to: topPoint)
        path.addLine(to: bottomPoint)

        context.stroke(
            path,
            with: .color(.cyan),
            style: StrokeStyle(lineWidth: 2, dash: [10, 5])
        )

        // Add label
        drawLabel(
            context: context,
            text: "Facial Midline",
            at: CGPoint(x: topPoint.x + 10, y: topPoint.y + 20),
            color: .cyan
        )
    }

    private func drawDentalMidline(
        context: GraphicsContext,
        landmarks: FacialLandmarks,
        scale: (CGPoint) -> CGPoint
    ) {
        guard let leftMouth = landmarks.leftMouthCorner,
              let rightMouth = landmarks.rightMouthCorner else { return }

        let midX = (leftMouth.x + rightMouth.x) / 2
        let topY = min(leftMouth.y, rightMouth.y) - 50
        let bottomY = max(leftMouth.y, rightMouth.y) + 50

        let topPoint = scale(CGPoint(x: midX, y: topY))
        let bottomPoint = scale(CGPoint(x: midX, y: bottomY))

        var path = Path()
        path.move(to: topPoint)
        path.addLine(to: bottomPoint)

        context.stroke(
            path,
            with: .color(.yellow),
            style: StrokeStyle(lineWidth: 2, dash: [5, 3])
        )

        drawLabel(
            context: context,
            text: "Dental Midline",
            at: CGPoint(x: topPoint.x + 10, y: topPoint.y + 40),
            color: .yellow
        )
    }

    private func drawGoldenProportion(
        context: GraphicsContext,
        landmarks: FacialLandmarks,
        scale: (CGPoint) -> CGPoint
    ) {
        guard let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil,
              let leftMouth = landmarks.leftMouthCorner,
              let rightMouth = landmarks.rightMouthCorner else { return }

        let ipd = hypot(rightPupil.x - leftPupil.x, rightPupil.y - leftPupil.y)
        let goldenRatio: CGFloat = 1.618
        let idealSmileWidth = ipd * goldenRatio

        let mouthMidX = (leftMouth.x + rightMouth.x) / 2
        let mouthMidY = (leftMouth.y + rightMouth.y) / 2

        let idealLeft = CGPoint(x: mouthMidX - idealSmileWidth / 2, y: mouthMidY)
        let idealRight = CGPoint(x: mouthMidX + idealSmileWidth / 2, y: mouthMidY)

        let scaledLeft = scale(idealLeft)
        let scaledRight = scale(idealRight)

        // Draw ideal smile width
        var path = Path()
        path.move(to: scaledLeft)
        path.addLine(to: scaledRight)

        context.stroke(
            path,
            with: .color(.orange),
            style: StrokeStyle(lineWidth: 3, dash: [15, 8])
        )

        // Draw markers
        drawCircle(context: context, at: scaledLeft, radius: 6, color: .orange)
        drawCircle(context: context, at: scaledRight, radius: 6, color: .orange)

        drawLabel(
            context: context,
            text: "Golden Proportion (1:1.618)",
            at: CGPoint(x: scaledLeft.x, y: scaledLeft.y - 20),
            color: .orange
        )
    }

    private func drawHorizontalReference(
        context: GraphicsContext,
        landmarks: FacialLandmarks,
        scale: (CGPoint) -> CGPoint
    ) {
        guard let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil else { return }

        let scaledLeft = scale(leftPupil)
        let scaledRight = scale(rightPupil)

        // Extend line across entire width
        var path = Path()
        path.move(to: CGPoint(x: 0, y: scaledLeft.y))
        path.addLine(to: CGPoint(x: imageSize.width, y: scaledRight.y))

        context.stroke(
            path,
            with: .color(.blue.opacity(0.6)),
            style: StrokeStyle(lineWidth: 1, dash: [8, 4])
        )

        drawLabel(
            context: context,
            text: "Horizontal Reference",
            at: CGPoint(x: 10, y: scaledLeft.y - 20),
            color: .blue
        )
    }

    private func drawVerticalThirds(
        context: GraphicsContext,
        landmarks: FacialLandmarks,
        scale: (CGPoint) -> CGPoint
    ) {
        let height = imageSize.height
        let third = height / 3

        for i in 1...2 {
            let y = CGFloat(i) * third
            let scaledY = y * (context.environment.displayScale)

            var path = Path()
            path.move(to: CGPoint(x: 0, y: scaledY))
            path.addLine(to: CGPoint(x: imageSize.width, y: scaledY))

            context.stroke(
                path,
                with: .color(.green.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [6, 3])
            )
        }

        drawLabel(
            context: context,
            text: "Facial Thirds",
            at: CGPoint(x: 10, y: 10),
            color: .green
        )
    }

    private func drawSmileWidth(
        context: GraphicsContext,
        landmarks: FacialLandmarks,
        scale: (CGPoint) -> CGPoint
    ) {
        guard let leftMouth = landmarks.leftMouthCorner,
              let rightMouth = landmarks.rightMouthCorner else { return }

        let scaledLeft = scale(leftMouth)
        let scaledRight = scale(rightMouth)

        var path = Path()
        path.move(to: scaledLeft)
        path.addLine(to: scaledRight)

        context.stroke(
            path,
            with: .color(.red),
            style: StrokeStyle(lineWidth: 3)
        )

        // Draw end markers
        drawCircle(context: context, at: scaledLeft, radius: 5, color: .red)
        drawCircle(context: context, at: scaledRight, radius: 5, color: .red)

        // Calculate and display width
        let width = hypot(rightMouth.x - leftMouth.x, rightMouth.y - leftMouth.y)
        let midPoint = CGPoint(
            x: (scaledLeft.x + scaledRight.x) / 2,
            y: (scaledLeft.y + scaledRight.y) / 2 + 30
        )

        drawLabel(
            context: context,
            text: String(format: "Smile Width: %.1fpx", width),
            at: midPoint,
            color: .red
        )
    }

    private func drawLipLine(
        context: GraphicsContext,
        landmarks: FacialLandmarks,
        scale: (CGPoint) -> CGPoint
    ) {
        guard let upperLip = landmarks.upperLipCenter,
              let leftMouth = landmarks.leftMouthCorner,
              let rightMouth = landmarks.rightMouthCorner else { return }

        let scaledUpper = scale(upperLip)
        let scaledLeft = scale(leftMouth)
        let scaledRight = scale(rightMouth)

        // Draw smooth curve through points
        var path = Path()
        path.move(to: scaledLeft)
        path.addQuadCurve(to: scaledRight, control: scaledUpper)

        context.stroke(
            path,
            with: .color(.pink),
            style: StrokeStyle(lineWidth: 2)
        )

        drawLabel(
            context: context,
            text: "Upper Lip Line",
            at: CGPoint(x: scaledUpper.x + 15, y: scaledUpper.y),
            color: .pink
        )
    }

    private func drawInterpupillaryLine(
        context: GraphicsContext,
        landmarks: FacialLandmarks,
        scale: (CGPoint) -> CGPoint
    ) {
        guard let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil else { return }

        let scaledLeft = scale(leftPupil)
        let scaledRight = scale(rightPupil)

        var path = Path()
        path.move(to: scaledLeft)
        path.addLine(to: scaledRight)

        context.stroke(
            path,
            with: .color(.purple),
            style: StrokeStyle(lineWidth: 2)
        )

        // Draw pupil markers
        drawCircle(context: context, at: scaledLeft, radius: 8, color: .purple)
        drawCircle(context: context, at: scaledRight, radius: 8, color: .purple)

        // Calculate IPD
        let ipd = hypot(rightPupil.x - leftPupil.x, rightPupil.y - leftPupil.y)
        let midPoint = CGPoint(
            x: (scaledLeft.x + scaledRight.x) / 2,
            y: scaledLeft.y - 25
        )

        drawLabel(
            context: context,
            text: String(format: "IPD: %.1fpx", ipd),
            at: midPoint,
            color: .purple
        )
    }

    private func drawCanineGuideline(
        context: GraphicsContext,
        landmarks: FacialLandmarks,
        scale: (CGPoint) -> CGPoint
    ) {
        guard let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil,
              let leftMouth = landmarks.leftMouthCorner,
              let rightMouth = landmarks.rightMouthCorner else { return }

        // Canines typically align below inner canthus/pupil
        let leftCanineX = leftPupil.x
        let rightCanineX = rightPupil.x
        let mouthY = (leftMouth.y + rightMouth.y) / 2

        let leftTop = scale(CGPoint(x: leftCanineX, y: leftPupil.y))
        let leftBottom = scale(CGPoint(x: leftCanineX, y: mouthY + 30))
        let rightTop = scale(CGPoint(x: rightCanineX, y: rightPupil.y))
        let rightBottom = scale(CGPoint(x: rightCanineX, y: mouthY + 30))

        var path = Path()
        path.move(to: leftTop)
        path.addLine(to: leftBottom)
        path.move(to: rightTop)
        path.addLine(to: rightBottom)

        context.stroke(
            path,
            with: .color(.teal),
            style: StrokeStyle(lineWidth: 2, dash: [8, 4])
        )

        drawLabel(
            context: context,
            text: "Canine Guide",
            at: CGPoint(x: leftBottom.x + 10, y: leftBottom.y),
            color: .teal
        )
    }

    private func drawBizygomatic(
        context: GraphicsContext,
        landmarks: FacialLandmarks,
        scale: (CGPoint) -> CGPoint
    ) {
        // Approximate zygomatic points based on pupil distance
        guard let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil else { return }

        let ipd = hypot(rightPupil.x - leftPupil.x, rightPupil.y - leftPupil.y)
        let zygomaticWidth = ipd * 2.2 // Typical ratio

        let midX = (leftPupil.x + rightPupil.x) / 2
        let midY = (leftPupil.y + rightPupil.y) / 2

        let leftZygoma = CGPoint(x: midX - zygomaticWidth / 2, y: midY)
        let rightZygoma = CGPoint(x: midX + zygomaticWidth / 2, y: midY)

        let scaledLeft = scale(leftZygoma)
        let scaledRight = scale(rightZygoma)

        var path = Path()
        path.move(to: scaledLeft)
        path.addLine(to: scaledRight)

        context.stroke(
            path,
            with: .color(.brown.opacity(0.7)),
            style: StrokeStyle(lineWidth: 2, dash: [12, 6])
        )

        drawCircle(context: context, at: scaledLeft, radius: 6, color: .brown)
        drawCircle(context: context, at: scaledRight, radius: 6, color: .brown)

        drawLabel(
            context: context,
            text: "Bizygomatic Width",
            at: CGPoint(x: scaledLeft.x, y: scaledLeft.y + 20),
            color: .brown
        )
    }

    // MARK: - Helper Methods

    private func drawCircle(context: GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color) {
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        let circle = Circle().path(in: rect)
        context.stroke(circle, with: .color(color), lineWidth: 2)
    }

    private func drawLabel(context: GraphicsContext, text: String, at point: CGPoint, color: Color) {
        context.draw(
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color),
            at: point
        )
    }
}

// MARK: - Guide Types

enum GuideType: String, CaseIterable, Identifiable {
    case facialMidline = "Facial Midline"
    case dentalMidline = "Dental Midline"
    case goldenProportion = "Golden Proportion"
    case horizontalReference = "Horizontal Reference"
    case verticalThirds = "Facial Thirds"
    case smileWidth = "Smile Width"
    case lipLine = "Lip Line"
    case interpupillaryLine = "Interpupillary Line"
    case canineGuideline = "Canine Guidelines"
    case bizygomatic = "Bizygomatic Width"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .facialMidline:
            return "Shows the vertical center line of the face"
        case .dentalMidline:
            return "Shows the dental midline between central incisors"
        case .goldenProportion:
            return "Golden ratio (1:1.618) for ideal smile width"
        case .horizontalReference:
            return "Horizontal reference line through pupils"
        case .verticalThirds:
            return "Divides face into upper, middle, and lower thirds"
        case .smileWidth:
            return "Measures actual smile width"
        case .lipLine:
            return "Upper lip curve and smile line"
        case .interpupillaryLine:
            return "Distance between pupils (IPD)"
        case .canineGuideline:
            return "Vertical guidelines for canine positioning"
        case .bizygomatic:
            return "Facial width at widest point"
        }
    }

    var icon: String {
        switch self {
        case .facialMidline: return "line.vertical"
        case .dentalMidline: return "line.vertical.dotted"
        case .goldenProportion: return "rectangle.ratio.3.to.4"
        case .horizontalReference: return "line.horizontal"
        case .verticalThirds: return "rectangle.split.3x1"
        case .smileWidth: return "arrow.left.and.right"
        case .lipLine: return "mouth"
        case .interpupillaryLine: return "eye.circle"
        case .canineGuideline: return "arrow.up.and.down"
        case .bizygomatic: return "arrow.left.and.right.square"
        }
    }
}

// MARK: - Guide Settings View

struct GuideSettingsView: View {
    @Binding var enabledGuides: Set<GuideType>

    var body: some View {
        Form {
            Section("Proportional Guides") {
                ForEach(GuideType.allCases) { guideType in
                    Toggle(isOn: Binding(
                        get: { enabledGuides.contains(guideType) },
                        set: { isEnabled in
                            if isEnabled {
                                enabledGuides.insert(guideType)
                            } else {
                                enabledGuides.remove(guideType)
                            }
                        }
                    )) {
                        HStack {
                            Image(systemName: guideType.icon)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(guideType.rawValue)
                                    .font(.headline)
                                Text(guideType.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Enable All") {
                    enabledGuides = Set(GuideType.allCases)
                }

                Button("Disable All") {
                    enabledGuides.removeAll()
                }

                Button("Reset to Default") {
                    enabledGuides = [
                        .facialMidline,
                        .dentalMidline,
                        .goldenProportion,
                        .smileWidth
                    ]
                }
            }
        }
        .formStyle(.grouped)
    }
}
