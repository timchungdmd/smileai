//
//  EnhancedToothLibrary.swift
//  smileai
//
//  Enhanced tooth library with extensive preset designs
//  Competing with exocad's extensive tooth library
//

import Foundation
import SceneKit

/// Enhanced tooth library with clinical-grade presets
class EnhancedToothLibrary {

    // MARK: - Tooth Morphology Presets

    static let morphologyPresets: [ToothMorphologyPreset] = [
        // Natural Presets
        ToothMorphologyPreset(
            name: "Natural Ovoid",
            category: .natural,
            description: "Soft, rounded contours with gentle transitions",
            parameters: ToothParameters(
                width: 8.5, height: 11.0, thickness: 7.5,
                convexity: 0.6, incisalCurvature: 0.4,
                cervicalBulge: 0.5, angulation: 2.0,
                labialInclination: 5.0, mesialDistalAngle: 3.0,
                incisorTip: 0.3, mammelonDepth: 0.2
            ),
            ageGroup: .adult,
            gender: .neutral
        ),

        ToothMorphologyPreset(
            name: "Natural Square",
            category: .natural,
            description: "Balanced proportions with straight mesial and distal walls",
            parameters: ToothParameters(
                width: 9.0, height: 11.0, thickness: 7.5,
                convexity: 0.4, incisalCurvature: 0.2,
                cervicalBulge: 0.5, angulation: 1.0,
                labialInclination: 6.0, mesialDistalAngle: 1.0,
                incisorTip: 0.2, mammelonDepth: 0.15
            ),
            ageGroup: .adult,
            gender: .neutral
        ),

        ToothMorphologyPreset(
            name: "Natural Triangular",
            category: .natural,
            description: "Tapered incisal edge with wider cervical base",
            parameters: ToothParameters(
                width: 7.5, height: 11.5, thickness: 7.0,
                convexity: 0.7, incisalCurvature: 0.5,
                cervicalBulge: 0.6, angulation: 3.5,
                labialInclination: 7.0, mesialDistalAngle: 5.0,
                incisorTip: 0.4, mammelonDepth: 0.25
            ),
            ageGroup: .adult,
            gender: .neutral
        ),

        // Masculine Presets
        ToothMorphologyPreset(
            name: "Masculine Bold",
            category: .masculine,
            description: "Strong, angular features with flat incisal edges",
            parameters: ToothParameters(
                width: 9.5, height: 11.5, thickness: 8.0,
                convexity: 0.3, incisalCurvature: 0.1,
                cervicalBulge: 0.4, angulation: 0.5,
                labialInclination: 5.0, mesialDistalAngle: 0.5,
                incisorTip: 0.1, mammelonDepth: 0.1
            ),
            ageGroup: .adult,
            gender: .male
        ),

        ToothMorphologyPreset(
            name: "Masculine Athletic",
            category: .masculine,
            description: "Powerful appearance with defined developmental grooves",
            parameters: ToothParameters(
                width: 10.0, height: 12.0, thickness: 8.5,
                convexity: 0.35, incisalCurvature: 0.15,
                cervicalBulge: 0.45, angulation: 1.0,
                labialInclination: 4.0, mesialDistalAngle: 1.0,
                incisorTip: 0.15, mammelonDepth: 0.2
            ),
            ageGroup: .adult,
            gender: .male
        ),

        // Feminine Presets
        ToothMorphologyPreset(
            name: "Feminine Delicate",
            category: .feminine,
            description: "Graceful curves with rounded incisal edges",
            parameters: ToothParameters(
                width: 8.0, height: 10.5, thickness: 7.0,
                convexity: 0.7, incisalCurvature: 0.6,
                cervicalBulge: 0.6, angulation: 3.0,
                labialInclination: 8.0, mesialDistalAngle: 4.0,
                incisorTip: 0.5, mammelonDepth: 0.3
            ),
            ageGroup: .adult,
            gender: .female
        ),

        ToothMorphologyPreset(
            name: "Feminine Elegant",
            category: .feminine,
            description: "Refined proportions with soft contours",
            parameters: ToothParameters(
                width: 8.2, height: 11.0, thickness: 7.2,
                convexity: 0.65, incisalCurvature: 0.5,
                cervicalBulge: 0.55, angulation: 2.5,
                labialInclination: 7.0, mesialDistalAngle: 3.5,
                incisorTip: 0.4, mammelonDepth: 0.25
            ),
            ageGroup: .adult,
            gender: .female
        ),

        // Youthful Presets
        ToothMorphologyPreset(
            name: "Youthful Bright",
            category: .youthful,
            description: "Vibrant mammelons and pronounced developmental lobes",
            parameters: ToothParameters(
                width: 8.5, height: 11.0, thickness: 7.5,
                convexity: 0.6, incisalCurvature: 0.4,
                cervicalBulge: 0.5, angulation: 2.0,
                labialInclination: 6.0, mesialDistalAngle: 3.0,
                incisorTip: 0.4, mammelonDepth: 0.4
            ),
            ageGroup: .young,
            gender: .neutral
        ),

        // Mature Presets
        ToothMorphologyPreset(
            name: "Mature Natural",
            category: .mature,
            description: "Subtle wear patterns with reduced incisal detail",
            parameters: ToothParameters(
                width: 8.5, height: 10.0, thickness: 7.5,
                convexity: 0.5, incisalCurvature: 0.2,
                cervicalBulge: 0.5, angulation: 1.5,
                labialInclination: 5.0, mesialDistalAngle: 2.0,
                incisorTip: 0.1, mammelonDepth: 0.05
            ),
            ageGroup: .mature,
            gender: .neutral
        ),

        // Aesthetic Presets
        ToothMorphologyPreset(
            name: "Hollywood Smile",
            category: .aesthetic,
            description: "Perfect proportions optimized for aesthetics",
            parameters: ToothParameters(
                width: 9.0, height: 11.5, thickness: 7.8,
                convexity: 0.55, incisalCurvature: 0.35,
                cervicalBulge: 0.5, angulation: 2.0,
                labialInclination: 6.5, mesialDistalAngle: 2.5,
                incisorTip: 0.3, mammelonDepth: 0.2
            ),
            ageGroup: .adult,
            gender: .neutral
        ),

        ToothMorphologyPreset(
            name: "Celebrity Ultra",
            category: .aesthetic,
            description: "Ultra-aesthetic with enhanced visibility and brightness",
            parameters: ToothParameters(
                width: 9.5, height: 12.0, thickness: 8.0,
                convexity: 0.6, incisalCurvature: 0.4,
                cervicalBulge: 0.55, angulation: 2.0,
                labialInclination: 7.0, mesialDistalAngle: 2.0,
                incisorTip: 0.35, mammelonDepth: 0.25
            ),
            ageGroup: .adult,
            gender: .neutral
        ),

        // Ethnic/Cultural Variations
        ToothMorphologyPreset(
            name: "Asian Harmony",
            category: .ethnic,
            description: "Proportions common in Asian populations",
            parameters: ToothParameters(
                width: 8.8, height: 10.5, thickness: 7.8,
                convexity: 0.55, incisalCurvature: 0.3,
                cervicalBulge: 0.5, angulation: 2.5,
                labialInclination: 8.0, mesialDistalAngle: 3.0,
                incisorTip: 0.3, mammelonDepth: 0.2
            ),
            ageGroup: .adult,
            gender: .neutral
        ),

        ToothMorphologyPreset(
            name: "European Classic",
            category: .ethnic,
            description: "Traditional European tooth morphology",
            parameters: ToothParameters(
                width: 8.5, height: 11.0, thickness: 7.5,
                convexity: 0.5, incisalCurvature: 0.3,
                cervicalBulge: 0.5, angulation: 2.0,
                labialInclination: 6.0, mesialDistalAngle: 2.5,
                incisorTip: 0.25, mammelonDepth: 0.2
            ),
            ageGroup: .adult,
            gender: .neutral
        ),

        ToothMorphologyPreset(
            name: "African Radiant",
            category: .ethnic,
            description: "Features common in African populations",
            parameters: ToothParameters(
                width: 9.0, height: 11.5, thickness: 8.0,
                convexity: 0.6, incisalCurvature: 0.4,
                cervicalBulge: 0.55, angulation: 2.5,
                labialInclination: 7.5, mesialDistalAngle: 3.0,
                incisorTip: 0.35, mammelonDepth: 0.25
            ),
            ageGroup: .adult,
            gender: .neutral
        )
    ]

