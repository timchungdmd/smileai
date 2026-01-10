import SwiftUI
import SceneKit
import Combine

@MainActor
class SmileAutomationManager: ObservableObject {
    
    enum Status: Equatable {
        case idle
        case projecting
        case optimizing(progress: Float)
        case completed
    }
    
    @Published var status: Status = .idle
    @Published var errorMessage: String?
    
    // MARK: - Delegates
    var projectionDelegate: ((_ points: [CGPoint]) -> [SCNVector3])?
    
    // MARK: - Dependencies
    private let insertionCalc = InsertionAxisCalculator()
    private let occlusalEngine = OcclusalAlignmentEngine()
    
    // MARK: - Main Workflow
    func runAutoDesign(
        overlayState: SmileOverlayState,
        scanNode: SCNNode?,
        antagonistNode: SCNNode?
    ) async -> [String: ToothState] {
        
        self.status = .projecting
        
        // 1. Gather 2D centers from the overlay using the calculated transforms
        let activeTeeth = overlayState.transformedTeeth
        let points2D = activeTeeth.map { $0.position }
        
        // 2. Call the Bridge
        guard let projector = projectionDelegate, !points2D.isEmpty else {
            self.errorMessage = "Projection Bridge not connected or no teeth placed"
            self.status = .idle
            return [:]
        }
        
        let points3D = projector(points2D)
        
        // 3. Instantiate & Optimize in Background
        self.status = .optimizing(progress: 0.0)
        
        // Run heavy math off the main thread
        let task = Task.detached(priority: .userInitiated) {
            var newStates: [String: ToothState] = [:]
            
            for (index, tooth) in activeTeeth.enumerated() {
                guard index < points3D.count else { break }
                
                let targetPos = points3D[index]
                let initialRotation = SCNVector4(0, 1, 0, 0)
                
                // Here we map the 2D "toothNumber" (e.g. "11") to the 3D state key
                // Assuming ToothOverlay2D has a 'toothNumber' or 'id' property we can use
                // If using UUID, we might need a mapping strategy.
                // For now, we assume toothNumber matches standard string keys.
                let key = tooth.toothNumber
                
                let state = ToothState(
                    position: targetPos,
                    rotation: initialRotation,
                    scale: SCNVector3(1, 1, 1),
                    visible: true
                )
                
                newStates[key] = state
            }
            return newStates
        }
        
        let result = await task.value
        self.status = .idle
        return result
    }
}
