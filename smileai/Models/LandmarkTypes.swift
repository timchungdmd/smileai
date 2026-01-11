import Foundation
import SwiftUI
import SceneKit

enum LandmarkType: String, CaseIterable, Codable {
    // Eyes & Upper Face (Blue/Purple)
    case rightPupil = "Right Pupil"
    case leftPupil = "Left Pupil"
    case glabella = "Glabella"
    case nasion = "Nasion (Root)" // NEW
    
    // Mid Face (Yellow/Orange)
    case subnasale = "Subnasale (Base)"
    case rightAla = "Right Ala" // NEW
    case leftAla = "Left Ala" // NEW
    case rightZygoma = "Right Zygoma" // NEW
    case leftZygoma = "Left Zygoma" // NEW
    
    // Ears (Green)
    case rightTragus = "Right Tragus" // NEW
    case leftTragus = "Left Tragus" // NEW
    
    // Lower Face & Lips (Red/Pink)
    case upperLipCenter = "Upper Lip Center"
    case lowerLipCenter = "Lower Lip Center"
    case rightCommissure = "R. Mouth Corner"
    case leftCommissure = "L. Mouth Corner"
    case menton = "Menton (Chin)"
    case pogonion = "Pogonion (Chin Proj)" // NEW
    
    // Teeth (Cyan/White)
    case midline = "Dental Midline"
    case rightCanine = "Right Canine"
    case leftCanine = "Left Canine"
    
    /// Distinct color for each landmark group
    var color: Color {
        switch self {
        case .rightPupil, .leftPupil: return .blue
        case .glabella, .nasion: return .purple
            
        case .subnasale, .rightAla, .leftAla: return .yellow
        case .rightZygoma, .leftZygoma: return .orange
            
        case .rightTragus, .leftTragus: return .green
            
        case .upperLipCenter, .lowerLipCenter: return .pink
        case .rightCommissure, .leftCommissure: return .red
        case .menton, .pogonion: return .brown
            
        case .midline, .rightCanine, .leftCanine: return .cyan
        }
    }
    
    /// Helper for SceneKit conversion
    #if os(macOS)
    var nsColor: NSColor { NSColor(color) }
    #else
    var uiColor: UIColor { UIColor(color) }
    #endif
}

enum DesignMode: Int, CaseIterable, Identifiable {
    case analysis = 0
    case design = 1
    
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .analysis: return "Analysis"
        case .design: return "Design"
        }
    }
}

struct OcclusalPlane {
    var origin: SCNVector3
    var normal: SCNVector3
    
    static func computeFromLandmarks(_ landmarks: [LandmarkType: SCNVector3]) -> OcclusalPlane? {
        guard let g = landmarks[.glabella],
              let lc = landmarks[.leftCanine],
              let rc = landmarks[.rightCanine] else { return nil }
        
        let v1 = lc - g
        let v2 = rc - g
        let normal = v1.cross(v2).normalized
        
        return OcclusalPlane(origin: g, normal: normal)
    }
}
