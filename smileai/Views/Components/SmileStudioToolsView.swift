//
//  SmileStudioToolsView.swift
//  smileai
//
//  Integrated UI controls for all new exocad-competing features
//

import SwiftUI
import AppKit

/// Comprehensive tools panel for smile design features
struct SmileStudioToolsView: View {

    // MARK: - Bindings
    @Binding var facePhoto: NSImage?
    @Binding var selectedToothPreset: ToothMorphologyPreset?
    @Binding var waxUpPhase: WaxUpPhase
    @Binding var showArticulator: Bool

    // MARK: - State
    @State private var showEnhancedAnalysis = false
    @State private var enhancedAnalysis: EnhancedFacialAnalysis?
    @State private var showSimulation = false
    @State private var simulatedImage: NSImage?
    @State private var selectedShade: ToothShadeData?
    @State private var isProcessing = false
    @State private var showToothLibrary = false
    @State private var showWaxUpPanel = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - AI Analysis Section
                sectionHeader(title: "AI-Powered Analysis", icon: "brain.head.profile")

                if let photo = facePhoto {
                    Button(action: {
                        Task {
                            await performEnhancedAnalysis(photo)
                        }
                    }) {
                        Label("Detect Smile Line & Proportions", systemImage: "face.smiling.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)

                    if let analysis = enhancedAnalysis {
                        analysisResultsView(analysis)
                    }
                }

                Divider()

                // MARK: - Smile Simulation Section
                sectionHeader(title: "TruSmile Simulation", icon: "photo.on.rectangle.angled")

                if facePhoto != nil {
                    Button(action: {
                        showSimulation = true
                    }) {
                        Label("Generate Realistic Simulation", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)

                    if let simulated = simulatedImage {
                        VStack(alignment: .leading) {
                            Text("Simulation Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Image(nsImage: simulated)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 150)
                                .cornerRadius(8)

                            Button(action: {
                                Task {
                                    await generateComparisonVideo()
                                }
                            }) {
                                Label("Create Before/After Video", systemImage: "video.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Divider()

                // MARK: - Tooth Library Section
                sectionHeader(title: "Enhanced Tooth Library", icon: "square.stack.3d.up.fill")

                Button(action: {
                    showToothLibrary = true
                }) {
                    Label("Browse Tooth Presets", systemImage: "square.grid.3x3.fill")
                }
                .buttonStyle(.bordered)

                if let preset = selectedToothPreset {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Selected: \(preset.name)")
                                .font(.headline)
                            Spacer()
                            Circle()
                                .fill(categoryColor(for: preset.category))
                                .frame(width: 12, height: 12)
                        }

                        Text(preset.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Category: \(preset.category.rawValue)")
                            Spacer()
                            Text("\(preset.ageGroup.rawValue)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }

                Divider()

                // MARK: - Virtual Articulator Section
                sectionHeader(title: "Virtual Articulator", icon: "gearshape.2.fill")

                Toggle(isOn: $showArticulator) {
                    Label("Enable Articulator Simulation", systemImage: "arrow.triangle.2.circlepath")
                }

                if showArticulator {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Simulate Protrusion") {
                            simulateMovement(.protrusion)
                        }
                        .buttonStyle(.borderless)

                        Button("Simulate Lateral Movement") {
                            simulateMovement(.lateralRight)
                        }
                        .buttonStyle(.borderless)

                        Button("Analyze Full Occlusion") {
                            analyzeOcclusion()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.leading)
                }

                Divider()

                // MARK: - Wax-Up Workflow Section
                sectionHeader(title: "Virtual Wax-Up", icon: "hammer.fill")

                Button(action: {
                    showWaxUpPanel = true
                }) {
                    Label("Open Wax-Up Workflow", systemImage: "flowchart.fill")
                }
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Current Phase")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        ForEach(WaxUpPhase.allCases, id: \.self) { phase in
                            Circle()
                                .fill(waxUpPhase == phase ? Color.blue : Color.gray)
                                .frame(width: 8, height: 8)
                        }
                    }

                    Text(waxUpPhase.rawValue)
                        .font(.headline)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)

                Divider()

                // MARK: - Shade Selection Section
                sectionHeader(title: "Tooth Shade", icon: "paintpalette.fill")

                Menu {
                    ForEach(ToothShadeLibrary.shadeGuides, id: \.name) { guide in
                        Menu(guide.name) {
                            ForEach(guide.shades) { shade in
                                Button(shade.code) {
                                    selectedShade = shade
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        if let shade = selectedShade {
                            Circle()
                                .fill(Color(nsColor: shade.color))
                                .frame(width: 20, height: 20)

                            Text(shade.code)
                        } else {
                            Text("Select Shade")
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .sheet(isPresented: $showToothLibrary) {
            ToothLibraryBrowserView(selectedPreset: $selectedToothPreset)
        }
        .sheet(isPresented: $showWaxUpPanel) {
            WaxUpWorkflowView(currentPhase: $waxUpPhase)
        }
        .sheet(isPresented: $showSimulation) {
            SmileSimulationView(
                originalPhoto: facePhoto!,
                simulatedImage: $simulatedImage,
                selectedShade: $selectedShade
            )
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundColor(.primary)
    }

    private func analysisResultsView(_ analysis: EnhancedFacialAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let smileLine = analysis.smileLine {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Smile Line: \(smileLine.type.rawValue)")
                    Spacer()
                    Text(String(format: "%.0f%%", smileLine.confidence * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(analysis.predictedToothPositions.count) tooth positions predicted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let proportions = analysis.facialProportions {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Facial Proportions")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("IPD: \(String(format: "%.1f", proportions.ipd))px")
                        Spacer()
                        Image(systemName: proportions.isIdeal ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                    }
                    .font(.caption2)

                    HStack {
                        Text("Smile Width Ratio:")
                        Spacer()
                        Text(String(format: "%.2f", proportions.smileWidthRatio))
                    }
                    .font(.caption2)
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }

            if let asymmetry = analysis.smileAsymmetry {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(asymmetryColor(for: asymmetry.severity))
                    Text("Asymmetry: \(asymmetry.severity.rawValue)")
                        .font(.caption)
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private func categoryColor(for category: PresetCategory) -> Color {
        switch category {
        case .natural: return .green
        case .masculine: return .blue
        case .feminine: return .pink
        case .youthful: return .orange
        case .mature: return .brown
        case .aesthetic: return .purple
        case .ethnic: return .cyan
        case .custom: return .gray
        }
    }

    private func asymmetryColor(for severity: AsymmetrySeverity) -> Color {
        switch severity {
        case .minimal: return .green
        case .mild: return .yellow
        case .moderate: return .orange
        case .severe: return .red
        }
    }

    // MARK: - Actions

    private func performEnhancedAnalysis(_ photo: NSImage) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            enhancedAnalysis = try await FaceDetectionService.performEnhancedAnalysis(in: photo)
        } catch {
            print("Analysis error: \(error)")
        }
    }

    private func generateComparisonVideo() async {
        guard let original = facePhoto,
              let simulated = simulatedImage else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("smile_comparison_\(UUID().uuidString).mov")

        do {
            try await AISmileSimulationService.generateComparisonVideo(
                originalPhoto: original,
                simulatedPhoto: simulated,
                duration: 5.0,
                outputURL: tempURL
            )

            // Open video in default player
            NSWorkspace.shared.open(tempURL)
        } catch {
            print("Video generation error: \(error)")
        }
    }

    private func simulateMovement(_ type: MovementType) {
        // This would interact with the VirtualArticulator in the 3D scene
        print("Simulating movement: \(type.rawValue)")
        NotificationCenter.default.post(
            name: NSNotification.Name("SimulateArticulatorMovement"),
            object: type
        )
    }

    private func analyzeOcclusion() {
        print("Analyzing full occlusion")
        NotificationCenter.default.post(
            name: NSNotification.Name("AnalyzeOcclusion"),
            object: nil
        )
    }
}

// MARK: - Supporting Views

struct ToothLibraryBrowserView: View {
    @Binding var selectedPreset: ToothMorphologyPreset?
    @Environment(\.dismiss) var dismiss

    @State private var selectedCategory: PresetCategory = .natural

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tooth Library")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            // Category Picker
            Picker("Category", selection: $selectedCategory) {
                ForEach(PresetCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Preset List
            List(EnhancedToothLibrary.presets(for: selectedCategory)) { preset in
                Button(action: {
                    selectedPreset = preset
                    dismiss()
                }) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(preset.name)
                                .font(.headline)
                            Spacer()
                            if selectedPreset?.id == preset.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }

                        Text(preset.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("\(preset.ageGroup.rawValue)")
                            Text("•")
                            Text("\(preset.gender.rawValue)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 500, height: 600)
    }
}

struct WaxUpWorkflowView: View {
    @Binding var currentPhase: WaxUpPhase
    @Environment(\.dismiss) var dismiss

    @StateObject private var waxUpManager = VirtualWaxUpManager()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Wax-Up Workflow")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            // Phase Indicator
            HStack(spacing: 15) {
                ForEach(Array(WaxUpPhase.allCases.enumerated()), id: \.element) { index, phase in
                    VStack {
                        ZStack {
                            Circle()
                                .fill(waxUpManager.currentPhase == phase ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 40, height: 40)

                            if WaxUpPhase.allCases.firstIndex(of: waxUpManager.currentPhase)! >= index {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.white)
                            } else {
                                Text("\(index + 1)")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text(phase.rawValue)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    if index < WaxUpPhase.allCases.count - 1 {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
            .padding()

            // Phase Content
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Phase: \(waxUpManager.currentPhase.rawValue)")
                        .font(.headline)

                    Text(phaseDescription(for: waxUpManager.currentPhase))
                        .font(.body)
                        .foregroundStyle(.secondary)

                    // Phase-specific controls would go here

                    Divider()

                    HStack {
                        Button("Previous") {
                            waxUpManager.returnToPreviousPhase()
                        }
                        .disabled(waxUpManager.currentPhase == .diagnostic)

                        Spacer()

                        Button("Next Phase") {
                            waxUpManager.advanceToNextPhase()
                            currentPhase = waxUpManager.currentPhase
                        }
                        .disabled(waxUpManager.currentPhase == .export)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }

    private func phaseDescription(for phase: WaxUpPhase) -> String {
        switch phase {
        case .diagnostic:
            return "Import and analyze diagnostic scans. The system will automatically detect arch form, missing teeth, and available space."
        case .blockOut:
            return "Create block-out for undercuts to ensure proper insertion path for prosthetics."
        case .initialWaxUp:
            return "Generate initial wax-up from selected tooth morphology presets. Teeth will be automatically positioned based on arch analysis."
        case .refinement:
            return "Refine the design using morphology adjustments, free-form sculpting, or material additions."
        case .finalization:
            return "Validate the final design for occlusion, spacing, emergence profile, and margins. Review all warnings and errors."
        case .export:
            return "Export production files including STL, 3D print files, milling instructions, and technical sheets."
        }
    }
}

struct SmileSimulationView: View {
    let originalPhoto: NSImage
    @Binding var simulatedImage: NSImage?
    @Binding var selectedShade: ToothShadeData?
    @Environment(\.dismiss) var dismiss

    @State private var isProcessing = false
    @State private var settings = SimulationSettings.default

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Smile Simulation")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            // Settings
            Form {
                Section("Appearance") {
                    Slider(value: $settings.translucency, in: 0...1) {
                        Text("Translucency")
                    }

                    Slider(value: $settings.brightness, in: -0.5...0.5) {
                        Text("Brightness")
                    }

                    Slider(value: $settings.contrast, in: 0.5...1.5) {
                        Text("Contrast")
                    }

                    Toggle("Add Surface Texture", isOn: $settings.addSurfaceTexture)
                    Toggle("Add Highlights", isOn: $settings.addHighlights)
                }
            }
            .formStyle(.grouped)

            // Generate Button
            Button(action: {
                Task {
                    await generateSimulation()
                }
            }) {
                Label(
                    isProcessing ? "Processing..." : "Generate Simulation",
                    systemImage: "wand.and.stars"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing || selectedShade == nil)

            if selectedShade == nil {
                Text("Please select a tooth shade first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 400, height: 500)
    }

    private func generateSimulation() async {
        isProcessing = true
        defer { isProcessing = false }

        // In production, this would use actual tooth design data
        let mockToothDesign: [ToothDesignData] = []

        do {
            // This would need landmarks from the photo
            let landmarks = try await FaceDetectionService.detectLandmarks(in: originalPhoto)

            if let landmarks = landmarks {
                let result = try await AISmileSimulationService.generateSmileSimulation(
                    originalPhoto: originalPhoto,
                    toothDesign: mockToothDesign,
                    landmarks: landmarks,
                    settings: settings
                )

                simulatedImage = result.simulatedImage
                dismiss()
            }
        } catch {
            print("Simulation error: \(error)")
        }
    }
}
