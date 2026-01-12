//
//  ArticulatorIntegration.swift
//  smileai
//
//  Integration manager for Virtual Articulator in 3D scene
//

import Foundation
import SceneKit
import Combine

/// Manages integration of Virtual Articulator with the 3D scene
@Observable
class ArticulatorIntegrationManager {

    // MARK: - Properties

    var articulator: VirtualArticulator
    var isEnabled: Bool = false
    var currentReport: OcclusalAnalysisReport?
    var activeMovement: MovementType?

    private var cancellables = Set<AnyCancellable>()
    private var scene: SCNScene?

    // MARK: - Initialization

    init(settings: ArticulatorSettings = .default) {
        self.articulator = VirtualArticulator(settings: settings)
        setupNotificationObservers()
    }

    // MARK: - Setup

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SimulateArticulatorMovement"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let movementType = notification.object as? MovementType {
                self?.simulateMovement(type: movementType)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AnalyzeOcclusion"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.analyzeOcclusion()
        }
    }

    // MARK: - Scene Integration

    /// Mount upper and lower arches in the articulator
    func mountArches(upperArch: SCNNode, lowerArch: SCNNode, scene: SCNScene) {
        self.scene = scene

        // Create mounting data (in production, this would be user-configured or auto-detected)
        let mounting = MountingData(
            upperMounting: .identity,
            lowerMounting: .identity
        )

        articulator.mountModels(
            upperArch: upperArch,
            lowerArch: lowerArch,
            mounting: mounting
        )

        isEnabled = true
    }

    /// Unmount models from articulator
    func unmount() {
        articulator.upperArchNode = nil
        articulator.lowerArchNode = nil
        isEnabled = false
    }

    // MARK: - Movement Simulation

    /// Simulate a specific jaw movement
    func simulateMovement(type: MovementType, duration: TimeInterval = 2.0) {
        guard isEnabled else { return }

        activeMovement = type

        articulator.simulateMovement(type: type, duration: duration) { [weak self] report in
            self?.handleMovementReport(report)
            self?.activeMovement = nil
        }
    }

    private func handleMovementReport(_ report: CollisionReport) {
        print("📊 Movement Report:")
        print("  Type: \(report.movementType.rawValue)")
        print("  Collisions: \(report.collisionCount)")
        print("  Max Penetration: \(report.maxPenetration)mm")
        print("  Severity: \(report.severity.rawValue)")

        // Visualize collision points if needed
        if report.severity == .moderate || report.severity == .severe {
            visualizeCollisions(report.collisions)
        }
    }

    // MARK: - Occlusal Analysis

    /// Perform comprehensive occlusal analysis
    func analyzeOcclusion() {
        guard isEnabled else { return }

        let report = articulator.analyzeOcclusion()
        currentReport = report

        print("🔍 Occlusal Analysis Report:")
        print("  Overall Score: \(String(format: "%.1f", report.overallScore))/100")
        print("  Movements Analyzed: \(report.movementReports.count)")

        for movementReport in report.movementReports {
            print("\n  \(movementReport.type.rawValue):")
            print("    Collisions: \(movementReport.collisionCount)")
            print("    Max Penetration: \(String(format: "%.2f", movementReport.maxPenetration))mm")

            if !movementReport.problematicPhases.isEmpty {
                print("    Issues:")
                for phase in movementReport.problematicPhases {
                    print("      - \(phase)")
                }
            }
        }

        print("\n  Recommendations:")
        for recommendation in report.recommendations {
            print("    • \(recommendation)")
        }

        // Notify UI to show report
        NotificationCenter.default.post(
            name: NSNotification.Name("OcclusalAnalysisComplete"),
            object: report
        )
    }

    // MARK: - Visualization

    /// Visualize collision points in the scene
    private func visualizeCollisions(_ collisions: [CollisionEvent]) {
        guard let scene = scene else { return }

        // Remove previous collision markers
        scene.rootNode.childNodes.filter { $0.name == "CollisionMarker" }.forEach { $0.removeFromParentNode() }

        // Add new collision markers
        for collision in collisions {
            for toothCollision in collision.toothCollisions {
                let marker = createCollisionMarker(at: toothCollision.contactPoint, severity: collision.penetrationDepth)
                marker.name = "CollisionMarker"
                scene.rootNode.addChildNode(marker)
            }
        }
    }

    private func createCollisionMarker(at position: SCNVector3, severity: CGFloat) -> SCNNode {
        let sphere = SCNSphere(radius: 0.5)

        // Color based on severity
        let color: NSColor
        if severity < 0.1 {
            color = .yellow
        } else if severity < 0.3 {
            color = .orange
        } else {
            color = .red
        }

        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.transparency = 0.6
        sphere.materials = [material]

        let node = SCNNode(geometry: sphere)
        node.position = position

        // Add pulsing animation
        let scaleUp = SCNAction.scale(to: 1.2, duration: 0.5)
        let scaleDown = SCNAction.scale(to: 1.0, duration: 0.5)
        let pulse = SCNAction.sequence([scaleUp, scaleDown])
        let repeatPulse = SCNAction.repeatForever(pulse)
        node.runAction(repeatPulse)

        return node
    }

    // MARK: - Settings Management

    /// Update articulator settings
    func updateSettings(_ settings: ArticulatorSettings) {
        articulator.settings = settings

        // If arches are mounted, re-mount with new settings
        if let upper = articulator.upperArchNode,
           let lower = articulator.lowerArchNode,
           let scene = scene {
            mountArches(upperArch: upper, lowerArch: lower, scene: scene)
        }
    }

    /// Get recommended settings based on patient data
    static func recommendedSettings(for patientAge: Int? = nil) -> ArticulatorSettings {
        var settings = ArticulatorSettings.default

        // Adjust settings based on age if provided
        if let age = patientAge {
            if age < 30 {
                // Younger patients typically have steeper condylar angles
                settings.condylarAngle = 35.0
            } else if age > 60 {
                // Older patients may have flatter angles
                settings.condylarAngle = 25.0
            }
        }

        return settings
    }

    // MARK: - Export

    /// Export occlusal analysis report
    func exportReport() -> String {
        guard let report = currentReport else {
            return "No analysis report available"
        }

        var output = "OCCLUSAL ANALYSIS REPORT\n"
        output += "========================\n\n"
        output += "Date: \(report.timestamp.formatted())\n"
        output += "Overall Score: \(String(format: "%.1f", report.overallScore))/100\n\n"

        output += "MOVEMENT ANALYSIS:\n"
        output += "==================\n\n"

        for movementReport in report.movementReports {
            output += "\(movementReport.type.rawValue):\n"
            output += "  Collision Count: \(movementReport.collisionCount)\n"
            output += "  Max Penetration: \(String(format: "%.2fmm", movementReport.maxPenetration))\n"

            if !movementReport.problematicPhases.isEmpty {
                output += "  Issues:\n"
                for phase in movementReport.problematicPhases {
                    output += "    - \(phase)\n"
                }
            }
            output += "\n"
        }

        output += "RECOMMENDATIONS:\n"
        output += "================\n"
        for recommendation in report.recommendations {
            output += "• \(recommendation)\n"
        }

        return output
    }
}

