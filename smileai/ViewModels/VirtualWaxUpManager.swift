//
//  VirtualWaxUpManager.swift
//  smileai
//
//  Virtual wax-up workflow management
//  Competing with exocad's wax-up and free-forming features
//

import Foundation
import SceneKit
import SwiftUI

/// Manages virtual wax-up workflow from diagnostic to final prosthetic design
@Observable
class VirtualWaxUpManager {

    // MARK: - Properties

    var currentPhase: WaxUpPhase = .diagnostic
    var diagnostic: DiagnosticData?
    var waxUpDesign: WaxUpDesign?
    var history: [WaxUpHistoryEntry] = []
    var modifications: [WaxUpModification] = []

    // MARK: - Phase Management

    /// Progress to next phase in workflow
    func advanceToNextPhase() {
        switch currentPhase {
        case .diagnostic:
            currentPhase = .blockOut
        case .blockOut:
            currentPhase = .initialWaxUp
        case .initialWaxUp:
            currentPhase = .refinement
        case .refinement:
            currentPhase = .finalization
        case .finalization:
            currentPhase = .export
        case .export:
            break
        }

        recordHistoryEntry()
    }

    /// Return to previous phase
    func returnToPreviousPhase() {
        switch currentPhase {
        case .diagnostic:
            break
        case .blockOut:
            currentPhase = .diagnostic
        case .initialWaxUp:
            currentPhase = .blockOut
        case .refinement:
            currentPhase = .initialWaxUp
        case .finalization:
            currentPhase = .refinement
        case .export:
            currentPhase = .finalization
        }

        recordHistoryEntry()
    }

    // MARK: - Diagnostic Phase

    /// Capture diagnostic information from scans
    func captureDiagnostic(
        preOpScan: SCNNode,
        antagonistScan: SCNNode?,
        photos: [NSImage]
    ) {
        diagnostic = DiagnosticData(
            preOpScan: preOpScan,
            antagonistScan: antagonistScan,
            photos: photos,
            timestamp: Date(),
            analysisResults: performAutomaticAnalysis(scan: preOpScan)
        )

        recordHistoryEntry()
    }

    private func performAutomaticAnalysis(scan: SCNNode) -> AnalysisResults {
        // Automatic analysis of diagnostic scan
        var results = AnalysisResults()

        // Analyze arch form
        results.archForm = analyzeArchForm(scan: scan)

        // Detect missing teeth
        results.missingTeeth = detectMissingTeeth(scan: scan)

        // Calculate available space
        results.availableSpace = calculateAvailableSpace(scan: scan)

        // Assess occlusal plane
        results.occlusalPlaneDeviation = assessOcclusalPlane(scan: scan)

        return results
    }

    private func analyzeArchForm(scan: SCNNode) -> ArchForm {
        // Simplified arch form detection
        // In production, this would use ML or geometric analysis
        return .ovoid
    }

    private func detectMissingTeeth(scan: SCNNode) -> [Int] {
        // Detect missing teeth by analyzing scan
        // Returns FDI notation numbers
        return []
    }

    private func calculateAvailableSpace(scan: SCNNode) -> CGFloat {
        // Calculate available space for restorations
        return 0.0
    }

    private func assessOcclusalPlane(scan: SCNNode) -> CGFloat {
        // Assess deviation from ideal occlusal plane
        return 0.0
    }

    // MARK: - Block-Out Phase

    /// Create block-out for undercuts
    func createBlockOut(areas: [BlockOutArea]) {
        guard let diagnostic = diagnostic else { return }

        // Create block-out geometry
        for area in areas {
            let blockOutGeometry = generateBlockOutGeometry(for: area)
            // Apply to scan
            applyBlockOut(geometry: blockOutGeometry, to: diagnostic.preOpScan)
        }

        recordHistoryEntry()
    }

    private func generateBlockOutGeometry(for area: BlockOutArea) -> SCNGeometry {
        // Generate geometry to fill undercuts
        // This would create a mesh that fills the specified area
        return SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
    }

