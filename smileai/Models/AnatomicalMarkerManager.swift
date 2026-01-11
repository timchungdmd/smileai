import SwiftUI
import Combine
import SceneKit

class AnatomicalMarkerManager: ObservableObject {
    // MARK: - Data Stores
    @Published var landmarks3D: [LandmarkType: SCNVector3] = [:]
    @Published var landmarks2D: [LandmarkType: CGPoint] = [:]
    
    // MARK: - State Flags
    @Published var isPlacingMode: Bool = false
    @Published var isLocked: Bool = false
    
    // MARK: - Sequence Definition (Updated with new markers)
    private let placementSequence: [LandmarkType] = [
        // Eyes
        .rightPupil, .leftPupil, .glabella, .nasion,
        // Ears
        .rightTragus, .leftTragus,
        // Midface
        .rightZygoma, .leftZygoma, .subnasale, .rightAla, .leftAla,
        // Mouth
        .rightCommissure, .leftCommissure, .upperLipCenter, .lowerLipCenter,
        // Chin
        .menton, .pogonion,
        // Teeth
        .midline, .rightCanine, .leftCanine
    ]
    
    // MARK: - Logic
    func nextLandmark(hasFacePhoto: Bool) -> LandmarkType? {
        if isLocked { return nil }
        return placementSequence.first { type in
            if hasFacePhoto { return landmarks2D[type] == nil }
            else { return landmarks3D[type] == nil }
        }
    }
    
    func getCurrentPrompt(hasFacePhoto: Bool) -> String {
        if let next = nextLandmark(hasFacePhoto: hasFacePhoto) {
            return "Place: \(next.rawValue)"
        }
        return "All Markers Placed"
    }
    
    // MARK: - Actions
    func addLandmark3D(_ position: SCNVector3) {
        guard isPlacingMode, !isLocked, let type = nextLandmark(hasFacePhoto: false) else { return }
        landmarks3D[type] = position
        playSound()
    }
    
    func addLandmark2D(_ point: CGPoint) {
        guard isPlacingMode, !isLocked, let type = nextLandmark(hasFacePhoto: true) else { return }
        landmarks2D[type] = point
        playSound()
    }
    
    func undoLast(hasFacePhoto: Bool) {
        let placed = placementSequence.reversed()
        if hasFacePhoto {
            if let last = placed.first(where: { landmarks2D[$0] != nil }) { landmarks2D.removeValue(forKey: last) }
        } else {
            if let last = placed.first(where: { landmarks3D[$0] != nil }) { landmarks3D.removeValue(forKey: last) }
        }
    }
    
    func reset() {
        landmarks3D.removeAll()
        landmarks2D.removeAll()
        isPlacingMode = false
        isLocked = false
    }
    
    private func playSound() {
        #if os(macOS)
        NSSound.beep()
        #endif
    }
}