    // MARK: - Category-based Access

    static func presets(for category: PresetCategory) -> [ToothMorphologyPreset] {
        return morphologyPresets.filter { $0.category == category }
    }

    static func presets(for ageGroup: AgeGroup) -> [ToothMorphologyPreset] {
        return morphologyPresets.filter { $0.ageGroup == ageGroup }
    }

    static func presets(for gender: Gender) -> [ToothMorphologyPreset] {
        return morphologyPresets.filter { $0.gender == gender || $0.gender == .neutral }
    }

    // MARK: - Smart Recommendations

    static func recommendPresets(
        age: Int? = nil,
        gender: Gender? = nil,
        facialProportions: FacialProportions? = nil
    ) -> [ToothMorphologyPreset] {

        var recommended = morphologyPresets

        // Filter by age
        if let age = age {
            let ageGroup: AgeGroup
            if age < 30 {
                ageGroup = .young
            } else if age < 55 {
                ageGroup = .adult
            } else {
                ageGroup = .mature
            }
            recommended = recommended.filter { $0.ageGroup == ageGroup || $0.ageGroup == .adult }
        }

        // Filter by gender
        if let gender = gender {
            recommended = recommended.filter { $0.gender == gender || $0.gender == .neutral }
        }

        // Consider facial proportions
        if let proportions = facialProportions {
            // If smile is wide, prefer wider tooth designs
            if proportions.smileWidthRatio > 1.1 {
                recommended = recommended.sorted { $0.parameters.width > $1.parameters.width }
            }
        }

        return Array(recommended.prefix(5)) // Top 5 recommendations
    }
}