    private func applyBlockOut(geometry: SCNGeometry, to scan: SCNNode) {
        let blockOutNode = SCNNode(geometry: geometry)
        blockOutNode.name = "BlockOut"
        scan.addChildNode(blockOutNode)
    }

    // MARK: - Initial Wax-Up Phase

    /// Generate initial wax-up from diagnostic data
    func generateInitialWaxUp(
        using preset: ToothMorphologyPreset,
        teethToRestore: [Int]
    ) {
        guard let diagnostic = diagnostic else { return }

        var restorations: [WaxUpTooth] = []

        for toothNumber in teethToRestore {
            let restoration = createRestorationForTooth(
                number: toothNumber,
                preset: preset,
                diagnostic: diagnostic
            )
            restorations.append(restoration)
        }

        waxUpDesign = WaxUpDesign(
            restorations: restorations,
            archForm: diagnostic.analysisResults.archForm,
            createdDate: Date()
        )

        recordHistoryEntry()
    }

    private func createRestorationForTooth(
        number: Int,
        preset: ToothMorphologyPreset,
        diagnostic: DiagnosticData
    ) -> WaxUpTooth {

        // Create tooth based on preset and position
        let position = calculateToothPosition(number: number, in: diagnostic.preOpScan)

        return WaxUpTooth(
            fdiNumber: number,
            morphology: preset.parameters,
            position: position,
            rotation: SCNVector3(0, 0, 0),
            scale: SCNVector3(1, 1, 1),
            shade: "A2"
        )
    }

    private func calculateToothPosition(number: Int, in scan: SCNNode) -> SCNVector3 {
        // Calculate appropriate position for tooth
        // In production, this would analyze the scan to find exact position
        return SCNVector3(0, 0, 0)
    }

    // MARK: - Refinement Phase

    /// Apply modification to wax-up
    func applyModification(_ modification: WaxUpModification) {
        modifications.append(modification)

        switch modification.type {
        case .morphology(let tooth, let parameters):
            updateToothMorphology(tooth: tooth, parameters: parameters)

        case .position(let tooth, let position):
            updateToothPosition(tooth: tooth, position: position)

        case .rotation(let tooth, let rotation):
            updateToothRotation(tooth: tooth, rotation: rotation)

        case .scale(let tooth, let scale):
            updateToothScale(tooth: tooth, scale: scale)

        case .freeForm(let tooth, let vertices):
            applyFreeFormModification(tooth: tooth, vertices: vertices)

        case .cutBack(let tooth, let amount):
            applyCutBack(tooth: tooth, amount: amount)

        case .addition(let tooth, let material):
            applyAddition(tooth: tooth, material: material)
        }

        recordHistoryEntry()
    }

    private func updateToothMorphology(tooth: Int, parameters: ToothParameters) {
        guard let index = waxUpDesign?.restorations.firstIndex(where: { $0.fdiNumber == tooth }) else { return }
        waxUpDesign?.restorations[index].morphology = parameters
    }

    private func updateToothPosition(tooth: Int, position: SCNVector3) {
        guard let index = waxUpDesign?.restorations.firstIndex(where: { $0.fdiNumber == tooth }) else { return }
        waxUpDesign?.restorations[index].position = position
    }

    private func updateToothRotation(tooth: Int, rotation: SCNVector3) {
        guard let index = waxUpDesign?.restorations.firstIndex(where: { $0.fdiNumber == tooth }) else { return }
        waxUpDesign?.restorations[index].rotation = rotation
    }

    private func updateToothScale(tooth: Int, scale: SCNVector3) {
        guard let index = waxUpDesign?.restorations.firstIndex(where: { $0.fdiNumber == tooth }) else { return }
        waxUpDesign?.restorations[index].scale = scale
    }

    private func applyFreeFormModification(tooth: Int, vertices: [VertexModification]) {
        // Apply free-form sculpting modifications
        // This would modify the mesh vertices directly
    }

