import Foundation
import RealityKit
import Combine
import ModelIO
import SceneKit.ModelIO

@MainActor
class ProcessingViewModel: ObservableObject {
    
    enum State: Equatable {
        case idle
        case processing(progress: Double, timeElapsed: TimeInterval)
        case completed(url: URL)
        case failed(error: String)
        
        var isProcessing: Bool {
            if case .processing = self { return true }
            return false
        }
        
        // Helper to check if we have an active model
        var hasModel: Bool {
            if case .completed = self { return true }
            return false
        }
        
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.processing, .processing): return true
            case (.completed(let a), .completed(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }
    
    @Published var state: State = .idle
    @Published var consoleLog: String = "Ready. Drop HEIC/JPG Folder or Zip."
    @Published var selectedDetailLevel: PhotogrammetrySession.Request.Detail = .full
    
    var currentModelURL: URL?
    private var startTime: Date?
    
    // MARK: - Cleanup Logic
    
    /// Deletes the current model file and resets state
    func resetAndCleanup() {
        if let url = currentModelURL {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    self.log("🗑️ Previous model deleted.")
                }
            } catch {
                self.log("⚠️ Failed to delete old model: \(error.localizedDescription)")
            }
        }
        
        // Reset State
        self.currentModelURL = nil
        self.state = .idle
        self.consoleLog = "Ready for new scan."
    }
    
    // MARK: - Ingestion & Processing
    
    func ingest(url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        
        Task {
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            
            do {
                var inputRoot = url
                
                // 1. Unzip if needed
                if ["zip", "ar"].contains(url.pathExtension.lowercased()) {
                    self.log("📦 Decompressing Archive...")
                    inputRoot = try ZipUtilities.unzip(fileURL: url)
                }
                
                // 2. Find Images
                guard let dataFolder = ZipUtilities.findImageSource(in: inputRoot) else {
                    throw NSError(domain: "App", code: 404, userInfo: [NSLocalizedDescriptionKey: "No valid images found."])
                }
                
                // 3. Count
                let validExtensions = ["heic", "heif", "jpg", "jpeg", "png"]
                let files = try? FileManager.default.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil)
                let imageCount = files?.filter { validExtensions.contains($0.pathExtension.lowercased()) }.count ?? 0
                
                self.log("📸 Found \(imageCount) images.")
                
                guard imageCount >= 10 else {
                    throw NSError(domain: "App", code: 400, userInfo: [NSLocalizedDescriptionKey: "Need at least 10 images."])
                }
                
                // 4. Run Photogrammetry
                await runPhotogrammetry(inputFolder: dataFolder, imageCount: imageCount)
                
            } catch {
                self.state = .failed(error: error.localizedDescription)
                self.log("Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func runPhotogrammetry(inputFolder: URL, imageCount: Int) async {
        self.startTime = Date()
        self.log("🚀 Starting Reconstruction...")
        
        let tempDir = FileManager.default.temporaryDirectory
        let uniqueID = UUID().uuidString
        let filename = "DentalScan_\(uniqueID).usdz"
        let outputURL = tempDir.appendingPathComponent(filename)
        
        do {
            guard PhotogrammetrySession.isSupported else {
                throw NSError(domain: "App", code: 500, userInfo: [NSLocalizedDescriptionKey: "Hardware not supported."])
            }
            
            var config = PhotogrammetrySession.Configuration()
            config.featureSensitivity = .high
            config.sampleOrdering = .unordered
            
            // Enable Apple's built-in masking
            config.isObjectMaskingEnabled = true
            
            let session = try PhotogrammetrySession(input: inputFolder, configuration: config)
            let request = PhotogrammetrySession.Request.modelFile(url: outputURL, detail: selectedDetailLevel)
            
            try session.process(requests: [request])
            
            for try await output in session.outputs {
                switch output {
                case .requestProgress(_, let fraction):
                    await MainActor.run {
                        let elapsed = Date().timeIntervalSince(self.startTime ?? Date())
                        self.state = .processing(progress: fraction, timeElapsed: elapsed)
                        
                        if Int(fraction * 100) % 10 == 0 {
                            self.consoleLog = "Reconstructing: \(Int(fraction * 100))% | Time: \(Int(elapsed))s"
                        }
                    }
                    
                case .requestComplete(_, _):
                    await MainActor.run {
                        let elapsed = Date().timeIntervalSince(self.startTime ?? Date())
                        self.log("✨ Success in \(Int(elapsed))s!")
                        self.currentModelURL = outputURL
                        self.state = .completed(url: outputURL)
                    }
                    
                case .requestError(_, let error):
                    self.log("⚠️ Warning: \(error.localizedDescription)")
                    
                default: break
                }
            }
        } catch {
            await MainActor.run {
                self.state = .failed(error: error.localizedDescription)
                self.log("❌ Failed: \(error.localizedDescription)")
            }
        }
    }
    
    func exportSTL(to destinationURL: URL) {
        guard let sourceURL = currentModelURL else { return }
        self.log("⚙️ Converting to STL...")
        
        Task.detached {
            do {
                let asset = MDLAsset(url: sourceURL)
                guard asset.count > 0 else { throw NSError(domain: "Ex", code: 0, userInfo: nil) }
                
                let scaleFactor: Float = 1000.0
                let scaleMatrix = matrix_float4x4(diagonal: SIMD4<Float>(scaleFactor, scaleFactor, scaleFactor, 1))
                
                for index in 0..<asset.count {
                    let object = asset.object(at: index)
                    if let transform = object.transform {
                        transform.matrix = scaleMatrix
                    } else {
                        let component = MDLTransform(matrix: scaleMatrix)
                        object.transform = component
                    }
                }
                
                try asset.export(to: destinationURL)
                await MainActor.run { self.log("✅ Exported: \(destinationURL.lastPathComponent)") }
            } catch {
                await MainActor.run { self.log("❌ Export Failed: \(error.localizedDescription)") }
            }
        }
    }
    
    private func log(_ msg: String) {
        print(msg)
        consoleLog = msg
    }
}
