import SwiftUI
import SceneKit
import Combine

@MainActor
class SmileAutomationManager: ObservableObject {
    
    // MARK: - State
    enum Status {
        case idle
        case projecting
        case optimizing(progress: Float)
        case completed
    }
    
    @Published var status: Status = .idle
    @Published var errorMessage: String?
    
    // MARK: - Delegates (The "Glue")
    // The ViewWrapper will assign this closure to allow us to talk to the SCNView
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
        
        // 1. Gather 2D centers from the overlay
        // We need to map tooth IDs (e.g., "11", "21") to their 2D positions
        let activeTeeth = overlayState.transforms.keys.sorted()
        let points2D = activeTeeth.map { overlayState.transforms[$0]?.position ?? .zero }
        
        // 2. Call the Bridge (Project to 3D)
        guard let projector = projectionDelegate else {
            self.errorMessage = "Projection Bridge not connected"
            return [:]
        }
        
        let points3D = projector(points2D)
        
        // 3. Instantiate & Optimize in Background
        self.status = .optimizing(progress: 0.0)
        
        return await Task.detached(priority: .userInitiated) {
            var newStates: [String: ToothState] = [:]
            let total = Float(activeTeeth.count)
            
            for (index, toothID) in activeTeeth.enumerated() {
                let targetPos = points3D[index]
                
                // A. Initial Placement (Snap to Surface)
                // Default rotation: Facing Forward (-Z) usually, depending on your model axis
                let initialRotation = SCNVector4(0, 1, 0, 0)
                
                var finalPos = targetPos
                var finalRot = initialRotation
                
                // B. Insertion Axis Optimization (Optional but recommended)
                // (Using a placeholder crown node for calculation)
                let tempCrown = SCNNode() // In real app, load actual geometry here
                tempCrown.position = targetPos
                
                if let scan = scanNode {
                    // Calculate "Up" vector relative to the gum surface
                    // For now, we assume standard vertical, but InsertionAxisCalculator can refine this
                }
                
                // C. Occlusal Alignment (If antagonist exists)
                if let antagonist = antagonistNode {
                    // Run the physics engine
                    // Note: We need actual geometry for this to work well.
                    // Since we are just generating states, we might skip heavy physics
                    // until the models are actually loaded in the scene.
                }
                
                // D. Create State
                let state = ToothState(
                    position: finalPos,
                    rotation: finalRot,
                    scale: SCNVector3(1, 1, 1), // User mentioned models are not to scale; we'll fix this later
                    visible: true
                )
                
                newStates[toothID] = state
                
                // Update Progress
                await MainActor.run {
                    // self.status = .optimizing(progress: Float(index) / total)
                    // (Requires actor hopping, simplified for now)
                }
            }
            
            return newStates
        }.value
    }
    
    func applyOptimization() {
        self.status = .idle
    }
}