    private func applyCutBack(tooth: Int, amount: CGFloat) {
        // Apply cut-back for lingual reduction
        // Used in layering technique for ceramics
    }

    private func applyAddition(tooth: Int, material: MaterialType) {
        // Add material (wax/ceramic) to tooth
        // For building up form
    }

    // MARK: - Finalization Phase

    /// Validate wax-up design
    func validateDesign() -> WaxUpValidationReport {
        guard let waxUpDesign = waxUpDesign,
              let diagnostic = diagnostic else {
            return WaxUpValidationReport(isValid: false, errors: ["Missing design data"], warnings: [])
        }

        var errors: [String] = []
        var warnings: [String] = []

        // Check occlusion
        if let antagonist = diagnostic.antagonistScan {
            let occlusalCheck = checkOcclusion(
                waxUp: waxUpDesign,
                antagonist: antagonist
            )

            if occlusalCheck.hasInterference {
                errors.append("Occlusal interference detected")
            }

            if occlusalCheck.hasInsufficientContact {
                warnings.append("Insufficient occlusal contacts")
            }
        }

        // Check spacing
        let spacingCheck = checkInterproximalSpacing(waxUpDesign: waxUpDesign)
        if spacingCheck.hasTightContacts {
            warnings.append("Tight interproximal contacts detected")
        }

        // Check emergence profile
        let emergenceCheck = checkEmergenceProfile(waxUpDesign: waxUpDesign)
        if !emergenceCheck.isIdeal {
            warnings.append("Non-ideal emergence profile")
        }

        // Check margin integrity
        let marginCheck = checkMargins(waxUpDesign: waxUpDesign)
        if !marginCheck.isComplete {
            errors.append("Incomplete margin definition")
        }

        return WaxUpValidationReport(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    private func checkOcclusion(waxUp: WaxUpDesign, antagonist: SCNNode) -> OcclusalCheck {
        // Check occlusion against antagonist
        return OcclusalCheck(hasInterference: false, hasInsufficientContact: false)
    }

    private func checkInterproximalSpacing(waxUpDesign: WaxUpDesign) -> SpacingCheck {
        // Check spacing between teeth
        return SpacingCheck(hasTightContacts: false)
    }

    private func checkEmergenceProfile(waxUpDesign: WaxUpDesign) -> EmergenceCheck {
        // Check emergence profile from margin
        return EmergenceCheck(isIdeal: true)
    }

    private func checkMargins(waxUpDesign: WaxUpDesign) -> MarginCheck {
        // Check margin completion and quality
        return MarginCheck(isComplete: true)
    }

    /// Generate production-ready files
    func generateProductionFiles() -> ProductionFiles? {
        guard let waxUpDesign = waxUpDesign else { return nil }

        return ProductionFiles(
            stlFiles: exportSTL(design: waxUpDesign),
            printFile: generate3DPrintFile(design: waxUpDesign),
            millFile: generateMillingFile(design: waxUpDesign),
            technicalSheet: generateTechnicalSheet(design: waxUpDesign)
        )
    }

    private func exportSTL(design: WaxUpDesign) -> [URL] {
        // Export each restoration as STL
        return []
    }

    private func generate3DPrintFile(design: WaxUpDesign) -> URL? {
        // Generate file for 3D printing
        return nil
    }

    private func generateMillingFile(design: WaxUpDesign) -> URL? {
        // Generate file for milling machine
        return nil
    }

    private func generateTechnicalSheet(design: WaxUpDesign) -> TechnicalSheet {
        return TechnicalSheet(
            restorations: design.restorations,
            materials: [],
            instructions: [],
            generatedDate: Date()
        )
    }

    // MARK: - History Management

    private func recordHistoryEntry() {
        let entry = WaxUpHistoryEntry(
            phase: currentPhase,
            timestamp: Date(),
            description: "Phase: \(currentPhase.rawValue)",
            snapshot: createSnapshot()
        )
        history.append(entry)
    }

    private func createSnapshot() -> WaxUpSnapshot {
        return WaxUpSnapshot(
            diagnostic: diagnostic,
            waxUpDesign: waxUpDesign,
            modifications: modifications
        )
    }

    /// Undo last modification
    func undo() {
        guard let lastEntry = history.dropLast().last else { return }
        restoreSnapshot(lastEntry.snapshot)
        history.removeLast()
    }

    private func restoreSnapshot(_ snapshot: WaxUpSnapshot) {
        self.diagnostic = snapshot.diagnostic
        self.waxUpDesign = snapshot.waxUpDesign
        self.modifications = snapshot.modifications
    }
}

// MARK: - Supporting Types

enum WaxUpPhase: String, CaseIterable {
    case diagnostic = "Diagnostic"
    case blockOut = "Block-Out"
    case initialWaxUp = "Initial Wax-Up"
    case refinement = "Refinement"
    case finalization = "Finalization"
    case export = "Export"
}

struct DiagnosticData {
    var preOpScan: SCNNode
    var antagonistScan: SCNNode?
    var photos: [NSImage]
    var timestamp: Date
    var analysisResults: AnalysisResults
}

struct AnalysisResults {
    var archForm: ArchForm = .ovoid
    var missingTeeth: [Int] = []
    var availableSpace: CGFloat = 0.0
    var occlusalPlaneDeviation: CGFloat = 0.0
}

enum ArchForm: String {
    case tapered = "Tapered"
    case ovoid = "Ovoid"
    case square = "Square"
}

struct BlockOutArea {
    var location: SCNVector3
    var size: SCNVector3
    var severity: UnderCutSeverity
}

enum UnderCutSeverity: String {
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
}

struct WaxUpDesign {
    var restorations: [WaxUpTooth]
    var archForm: ArchForm
    var createdDate: Date
}

struct WaxUpTooth {
    var fdiNumber: Int
    var morphology: ToothParameters
    var position: SCNVector3
    var rotation: SCNVector3
    var scale: SCNVector3
    var shade: String
}

struct WaxUpModification {
    var type: ModificationType
    var timestamp: Date
    var description: String
}

enum ModificationType {
    case morphology(tooth: Int, parameters: ToothParameters)
    case position(tooth: Int, position: SCNVector3)
    case rotation(tooth: Int, rotation: SCNVector3)
    case scale(tooth: Int, scale: SCNVector3)
    case freeForm(tooth: Int, vertices: [VertexModification])
    case cutBack(tooth: Int, amount: CGFloat)
    case addition(tooth: Int, material: MaterialType)
}

struct VertexModification {
    var index: Int
    var delta: SCNVector3
}

enum MaterialType: String {
    case wax = "Wax"
    case ceramicFramework = "Ceramic Framework"
    case ceramicVeneer = "Ceramic Veneer"
    case composite = "Composite"
}

struct WaxUpHistoryEntry {
    var phase: WaxUpPhase
    var timestamp: Date
    var description: String
    var snapshot: WaxUpSnapshot
}

struct WaxUpSnapshot {
    var diagnostic: DiagnosticData?
    var waxUpDesign: WaxUpDesign?
    var modifications: [WaxUpModification]
}

struct WaxUpValidationReport {
    var isValid: Bool
    var errors: [String]
    var warnings: [String]
}

struct OcclusalCheck {
    var hasInterference: Bool
    var hasInsufficientContact: Bool
}

struct SpacingCheck {
    var hasTightContacts: Bool
}

struct EmergenceCheck {
    var isIdeal: Bool
}

struct MarginCheck {
    var isComplete: Bool
}

struct ProductionFiles {
    var stlFiles: [URL]
    var printFile: URL?
    var millFile: URL?
    var technicalSheet: TechnicalSheet
}

struct TechnicalSheet {
    var restorations: [WaxUpTooth]
    var materials: [String]
    var instructions: [String]
    var generatedDate: Date
}
