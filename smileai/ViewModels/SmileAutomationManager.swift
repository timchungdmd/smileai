import SwiftUI
import SceneKit
import Combine

@MainActor
class SmileAutomationManager: ObservableObject {
    
    // MARK: - State
    enum Status: Equatable {
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
        // FIX: Use 'transformedTeeth' array to get positions
        let activeTeeth = overlayState.transformedTeeth
        let points2D = activeTeeth.map { $0.position }
        
        // 2. Call the Bridge (Project to 3D)
        guard let projector = projectionDelegate, !points2D.isEmpty else {
            self.errorMessage = "Projection Bridge not connected or no teeth placed"
            self.status = .idle
            return [:]
        }
        
        let points3D = projector(points2D)
        
        // 3. Instantiate & Optimize in Background
        self.status = .optimizing(progress: 0.0)
        
        // FIX: Store task in a variable to avoid compiler confusion regarding 'await'
        let task = Task.detached(priority: .userInitiated) {
            var newStates: [String: ToothState] = [:]
            
            for (index, tooth) in activeTeeth.enumerated() {
                // Ensure we don't go out of bounds if projection failed for some points
                guard index < points3D.count else { break }
                
                let targetPos = points3D[index]
                let toothID = tooth.toothNumber
                
                // FIX: Explicitly cast CGFloat (SCNVector3) to Float (SIMD3)
                // This is required because SCNVector3 uses CGFloat on macOS but SIMD3<Float> requires Float
                let x = Float(targetPos.x)
                let y = Float(targetPos.y)
                let z = Float(targetPos.z)
                
                // Create State using SIMD3<Float>
                let state = ToothState(
                    positionOffset: SIMD3<Float>(x, y, z),
                    rotation: SIMD3<Float>(0, 0, 0), // Default zero rotation
                    scale: SIMD3<Float>(1, 1, 1)     // Default scale
                )
                
                newStates[toothID] = state
            }
            
            return newStates
        }
        
        // Await the result of the task
        let result = await task.value
        
        self.status = .idle
        return result
    }
    
    func applyOptimization() {
        self.status = .idle
    }
}