// MARK: - Supporting Types

struct ToothMorphologyPreset: Identifiable {
    let id = UUID()
    var name: String
    var category: PresetCategory
    var description: String
    var parameters: ToothParameters
    var ageGroup: AgeGroup
    var gender: Gender
}

struct ToothParameters: Codable {
    var width: CGFloat           // mm
    var height: CGFloat          // mm
    var thickness: CGFloat       // mm
    var convexity: CGFloat       // 0-1
    var incisalCurvature: CGFloat // 0-1
    var cervicalBulge: CGFloat   // 0-1
    var angulation: CGFloat      // degrees
    var labialInclination: CGFloat // degrees
    var mesialDistalAngle: CGFloat // degrees
    var incisorTip: CGFloat      // 0-1 roundness
    var mammelonDepth: CGFloat   // 0-1 prominence
}

enum PresetCategory: String, CaseIterable, Codable {
    case natural = "Natural"
    case masculine = "Masculine"
    case feminine = "Feminine"
    case youthful = "Youthful"
    case mature = "Mature"
    case aesthetic = "Aesthetic"
    case ethnic = "Ethnic"
    case custom = "Custom"
}

enum AgeGroup: String, Codable {
    case young = "Young (18-30)"
    case adult = "Adult (30-55)"
    case mature = "Mature (55+)"
}

enum Gender: String, Codable {
    case male = "Male"
    case female = "Female"
    case neutral = "Neutral"
}

// MARK: - Tooth Shade Library

class ToothShadeLibrary {

