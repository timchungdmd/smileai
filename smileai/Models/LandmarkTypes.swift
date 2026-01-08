import Foundation
import SceneKit

enum LandmarkType: String, CaseIterable, Codable {
    case rightPupil = "Right Pupil"
    case leftPupil = "Left Pupil"
    case glabella = "Glabella (Brows)"
    case subnasale = "Subnasale (Nose Base)"
    case menton = "Menton (Chin Tip)"
    case rightCommissure = "Right Mouth Corner"
    case leftCommissure = "Left Mouth Corner"
    case upperLipCenter = "Upper Lip Center"
    case lowerLipCenter = "Lower Lip Center"
    case midline = "Dental Midline"
    case leftCanine = "Left Canine Tip"
    case rightCanine = "Right Canine Tip"
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
    
    func transformMatrix() -> SCNMatrix4 {
        let up = SCNVector3(0, 1, 0)
        let axis = up.cross(normal).normalized
        let angle = acos(up.dot(normal))
        
        // FIX: Cast Float to CGFloat
        return SCNMatrix4MakeRotation(CGFloat(angle), CGFloat(axis.x), CGFloat(axis.y), CGFloat(axis.z))
    }
}
