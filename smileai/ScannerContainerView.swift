import SwiftUI
import SceneKit
import UniformTypeIdentifiers
import RealityKit

struct ScannerContainerView: View {
    @StateObject private var viewModel = ProcessingViewModel()
    @EnvironmentObject var session: PatientSession // <--- CONNECTS TO DESIGN TAB
    @State private var isTargeted = false
    @State private var isExporting = false
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT PANEL
            VStack(spacing: 20) {
                Text("Dental Studio")
                    .font(.largeTitle)
                    .fontWeight(.bold)
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
                        Task { @MainActor in viewModel.ingest(url: url) }
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
        // --- CRITICAL SYNC LOGIC ---
        .onChange(of: viewModel.state) { newState in
            if case .completed(let url) = newState {
                print("✅ Syncing Model to Design Tab: \(url.path)")
                session.activeScanURL = url
            }
        }
    }
}