    static let shadeGuides: [ShadeGuide] = [
        // Vita Classical Shade Guide
        ShadeGuide(
            name: "Vita Classical",
            manufacturer: "Vita Zahnfabrik",
            shades: [
                ToothShadeData(code: "A1", hue: "A", value: 1, chroma: 1, rgb: (240, 238, 232)),
                ToothShadeData(code: "A2", hue: "A", value: 2, chroma: 2, rgb: (235, 230, 220)),
                ToothShadeData(code: "A3", hue: "A", value: 3, chroma: 3, rgb: (230, 222, 210)),
                ToothShadeData(code: "A3.5", hue: "A", value: 3.5, chroma: 3.5, rgb: (225, 218, 205)),
                ToothShadeData(code: "A4", hue: "A", value: 4, chroma: 4, rgb: (220, 210, 195)),

                ToothShadeData(code: "B1", hue: "B", value: 1, chroma: 1, rgb: (240, 238, 230)),
                ToothShadeData(code: "B2", hue: "B", value: 2, chroma: 2, rgb: (235, 232, 220)),
                ToothShadeData(code: "B3", hue: "B", value: 3, chroma: 3, rgb: (230, 225, 210)),
                ToothShadeData(code: "B4", hue: "B", value: 4, chroma: 4, rgb: (225, 218, 200)),

                ToothShadeData(code: "C1", hue: "C", value: 1, chroma: 1, rgb: (238, 238, 232)),
                ToothShadeData(code: "C2", hue: "C", value: 2, chroma: 2, rgb: (232, 230, 220)),
                ToothShadeData(code: "C3", hue: "C", value: 3, chroma: 3, rgb: (228, 225, 212)),
                ToothShadeData(code: "C4", hue: "C", value: 4, chroma: 4, rgb: (222, 218, 200)),

                ToothShadeData(code: "D2", hue: "D", value: 2, chroma: 2, rgb: (235, 228, 218)),
                ToothShadeData(code: "D3", hue: "D", value: 3, chroma: 3, rgb: (230, 222, 208)),
                ToothShadeData(code: "D4", hue: "D", value: 4, chroma: 4, rgb: (225, 215, 195))
            ]
        ),

        // Vita 3D-Master
        ShadeGuide(
            name: "Vita 3D-Master",
            manufacturer: "Vita Zahnfabrik",
            shades: [
                ToothShadeData(code: "0M1", hue: "M", value: 0, chroma: 1, rgb: (250, 248, 245)),
                ToothShadeData(code: "0M2", hue: "M", value: 0, chroma: 2, rgb: (245, 242, 238)),
                ToothShadeData(code: "0M3", hue: "M", value: 0, chroma: 3, rgb: (240, 235, 230)),
                ToothShadeData(code: "1M1", hue: "M", value: 1, chroma: 1, rgb: (245, 242, 235)),
                ToothShadeData(code: "1M2", hue: "M", value: 1, chroma: 2, rgb: (240, 235, 228)),
                ToothShadeData(code: "2M1", hue: "M", value: 2, chroma: 1, rgb: (238, 235, 228)),
                ToothShadeData(code: "2M2", hue: "M", value: 2, chroma: 2, rgb: (235, 230, 220)),
                ToothShadeData(code: "2M3", hue: "M", value: 2, chroma: 3, rgb: (230, 222, 210)),
                ToothShadeData(code: "3M1", hue: "M", value: 3, chroma: 1, rgb: (235, 228, 218)),
                ToothShadeData(code: "3M2", hue: "M", value: 3, chroma: 2, rgb: (230, 222, 208)),
                ToothShadeData(code: "3M3", hue: "M", value: 3, chroma: 3, rgb: (225, 215, 200)),
                ToothShadeData(code: "4M1", hue: "M", value: 4, chroma: 1, rgb: (228, 220, 208)),
                ToothShadeData(code: "4M2", hue: "M", value: 4, chroma: 2, rgb: (222, 212, 195)),
                ToothShadeData(code: "5M1", hue: "M", value: 5, chroma: 1, rgb: (220, 210, 195)),
                ToothShadeData(code: "5M2", hue: "M", value: 5, chroma: 2, rgb: (215, 202, 185))
            ]
        ),

        // Bleach Shades
        ShadeGuide(
            name: "Bleach Shades",
            manufacturer: "Multiple",
            shades: [
                ToothShadeData(code: "BL1", hue: "BL", value: 1, chroma: 0, rgb: (255, 255, 252)),
                ToothShadeData(code: "BL2", hue: "BL", value: 2, chroma: 0, rgb: (252, 250, 248)),
                ToothShadeData(code: "BL3", hue: "BL", value: 3, chroma: 0, rgb: (248, 245, 242)),
                ToothShadeData(code: "BL4", hue: "BL", value: 4, chroma: 0, rgb: (245, 242, 238))
            ]
        )
    ]

    static func findShade(byCode code: String) -> ToothShadeData? {
        for guide in shadeGuides {
            if let shade = guide.shades.first(where: { $0.code == code }) {
                return shade
            }
        }
        return nil
    }

    static func recommendShade(for skinTone: SkinTone) -> ToothShadeData? {
        switch skinTone {
        case .veryLight:
            return findShade(byCode: "A1")
        case .light:
            return findShade(byCode: "A2")
        case .medium:
            return findShade(byCode: "A3")
        case .tan:
            return findShade(byCode: "A3.5")
        case .dark:
            return findShade(byCode: "B2")
        }
    }
}

struct ShadeGuide {
    var name: String
    var manufacturer: String
    var shades: [ToothShadeData]
}

struct ToothShadeData: Identifiable {
    let id = UUID()
    var code: String
    var hue: String
    var value: Double
    var chroma: Double
    var rgb: (r: Int, g: Int, b: Int)

    var color: NSColor {
        return NSColor(
            red: CGFloat(rgb.r) / 255.0,
            green: CGFloat(rgb.g) / 255.0,
            blue: CGFloat(rgb.b) / 255.0,
            alpha: 1.0
        )
    }
}

enum SkinTone: String, CaseIterable {
    case veryLight = "Very Light"
    case light = "Light"
    case medium = "Medium"
    case tan = "Tan"
    case dark = "Dark"
}
