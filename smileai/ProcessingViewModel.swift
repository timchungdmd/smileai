import Foundation
import RealityKit
import Combine
import ModelIO
import SceneKit.ModelIO

@MainActor
class ProcessingViewModel: ObservableObject {
    
    enum State {
        case idle
        case processing(progress: Double, timeElapsed: TimeInterval)
        case completed(url: URL)
        case failed(error: String)
    }
    
    @Published var state: State = .idle
    @Published var consoleLog: String = "Ready. Drop HEIC/JPG Folder or Zip."
    
    // Configurable Detail Level
    // .full = High detail + Texture Maps (Default)
    // .raw  = Max Geometry + Vertex Colors (No texture maps)
    @Published var selectedDetailLevel: PhotogrammetrySession.Request.Detail = .full
    
    // Store the last generated model URL
    var currentModelURL: URL?
    
    private var startTime: Date?
    
    // MARK: - Ingestion & Processing
    
    func ingest(url: URL) {
        // 1. Security Scope: Essential for Sandboxed Mac Apps to read user folders
        let access = url.startAccessingSecurityScopedResource()
        
        Task {
            // We defer stopping access until the task finishes,
            // but for Photogrammetry, we might need to keep it open or copy files.
            // Copying to Temp is safest for Sandboxed processing.
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }
            
            do {
                self.log("📂 Analyzing Input: \(url.lastPathComponent)")
                
                var inputRoot = url
                
                // A. Handle Zip (Decompress to Temp)
                if ["zip", "ar"].contains(url.pathExtension.lowercased()) {
                    self.log("📦 Decompressing Archive...")
                    inputRoot = try ZipUtilities.unzip(fileURL: url)
                }
                
                // B. Validate Data
                guard let dataFolder = ZipUtilities.findImageSource(in: inputRoot) else {
                    throw NSError(domain: "App", code: 404, userInfo: [NSLocalizedDescriptionKey: "No valid images found in folder."])
                }
                
                // C. Count Images
                let validExtensions = ["heic", "heif", "jpg", "jpeg", "png"]
                let files = try? FileManager.default.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil)
                let imageCount = files?.filter { validExtensions.contains($0.pathExtension.lowercased()) }.count ?? 0
                
                self.log("📸 Found \(imageCount) images. Mode: \(selectedDetailLevel == .raw ? "RAW (Max Density)" : "FULL (Textured)")")
                
                guard imageCount >= 10 else {
                    throw NSError(domain: "App", code: 400, userInfo: [NSLocalizedDescriptionKey: "Need at least 10 images."])
                }
                
                // D. Run Engine
                await runPhotogrammetry(inputFolder: dataFolder, imageCount: imageCount)
                
            } catch {
                self.state = .failed(error: error.localizedDescription)
                self.log("Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func runPhotogrammetry(inputFolder: URL, imageCount: Int) async {
        self.startTime = Date()
        self.log("🚀 Starting Engine...")
        
        // Output to Temp
        let tempDir = FileManager.default.temporaryDirectory
        let uniqueID = UUID().uuidString
        let filename = "DentalScan_\(selectedDetailLevel == .raw ? "Raw" : "Full")_\(uniqueID).usdz"
        let outputURL = tempDir.appendingPathComponent(filename)
        
        do {
            guard PhotogrammetrySession.isSupported else {
                throw NSError(domain: "App", code: 500, userInfo: [NSLocalizedDescriptionKey: "Hardware not supported."])
            }
            
            // Configuration for MAX QUALITY
            var config = PhotogrammetrySession.Configuration()
            config.featureSensitivity = .high // Critical for capturing fine details
            config.sampleOrdering = .unordered
            config.isObjectMaskingEnabled = false // Disable masking to ensure we get everything
            
            let session = try PhotogrammetrySession(input: inputFolder, configuration: config)
            
            // Use the selected detail level (Full or Raw)
            let request = PhotogrammetrySession.Request.modelFile(url: outputURL, detail: selectedDetailLevel)
            
            try session.process(requests: [request])
            
            for try await output in session.outputs {
                switch output {
                case .requestProgress(_, let fraction):
                    await MainActor.run {
                        let elapsed = Date().timeIntervalSince(self.startTime ?? Date())
                        // Smooth progress bar (0.0 -> 1.0)
                        self.state = .processing(progress: fraction, timeElapsed: elapsed)
                        
                        // Log every 10%
                        if Int(fraction * 100) % 10 == 0 {
                            self.consoleLog = "Processing: \(Int(fraction * 100))% | Time: \(Int(elapsed))s"
                        }
                    }
                    
                case .requestComplete(_, _):
                    await MainActor.run {
                        let elapsed = Date().timeIntervalSince(self.startTime ?? Date())
                        self.log("✨ Success in \(Int(elapsed))s! Model Ready.")
                        self.currentModelURL = outputURL
                        self.state = .completed(url: outputURL)
                    }
                    
                case .requestError(_, let error):
                    self.log("⚠️ Engine Warning: \(error.localizedDescription)")
                    // We don't throw here immediately, as some warnings are non-fatal
                    
                default: break
                }
            }
        } catch {
            await MainActor.run {
                self.state = .failed(error: error.localizedDescription)
                self.log("❌ Engine Failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Export Logic (STL)
    
    func exportSTL(to destinationURL: URL) {
        guard let sourceURL = currentModelURL else { return }
        self.log("⚙️ Converting to STL (Scale: mm)...")
        
        Task.detached {
            do {
                let asset = MDLAsset(url: sourceURL)
                guard asset.count > 0 else { throw NSError(domain: "Ex", code: 0, userInfo: nil) }
                
                // Scale Meters -> Millimeters
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
