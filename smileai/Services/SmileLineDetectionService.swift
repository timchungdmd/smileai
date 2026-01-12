//
//  SmileLineDetectionService.swift
//  smileai
//
//  AI-powered automatic smile line detection
//  Competing with exocad Smile Creator's AI features
//

import Foundation
import Vision
import AppKit
import CoreImage

/// Automatic smile line detection using AI and computer vision
class SmileLineDetectionService {

    // MARK: - Smile Line Detection

    /// Automatically detect smile line from facial landmarks
    static func detectSmileLine(from landmarks: FacialLandmarks, imageSize: CGSize) -> SmileLine? {
        guard let leftCorner = landmarks.leftMouthCorner,
              let rightCorner = landmarks.rightMouthCorner,
              let upperLip = landmarks.upperLipCenter else {
            return nil
        }

        // Calculate smile line curve from detected landmarks
        let controlPoints = generateSmileLineCurve(
            leftCorner: leftCorner,
            rightCorner: rightCorner,
            upperLip: upperLip,
            landmarks: landmarks,
            imageSize: imageSize
        )

        let smileType = classifySmileType(controlPoints: controlPoints)

        return SmileLine(
            controlPoints: controlPoints,
            type: smileType,
            confidence: calculateConfidence(landmarks: landmarks)
        )
    }

    /// Generate smooth smile line curve using cubic spline interpolation
    private static func generateSmileLineCurve(
        leftCorner: CGPoint,
        rightCorner: CGPoint,
        upperLip: CGPoint,
        landmarks: FacialLandmarks,
        imageSize: CGSize
    ) -> [CGPoint] {
        var points: [CGPoint] = []

        // Start from left corner
        points.append(leftCorner)

        // Calculate intermediate points for a natural smile curve
        let segments = 20 // Number of points along the curve
        let width = rightCorner.x - leftCorner.x

        // Determine curve characteristics
        let lipHeight = upperLip.y
        let curvature = calculateSmileCurvature(landmarks: landmarks)

        for i in 1..<segments {
            let t = CGFloat(i) / CGFloat(segments)
            let x = leftCorner.x + width * t

            // Cubic bezier curve for natural smile line
            let y = cubicSmileCurve(
                t: t,
                leftY: leftCorner.y,
                rightY: rightCorner.y,
                peakY: lipHeight,
                curvature: curvature
            )

            points.append(CGPoint(x: x, y: y))
        }

        // End at right corner
        points.append(rightCorner)

        return points
    }

    /// Calculate cubic curve for smile line
    private static func cubicSmileCurve(
        t: CGFloat,
        leftY: CGFloat,
        rightY: CGFloat,
        peakY: CGFloat,
        curvature: CGFloat
    ) -> CGFloat {
        // Use cubic Hermite spline for smooth curve
        let h00 = 2 * pow(t, 3) - 3 * pow(t, 2) + 1
        let h10 = pow(t, 3) - 2 * pow(t, 2) + t
        let h01 = -2 * pow(t, 3) + 3 * pow(t, 2)
        let h11 = pow(t, 3) - pow(t, 2)

        let midY = (leftY + rightY) / 2
        let peakOffset = peakY - midY

        // Apply curvature adjustment
        let curvedPeak = peakY + (curvature * peakOffset)

        return h00 * leftY + h10 * (curvedPeak - leftY) + h01 * rightY + h11 * (rightY - curvedPeak)
    }

    /// Calculate smile curvature from facial proportions
    private static func calculateSmileCurvature(landmarks: FacialLandmarks) -> CGFloat {
        guard let leftCorner = landmarks.leftMouthCorner,
              let rightCorner = landmarks.rightMouthCorner,
              let upperLip = landmarks.upperLipCenter,
              let lowerLip = landmarks.lowerLipCenter else {
            return 0.0
        }

        // Calculate smile width vs height ratio
        let smileWidth = hypot(rightCorner.x - leftCorner.x, rightCorner.y - leftCorner.y)
        let smileHeight = hypot(upperLip.x - lowerLip.x, upperLip.y - lowerLip.y)

        // Normalized curvature (0 = flat, 1 = highly curved)
        let curvature = min(max((smileHeight / smileWidth) * 2.0, 0.0), 1.0)

        return curvature
    }

