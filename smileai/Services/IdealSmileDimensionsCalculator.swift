//
//  IdealSmileDimensionsCalculator.swift
//  smileai
//
//  Calculates theoretical ideal smile dimensions based on facial proportions
//  Uses established dental and aesthetic proportion theories
//

import Foundation
import CoreGraphics

// MARK: - Data Models

struct IdealSmileDimensions {
    // Calculated ideals based on facial proportions
    var idealCanineToCanineWidth: CGFloat
    var idealCentralIncisorWidth: CGFloat
    var idealLateralIncisorWidth: CGFloat
    var idealCanineWidth: CGFloat
    var idealSmileWidth: CGFloat

    // Reference measurements used
    var interpupillaryDistance: CGFloat
    var bizygomaticWidth: CGFloat
    var facialWidth: CGFloat

    // Tooth proportions (Central:Lateral:Canine)
    var toothProportions: ToothProportions

    // Assessment scores
    var goldenProportionScore: Double // 0-100, how close to golden ratio
    var proportionQuality: ProportionQuality

    // Conversion factor (pixels to mm)
    var pixelsPerMM: CGFloat
}

struct ToothProportions {
    var centralToLateralRatio: CGFloat  // Ideal: 1.618 (Golden Ratio)
    var lateralToCanineRatio: CGFloat   // Ideal: 1.618 (Golden Ratio)
    var centralToCanineRatio: CGFloat   // Ideal: 2.618 (φ²)
}

enum ProportionQuality: String {
    case excellent = "Excellent"    // Within 2% of ideal
    case good = "Good"              // Within 5% of ideal
    case acceptable = "Acceptable"  // Within 10% of ideal
    case needsAdjustment = "Needs Adjustment"  // >10% deviation
}

// MARK: - Calculator

class IdealSmileDimensionsCalculator {

    // MARK: - Constants

    private static let goldenRatio: CGFloat = 1.618
    private static let averageIPDmm: CGFloat = 63.0 // Average interpupillary distance in mm
    private static let idealCentralWidth_mm: CGFloat = 8.5 // Average ideal central incisor width
    private static let idealLateralWidth_mm: CGFloat = 6.5 // Average ideal lateral incisor width
    private static let idealCanineWidth_mm: CGFloat = 7.5 // Average ideal canine width

    // MARK: - Main Calculation Method

    static func calculate(from landmarks: FacialLandmarks, imageSize: CGSize) -> IdealSmileDimensions? {
        // Require both pupils for calculations
        guard let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil else {
            return nil
        }

        // Calculate IPD in pixels
        let ipd = calculateIPD(leftPupil: leftPupil, rightPupil: rightPupil)

        // Calculate pixel-to-mm conversion factor using average IPD
        let pixelsPerMM = ipd / averageIPDmm

        // Calculate bizygomatic width (approximation based on IPD)
        let bizygomatic = calculateBizygomaticWidth(ipd: ipd)

        // Calculate facial width (from image bounds)
        let facialWidth = imageSize.width

        // Calculate ideal dimensions using established dental proportion theories

        // 1. Ideal Canine-to-Canine Width
        // Method: Golden Ratio of IPD (IPD × 0.618)
        let idealCanineToCanine = ipd * 0.618

        // 2. Ideal Central Incisor Width
        // Method: IPD / 16 (established dental proportion)
        let idealCentralWidth = ipd / 16.0

        // 3. Ideal Lateral Incisor Width
        // Method: Central width / Golden Ratio
        let idealLateralWidth = idealCentralWidth / goldenRatio

        // 4. Ideal Canine Width
        // Method: Lateral width / Golden Ratio
        let idealCanineWidth = idealLateralWidth / goldenRatio

        // 5. Ideal Smile Width
        // Method: 50% of bizygomatic width (should extend to molars)
        let idealSmileWidth = bizygomatic * 0.50

        // Calculate tooth proportions
        let proportions = ToothProportions(
            centralToLateralRatio: idealCentralWidth / idealLateralWidth,
            lateralToCanineRatio: idealLateralWidth / idealCanineWidth,
            centralToCanineRatio: idealCentralWidth / idealCanineWidth
        )

        // Calculate golden proportion score
        let goldenScore = calculateGoldenProportionScore(proportions: proportions)
        let quality = assessProportionQuality(score: goldenScore)

        return IdealSmileDimensions(
            idealCanineToCanineWidth: idealCanineToCanine,
            idealCentralIncisorWidth: idealCentralWidth,
            idealLateralIncisorWidth: idealLateralWidth,
            idealCanineWidth: idealCanineWidth,
            idealSmileWidth: idealSmileWidth,
            interpupillaryDistance: ipd,
            bizygomaticWidth: bizygomatic,
            facialWidth: facialWidth,
            toothProportions: proportions,
            goldenProportionScore: goldenScore,
            proportionQuality: quality,
            pixelsPerMM: pixelsPerMM
        )
    }