// MARK: - Articulator Settings View

struct ArticulatorSettingsView: View {
    @Binding var settings: ArticulatorSettings
    @Binding var isEnabled: Bool

    var body: some View {
        Form {
            Section("Articulator") {
                Toggle("Enable Virtual Articulator", isOn: $isEnabled)
            }

            Section("Condylar Settings") {
                VStack(alignment: .leading) {
                    Text("Condylar Angle: \(String(format: "%.1f°", settings.condylarAngle))")
                    Slider(value: $settings.condylarAngle, in: 0...60)
                }

                VStack(alignment: .leading) {
                    Text("Bennett Angle: \(String(format: "%.1f°", settings.bennettAngle))")
                    Slider(value: $settings.bennettAngle, in: 0...30)
                }

                VStack(alignment: .leading) {
                    Text("Bennett Shift: \(String(format: "%.2fmm", settings.bennettShift))")
                    Slider(value: $settings.bennettShift, in: 0...2)
                }
            }

            Section("Guidance") {
                VStack(alignment: .leading) {
                    Text("Protrusive Guidance: \(String(format: "%.1fmm", settings.protrusiveGuidance))")
                    Slider(value: $settings.protrusiveGuidance, in: 0...15)
                }

                VStack(alignment: .leading) {
                    Text("TMJ Distance: \(String(format: "%.1fmm", settings.tmjDistance))")
                    Slider(value: $settings.tmjDistance, in: 100...130)
                }
            }

            Section {
                Button("Reset to Default") {
                    settings = .default
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}

// MARK: - Occlusal Report View

struct OcclusalReportView: View {
    let report: OcclusalAnalysisReport
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Occlusal Analysis")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Export") {
                    exportReport()
                }
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            // Score
            VStack(spacing: 10) {
                Text("Overall Score")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                        .frame(width: 150, height: 150)

                    Circle()
                        .trim(from: 0, to: CGFloat(report.overallScore / 100))
                        .stroke(scoreColor(report.overallScore), lineWidth: 20)
                        .frame(width: 150, height: 150)
                        .rotationEffect(.degrees(-90))

                    Text(String(format: "%.0f", report.overallScore))
                        .font(.system(size: 48, weight: .bold))
                }
            }
            .padding()

            // Movement Reports
            List(report.movementReports, id: \.type.rawValue) { movementReport in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(movementReport.type.rawValue)
                            .font(.headline)
                        Spacer()
                        severityBadge(for: movementReport)
                    }

                    HStack {
                        Text("Collisions: \(movementReport.collisionCount)")
                        Spacer()
                        Text("Max Penetration: \(String(format: "%.2fmm", movementReport.maxPenetration))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !movementReport.problematicPhases.isEmpty {
                        ForEach(movementReport.problematicPhases, id: \.self) { phase in
                            Text("⚠️ \(phase)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Recommendations
            if !report.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recommendations")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(report.recommendations, id: \.self) { recommendation in
                        HStack(alignment: .top) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text(recommendation)
                                .font(.callout)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
                .background(Color.gray.opacity(0.1))
            }
        }
        .frame(width: 600, height: 700)
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 80 {
            return .green
        } else if score >= 60 {
            return .yellow
        } else {
            return .red
        }
    }

    private func severityBadge(for report: MovementReport) -> some View {
        let (text, color): (String, Color) = {
            if report.maxPenetration > 0.5 {
                return ("Severe", .red)
            } else if report.collisionCount > 5 {
                return ("Moderate", .orange)
            } else if report.collisionCount > 0 {
                return ("Mild", .yellow)
            } else {
                return ("OK", .green)
            }
        }()

        return Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    private func exportReport() {
        // Export report as text file
        let manager = ArticulatorIntegrationManager()
        let reportText = manager.exportReport()

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "occlusal_analysis_\(Date().timeIntervalSince1970).txt"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? reportText.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