    /// Classify smile type based on curve characteristics
    private static func classifySmileType(controlPoints: [CGPoint]) -> SmileType {
        guard controlPoints.count >= 3 else { return .straight }

        let leftCorner = controlPoints.first!
        let rightCorner = controlPoints.last!
        let midPoint = controlPoints[controlPoints.count / 2]

        let cornerMidY = (leftCorner.y + rightCorner.y) / 2
        let deviation = midPoint.y - cornerMidY

        // Classify based on vertical deviation
        if abs(deviation) < 5 {
            return .straight
        } else if deviation > 15 {
            return .upturned
        } else if deviation > 5 {
            return .natural
        } else if deviation < -15 {
            return .downturned
        } else {
            return .parallelToLip
        }
    }

    /// Calculate confidence score for detection
    private static func calculateConfidence(landmarks: FacialLandmarks) -> Double {
        var confidence: Double = 0.0
        var landmarkCount = 0

        // Check critical landmarks
        if landmarks.leftPupil != nil { confidence += 0.15; landmarkCount += 1 }
        if landmarks.rightPupil != nil { confidence += 0.15; landmarkCount += 1 }
        if landmarks.leftMouthCorner != nil { confidence += 0.25; landmarkCount += 1 }
        if landmarks.rightMouthCorner != nil { confidence += 0.25; landmarkCount += 1 }
        if landmarks.upperLipCenter != nil { confidence += 0.1; landmarkCount += 1 }
        if landmarks.lowerLipCenter != nil { confidence += 0.1; landmarkCount += 1 }

        return min(confidence, 1.0)
    }

    // MARK: - Tooth Position Prediction

    /// Predict incisal edge positions from smile line
    static func predictToothPositions(from smileLine: SmileLine, landmarks: FacialLandmarks) -> [ToothPosition] {
        var positions: [ToothPosition] = []

        guard let leftCorner = landmarks.leftMouthCorner,
              let rightCorner = landmarks.rightMouthCorner else {
            return positions
        }

        let smileWidth = rightCorner.x - leftCorner.x

        // Central incisors (6 anterior teeth visible in smile)
        let teethCount = 6
        let segmentWidth = smileWidth / CGFloat(teethCount + 1)

        for i in 0..<teethCount {
            let t = CGFloat(i + 1) / CGFloat(teethCount + 1)
            let x = leftCorner.x + smileWidth * t

            // Find corresponding Y on smile line
            let index = Int(t * CGFloat(smileLine.controlPoints.count - 1))
            let y = smileLine.controlPoints[index].y

            let position = ToothPosition(
                number: i + 1,
                center: CGPoint(x: x, y: y),
                width: segmentWidth * 0.8, // 80% of segment for natural spacing
                toothType: classifyToothType(index: i)
            )

            positions.append(position)
        }

        return positions
    }

    private static func classifyToothType(index: Int) -> PredictedToothType {
        switch index {
        case 0, 5: return .canine
        case 1, 4: return .lateralIncisor
        case 2, 3: return .centralIncisor
        default: return .centralIncisor
        }
    }

    // MARK: - Facial Proportion Analysis