    // MARK: - Helper Methods

    /// Calculate interpupillary distance (IPD) in pixels
    private static func calculateIPD(leftPupil: CGPoint, rightPupil: CGPoint) -> CGFloat {
        let dx = rightPupil.x - leftPupil.x
        let dy = rightPupil.y - leftPupil.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Calculate bizygomatic width (approximation)
    /// Bizygomatic width ≈ IPD × 2.0 (average facial proportion)
    private static func calculateBizygomaticWidth(ipd: CGFloat) -> CGFloat {
        return ipd * 2.0
    }

    /// Apply golden ratio transformation
    private static func applyGoldenRatio(_ value: CGFloat, inverse: Bool = false) -> CGFloat {
        return inverse ? value / goldenRatio : value * goldenRatio
    }

    /// Calculate how close proportions are to golden ratio (0-100 score)
    private static func calculateGoldenProportionScore(proportions: ToothProportions) -> Double {
        // Calculate deviation from ideal golden ratio (1.618)
        let centralLateralDev = abs(proportions.centralToLateralRatio - goldenRatio) / goldenRatio
        let lateralCanineDev = abs(proportions.lateralToCanineRatio - goldenRatio) / goldenRatio

        // Average deviation
        let avgDeviation = (centralLateralDev + lateralCanineDev) / 2.0

        // Convert to score (0% deviation = 100 score, 10% deviation = 0 score)
        let score = max(0.0, 100.0 - (Double(avgDeviation) * 1000.0))
        return min(100.0, score)
    }

    /// Assess proportion quality based on score
    private static func assessProportionQuality(score: Double) -> ProportionQuality {
        if score >= 98.0 {
            return .excellent   // Within 2%
        } else if score >= 95.0 {
            return .good        // Within 5%
        } else if score >= 90.0 {
            return .acceptable  // Within 10%
        } else {
            return .needsAdjustment // >10% deviation
        }
    }

    // MARK: - Conversion Utilities

    /// Convert pixels to millimeters using IPD reference
    static func convertToMM(_ pixels: CGFloat, pixelsPerMM: CGFloat) -> CGFloat {
        return pixels / pixelsPerMM
    }

    /// Convert millimeters to pixels using IPD reference
    static func convertToPixels(_ mm: CGFloat, pixelsPerMM: CGFloat) -> CGFloat {
        return mm * pixelsPerMM
    }

    /// Format measurement for display
    static func formatMeasurement(_ pixels: CGFloat, pixelsPerMM: CGFloat, unit: MeasurementUnit = .millimeters) -> String {
        switch unit {
        case .millimeters:
            let mm = convertToMM(pixels, pixelsPerMM: pixelsPerMM)
            return String(format: "%.1f mm", mm)
        case .pixels:
            return String(format: "%.0f px", pixels)
        }
    }
}

enum MeasurementUnit {
    case millimeters
    case pixels
}

// MARK: - Comparison Utilities

extension IdealSmileDimensions {

    /// Compare actual measurement to ideal
    func compareToIdeal(actualPixels: CGFloat, idealPixels: CGFloat) -> ComparisonResult {
        let deviationPercent = abs(actualPixels - idealPixels) / idealPixels * 100.0

        let status: ComparisonStatus
        if deviationPercent <= 2.0 {
            status = .excellent
        } else if deviationPercent <= 5.0 {
            status = .good
        } else if deviationPercent <= 10.0 {
            status = .acceptable
        } else {
            status = .needsAdjustment
        }

        return ComparisonResult(
            actual: actualPixels,
            ideal: idealPixels,
            deviationPercent: deviationPercent,
            status: status
        )
    }
}

struct ComparisonResult {
    var actual: CGFloat
    var ideal: CGFloat
    var deviationPercent: CGFloat
    var status: ComparisonStatus
}

enum ComparisonStatus: String {
    case excellent = "Excellent"
    case good = "Good"
    case acceptable = "Acceptable"
    case needsAdjustment = "Needs Adjustment"

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .acceptable: return "yellow"
        case .needsAdjustment: return "orange"
        }
    }
}
