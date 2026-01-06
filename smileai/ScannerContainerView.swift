import SwiftUI
import SceneKit
import UniformTypeIdentifiers
import RealityKit

struct ScannerContainerView: View {
    @StateObject private var viewModel = ProcessingViewModel()
    @EnvironmentObject var session: PatientSession
    @State private var isTargeted = false
    @State private var isExporting = false
    
    // ALERT STATE
    @State private var showOverwriteAlert = false
    @State private var pendingImportURL: URL?
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT PANEL
            VStack(spacing: 20) {
                // Header with Title and optional Delete Button
                HStack {
                    Text("Dental Studio")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    if viewModel.state.hasModel {
                        Button(action: {
                            // Trigger deletion confirmation without a new import pending
                            pendingImportURL = nil
                            showOverwriteAlert = true
                        }) {
                            Image(systemName: "trash.fill")
                                .foregroundStyle(.red)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .help("Delete Current Model")
                    }
                }
                .padding(.top)
                
                Divider()
                
                // Quality Selector
                VStack(alignment: .leading, spacing: 5) {
                    Text("Reconstruction Quality")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    Picker("Quality", selection: $viewModel.selectedDetailLevel) {
                        Text("Full (Textured)").tag(PhotogrammetrySession.Request.Detail.full)
                        Text("Raw (Max Density)").tag(PhotogrammetrySession.Request.Detail.raw)
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewModel.state.isProcessing)
                }
                .padding(.horizontal)
                
                // Status Card
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    
                    VStack {
                        switch viewModel.state {
                        case .idle:
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Drop Folder Here")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        case .processing(let progress, let time):
                            ProgressView(value: progress)
                                .padding(.horizontal)
                            Text("Processing: \(Int(progress * 100))%")
                            Text(String(format: "Time: %.0fs", time)).font(.caption)
                        case .completed:
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.green)
                            Text("Model Ready")
                                .font(.headline)
                            
                            // DOWNLOAD BUTTON
                            Button(action: {
                                isExporting = true
                            }) {
                                Label("Save Model", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                            
                        case .failed(let error):
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                            Text("Failed").font(.headline)
                            Text(error).font(.caption)
                        }
                    }
                }
                .frame(height: 220)
                .padding()
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isTargeted ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isTargeted ? 3 : 1).padding())
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                        guard let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        
                        DispatchQueue.main.async {
                            // CHECK IF MODEL EXISTS
                            if viewModel.state.hasModel || session.activeScanURL != nil {
                                // Stash the URL and ask for permission
                                self.pendingImportURL = url
                                self.showOverwriteAlert = true
                            } else {
                                // No model exists, proceed immediately
                                Task { @MainActor in viewModel.ingest(url: url) }
                            }
                        }
                    }
                    return true
                }
                
                Spacer()
                ScrollView { Text(viewModel.consoleLog).font(.caption2).padding() }
                    .frame(height: 100)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
            .frame(width: 320)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // RIGHT PANEL
            ZStack {
                Color.black
                if case .completed(let url) = viewModel.state {
                    SceneViewWrapper(modelURL: url).id(url)
                } else {
                    Text("3D Preview").foregroundStyle(.gray)
                }
            }
        }
        // SYNC LOGIC
        .onChange(of: viewModel.state) { _, newState in
            if case .completed(let url) = newState {
                print("✅ Syncing Model to Design Tab: \(url.path)")
                session.activeScanURL = url
            }
        }
        // EXPORTER
        .fileExporter(isPresented: $isExporting, document: STLFile(sourceURL: viewModel.currentModelURL), contentType: UTType(filenameExtension: "stl")!, defaultFilename: "DentalScan") { result in
            if case .success(let url) = result { viewModel.exportSTL(to: url) }
        }
        // DELETION ALERT
        .alert(pendingImportURL == nil ? "Delete Model?" : "Start New Reconstruction?", isPresented: $showOverwriteAlert) {
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.resetAndCleanup()
                session.activeScanURL = nil
                
                // If we had a pending import (drag & drop), start it now
                if let url = pendingImportURL {
                    viewModel.ingest(url: url)
                }
                pendingImportURL = nil
            }
        } message: {
            if pendingImportURL == nil {
                Text("Are you sure you want to delete this model? This action cannot be undone.")
            } else {
                Text("This will permanently delete the current model and any unsaved changes in the Smile Design tab.")
            }
        }
    }
}

// MARK: - Updated SceneView Wrapper (Invisible Box Logic)

struct SceneViewWrapper: NSViewRepresentable {
    let modelURL: URL
    
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        // OrbitArcball allows rotation around the object center naturally
        view.defaultCameraController.interactionMode = .orbitArcball
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.automaticTarget = false // We manually target the center
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = NSColor.darkGray
        return view
    }
    
    func updateNSView(_ uiView: SCNView, context: Context) {
        // Reload if the scene is new or empty
        if uiView.scene == nil || uiView.scene?.rootNode.name != modelURL.path {
            do {
                // 1. Load Source Scene
                let sourceScene = try SCNScene(url: modelURL, options: nil)
                
                // 2. Create Clean Destination Scene
                let cleanScene = SCNScene()
                cleanScene.rootNode.name = modelURL.path
                
                // 3. Find Geometry
                if let geoNode = findFirstGeometryNode(in: sourceScene.rootNode) {
                    
                    // Clone to detach
                    let node = geoNode.clone()
                    node.name = "PREVIEW_MODEL"
                    
                    // --- CENTERING LOGIC (The "Invisible Box") ---
                    // Calculate the geometric center of the bounding box
                    if let geo = node.geometry {
                        let (min, max) = geo.boundingBox
                        let cx = (min.x + max.x) / 2
                        let cy = (min.y + max.y) / 2
                        let cz = (min.z + max.z) / 2
                        
                        // Set the pivot point to this center
                        node.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)
                    }
                    
                    // Place the node at World Origin (0,0,0)
                    node.position = SCNVector3Zero
                    
                    // Ensure materials are visible and not glossy (Matte)
                    node.geometry?.materials.forEach { mat in
                        mat.lightingModel = .lambert
                        mat.isDoubleSided = true
                    }
                    
                    cleanScene.rootNode.addChildNode(node)
                    uiView.scene = cleanScene
                    
                    // 4. Force Camera Target to Origin
                    // Since the model is centered at 0,0,0, the camera will rotate perfectly around it.
                    uiView.defaultCameraController.target = SCNVector3Zero
                    
                } else {
                    // Fallback for empty scenes
                    uiView.scene = sourceScene
                }
                
            } catch {
                print("Failed to load scene: \(error)")
            }
        }
    }
    
    private func findFirstGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = findFirstGeometryNode(in: child) { return found }
        }
        return nil
    }
}