    /// Calculate facial proportions for smile design
    static func analyzeFacialProportions(landmarks: FacialLandmarks) -> FacialProportions? {
        guard let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil,
              let leftMouth = landmarks.leftMouthCorner,
              let rightMouth = landmarks.rightMouthCorner else {
            return nil
        }

        // Inter-pupillary distance (IPD)
        let ipd = hypot(rightPupil.x - leftPupil.x, rightPupil.y - leftPupil.y)

        // Smile width
        let smileWidth = hypot(rightMouth.x - leftMouth.x, rightMouth.y - leftMouth.y)

        // Ideal smile width is typically 1.618 (golden ratio) times IPD
        let idealSmileWidth = ipd * 1.618
        let smileWidthRatio = smileWidth / idealSmileWidth

        // Facial midline
        let facialMidlineX = (leftPupil.x + rightPupil.x) / 2
        let dentalMidlineX = (leftMouth.x + rightMouth.x) / 2
        let midlineDeviation = abs(dentalMidlineX - facialMidlineX)

        // Vertical face proportions
        let pupilToMouth = abs((leftPupil.y + rightPupil.y) / 2 - (leftMouth.y + rightMouth.y) / 2)

        return FacialProportions(
            ipd: ipd,
            smileWidth: smileWidth,
            idealSmileWidth: idealSmileWidth,
            smileWidthRatio: smileWidthRatio,
            midlineDeviation: midlineDeviation,
            pupilToMouthDistance: pupilToMouth
        )
    }

    // MARK: - Advanced Analysis

    /// Detect smile asymmetry
    static func detectSmileAsymmetry(landmarks: FacialLandmarks) -> SmileAsymmetry? {
        guard let leftCorner = landmarks.leftMouthCorner,
              let rightCorner = landmarks.rightMouthCorner,
              let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil else {
            return nil
        }

        // Calculate vertical asymmetry
        let pupilMidlineY = (leftPupil.y + rightPupil.y) / 2
        let leftDeviation = abs(leftCorner.y - pupilMidlineY)
        let rightDeviation = abs(rightCorner.y - pupilMidlineY)
        let verticalAsymmetry = abs(leftDeviation - rightDeviation)

        // Calculate horizontal asymmetry
        let facialMidlineX = (leftPupil.x + rightPupil.x) / 2
        let leftDistance = abs(leftCorner.x - facialMidlineX)
        let rightDistance = abs(rightCorner.x - facialMidlineX)
        let horizontalAsymmetry = abs(leftDistance - rightDistance)

        return SmileAsymmetry(
            verticalAsymmetry: verticalAsymmetry,
            horizontalAsymmetry: horizontalAsymmetry,
            severity: classifyAsymmetrySeverity(vertical: verticalAsymmetry, horizontal: horizontalAsymmetry)
        )
    }

    private static func classifyAsymmetrySeverity(vertical: CGFloat, horizontal: CGFloat) -> AsymmetrySeverity {
        let totalAsymmetry = sqrt(vertical * vertical + horizontal * horizontal)

        if totalAsymmetry < 5 {
            return .minimal
        } else if totalAsymmetry < 15 {
            return .mild
        } else if totalAsymmetry < 30 {
            return .moderate
        } else {
            return .severe
        }
    }
}

// MARK: - Supporting Types

struct SmileLine {
    var controlPoints: [CGPoint]
    var type: SmileType
    var confidence: Double
}

enum SmileType: String, CaseIterable {
    case natural = "Natural"
    case parallelToLip = "Parallel to Lip"
    case upturned = "Upturned"
    case straight = "Straight"
    case downturned = "Downturned"
    case custom = "Custom"
}

struct ToothPosition {
    var number: Int
    var center: CGPoint
    var width: CGFloat
    var toothType: PredictedToothType
}

enum PredictedToothType: String {
    case centralIncisor = "Central Incisor"
    case lateralIncisor = "Lateral Incisor"
    case canine = "Canine"
    case premolar = "Premolar"
    case molar = "Molar"
}

struct FacialProportions {
    var ipd: CGFloat
    var smileWidth: CGFloat
    var idealSmileWidth: CGFloat
    var smileWidthRatio: CGFloat
    var midlineDeviation: CGFloat
    var pupilToMouthDistance: CGFloat

    var isIdeal: Bool {
        // Check if proportions are within ideal range
        return smileWidthRatio > 0.9 && smileWidthRatio < 1.1 && midlineDeviation < 2.0
    }
}

struct SmileAsymmetry {
    var verticalAsymmetry: CGFloat
    var horizontalAsymmetry: CGFloat
    var severity: AsymmetrySeverity
}

enum AsymmetrySeverity: String {
    case minimal = "Minimal"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
}
