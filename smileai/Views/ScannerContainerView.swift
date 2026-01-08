import SwiftUI
import SceneKit
import UniformTypeIdentifiers
import RealityKit

struct ScannerContainerView: View {
    @StateObject private var viewModel = ProcessingViewModel()
    @EnvironmentObject var session: PatientSession
    @State private var isTargeted = false
    @State private var isExporting = false
    @State private var showOverwriteAlert = false
    @State private var pendingImportURL: URL?
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 20) {
                headerView
                Divider()
                qualitySelector
                statusCard
                Spacer()
                consoleView
            }
            .frame(width: 320)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            ZStack {
                Color.black
                if case .completed(let url) = viewModel.state {
                    SceneViewWrapper(modelURL: url).id(url)
                } else {
                    Text("3D Preview").foregroundStyle(.gray)
                }
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            if case .completed(let url) = newState {
                print("✅ Syncing Model to Design Tab: \(url.path)")
                session.activeScanURL = url
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: STLExportFile(sourceURL: viewModel.currentModelURL),
            contentType: UTType.stl,
            defaultFilename: "DentalScan"
        ) { result in
            if case .success(let url) = result {
                viewModel.exportSTL(to: url)
            }
        }
        .alert(
            pendingImportURL == nil ? "Delete Model?" : "Start New Reconstruction?",
            isPresented: $showOverwriteAlert
        ) {
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.resetAndCleanup()
                session.activeScanURL = nil
                
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
    
    private var headerView: some View {
        HStack {
            Text("Dental Studio")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Spacer()
            
            if viewModel.state.hasModel {
                Button(action: {
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
    }
    
    private var qualitySelector: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Reconstruction Quality")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("High Precision")
                    .font(.body)
                    .fontWeight(.medium)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
        }
        .padding(.horizontal)
    }
    
    private var statusCard: some View {
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
                    Text(String(format: "Time: %.0fs", time))
                        .font(.caption)
                    
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.green)
                    Text("Model Ready")
                        .font(.headline)
                    
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
                    Text("Failed")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                }
            }
        }
        .frame(height: 220)
        .padding()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isTargeted ? Color.accentColor : Color.gray.opacity(0.3),
                    lineWidth: isTargeted ? 3 : 1
                )
                .padding()
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }
    
    private var consoleView: some View {
        ScrollView {
            Text(viewModel.consoleLog)
                .font(.caption2)
                .padding()
        }
        .frame(height: 100)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            DispatchQueue.main.async {
                if viewModel.state.hasModel || session.activeScanURL != nil {
                    self.pendingImportURL = url
                    self.showOverwriteAlert = true
                } else {
                    Task { @MainActor in viewModel.ingest(url: url) }
                }
            }
        }
    }
}

struct SceneViewWrapper: NSViewRepresentable {
    let modelURL: URL
    
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.defaultCameraController.interactionMode = .orbitArcball
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.automaticTarget = false
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = NSColor.darkGray
        return view
    }
    
    func updateNSView(_ uiView: SCNView, context: Context) {
        if uiView.scene == nil || uiView.scene?.rootNode.name != modelURL.path {
            do {
                let sourceScene = try SCNScene(url: modelURL, options: nil)
                let cleanScene = SCNScene()
                cleanScene.rootNode.name = modelURL.path
                
                if let geoNode = findFirstGeometryNode(in: sourceScene.rootNode) {
                    let node = geoNode.clone()
                    node.name = "PREVIEW_MODEL"
                    
                    if let geo = node.geometry {
                        let (min, max) = geo.boundingBox
                        let cx = (min.x + max.x) / 2
                        let cy = (min.y + max.y) / 2
                        let cz = (min.z + max.z) / 2
                        
                        node.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)
                    }
                    
                    node.position = SCNVector3Zero
                    
                    node.geometry?.materials.forEach { mat in
                        mat.lightingModel = .lambert
                        mat.isDoubleSided = true
                    }
                    
                    cleanScene.rootNode.addChildNode(node)
                    uiView.scene = cleanScene
                    
                    uiView.defaultCameraController.target = SCNVector3Zero
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
