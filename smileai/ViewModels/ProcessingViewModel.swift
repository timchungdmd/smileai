import Foundation
import RealityKit
import Combine
import ModelIO
import SceneKit.ModelIO
import Vision
import CoreImage
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
class ProcessingViewModel: ObservableObject {
    
    enum State: Equatable {
        case idle
        case processing(progress: Double, timeElapsed: TimeInterval)
        case completed(url: URL)
        case failed(error: String)
        
        var isProcessing: Bool { if case .processing = self { return true }; return false }
        var hasModel: Bool { if case .completed = self { return true }; return false }
    }
    
    @Published var state: State = .idle
    @Published var consoleLog: String = "Ready. Drop HEIC/JPG Folder or Zip."
    
    @Published var selectedDetailLevel: PhotogrammetrySession.Request.Detail = .raw
    
    var currentModelURL: URL?
    private var startTime: Date?
    
    func resetAndCleanup() {
        if let url = currentModelURL {
            try? FileManager.default.removeItem(at: url)
            self.log("🗑️ Previous model deleted.")
        }
        self.currentModelURL = nil
        self.state = .idle
        self.consoleLog = "Ready for new scan."
    }
    
    func ingest(url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        Task {
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                var inputRoot = url
                
                // FIX: Use MainActor-isolated task with userInitiated priority
                if ["zip", "ar"].contains(url.pathExtension.lowercased()) {
                    self.log("📦 Decompressing Archive...")
                    
                    // Run decompression on a high-priority background queue
                    inputRoot = try await withCheckedThrowingContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            do {
                                let result = try ZipUtilities.unzip(fileURL: url)
                                continuation.resume(returning: result)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
                
                guard let dataFolder = ZipUtilities.findImageSource(in: inputRoot) else {
                    throw NSError(domain: "App", code: 404, userInfo: [NSLocalizedDescriptionKey: "No valid images found."])
                }
                
                self.log("✂️ AI Analysis: Cropping to Face...")
                let croppedFolder = try await performSmartCrop(in: dataFolder, margin: 0.5)
                
                let validExtensions = ["heic", "heif", "jpg", "jpeg", "png"]
                let files = try FileManager.default.contentsOfDirectory(at: croppedFolder, includingPropertiesForKeys: nil)
                let imageCount = files.filter { validExtensions.contains($0.pathExtension.lowercased()) }.count
                self.log("📸 Found \(imageCount) valid face images.")
                
                guard imageCount >= 10 else {
                    throw NSError(domain: "App", code: 400, userInfo: [NSLocalizedDescriptionKey: "Need at least 10 images with detected faces."])
                }
                
                await runPhotogrammetry(inputFolder: croppedFolder, imageCount: imageCount)
                try? FileManager.default.removeItem(at: croppedFolder)
                self.log("🧹 Cleaned up temporary files.")
                
            } catch {
                await MainActor.run {
                    self.state = .failed(error: error.localizedDescription)
                    self.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    nonisolated private func performSmartCrop(in inputURL: URL, margin: CGFloat) async throws -> URL {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("SmartCrop_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileURLs = try fileManager.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: nil)
        let imageExtensions = ["heic", "heif", "jpg", "jpeg", "png"]
        let context = CIContext(options: [.cacheIntermediates: false])
        
        for fileURL in fileURLs {
            if Task.isCancelled { break }
            guard imageExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            guard let ciImage = CIImage(contentsOf: fileURL) else { continue }
            
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            do {
                try handler.perform([request])
                guard let face = request.results?.sorted(by: {
                    $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height
                }).first else { continue }
                
                let w = CGFloat(ciImage.extent.width)
                let h = CGFloat(ciImage.extent.height)
                let bbox = face.boundingBox
                let rect = CGRect(x: bbox.origin.x * w, y: bbox.origin.y * h, width: bbox.width * w, height: bbox.height * h)
                let insetX = -(rect.width * margin) / 2
                let insetY = -(rect.height * margin) / 2
                let cropRect = rect.insetBy(dx: insetX, dy: insetY).intersection(ciImage.extent)
                let croppedImage = ciImage.cropped(to: cropRect)
                let destURL = tempDir.appendingPathComponent(fileURL.lastPathComponent)
                
                if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
                    try context.writeHEIFRepresentation(of: croppedImage, to: destURL, format: .RGBA8, colorSpace: colorSpace)
                }
            } catch {
                print("Skipping \(fileURL.lastPathComponent)")
            }
        }
        return tempDir
    }
    
    private func runPhotogrammetry(inputFolder: URL, imageCount: Int) async {
        await MainActor.run {
            self.startTime = Date()
            self.log("🚀 Starting Reconstruction...")
        }
        
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
                default:
                    break
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
        
        Task.detached(priority: .userInitiated) {
            do {
                let asset = MDLAsset(url: sourceURL)
                guard asset.count > 0 else {
                    throw NSError(domain: "Ex", code: 0, userInfo: nil)
                }
                
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
                await MainActor.run {
                    self.log("✅ Exported: \(destinationURL.lastPathComponent)")
                }
            } catch {
                await MainActor.run {
                    self.log("❌ Export Failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func log(_ msg: String) {
        print(msg)
        consoleLog = msg
    }
}
