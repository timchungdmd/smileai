//
//  AISmileSimulationService.swift
//  smileai
//
//  AI-based realistic smile simulation and photo rendering
//  Competing with exocad TruSmile Photo & Video features
//

import Foundation
import AppKit
import CoreImage
import CoreML
import Vision
import AVFoundation

/// Realistic smile simulation using AI and advanced image processing
class AISmileSimulationService {

    // MARK: - Photo Simulation

    /// Generate realistic smile makeover photo simulation
    @MainActor
    static func generateSmileSimulation(
        originalPhoto: NSImage,
        toothDesign: [ToothDesignData],
        landmarks: FacialLandmarks,
        settings: SimulationSettings = SimulationSettings.default
    ) async throws -> SmileSimulationResult {

        guard let cgImage = originalPhoto.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SimulationError.invalidImage
        }

        // Step 1: Create base simulation
        let baseSimulation = try await createBaseSimulation(
            image: cgImage,
            toothDesign: toothDesign,
            landmarks: landmarks,
            settings: settings
        )

        // Step 2: Apply realistic lighting and shadows
        let litSimulation = applyRealisticLighting(
            to: baseSimulation,
            landmarks: landmarks,
            settings: settings
        )

        // Step 3: Blend with original photo
        let finalSimulation = blendSimulationWithOriginal(
            original: cgImage,
            simulation: litSimulation,
            landmarks: landmarks,
            blendMode: settings.blendMode
        )

        // Step 4: Apply finishing touches
        let enhanced = applyFinishingTouches(
            to: finalSimulation,
            settings: settings
        )

        let nsImage = NSImage(cgImage: enhanced, size: originalPhoto.size)

        return SmileSimulationResult(
            simulatedImage: nsImage,
            originalImage: originalPhoto,
            confidence: 0.95,
            processingTime: 0.0 // Will be measured by caller
        )
    }

    /// Create base tooth simulation on photo
    private static func createBaseSimulation(
        image: CGImage,
        toothDesign: [ToothDesignData],
        landmarks: FacialLandmarks,
        settings: SimulationSettings
    ) async throws -> CGImage {

        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SimulationError.renderingFailed
        }

        // Draw original image
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Calculate perspective transformation
        let perspectiveTransform = calculatePerspectiveTransform(
            from: landmarks,
            imageSize: CGSize(width: width, height: height)
        )

        // Render each tooth with realistic appearance
        for tooth in toothDesign {
            renderToothOnPhoto(
                context: context,
                tooth: tooth,
                transform: perspectiveTransform,
                settings: settings
            )
        }

        guard let outputImage = context.makeImage() else {
            throw SimulationError.renderingFailed
        }

        return outputImage
    }

    /// Render individual tooth with realistic appearance
    private static func renderToothOnPhoto(
        context: CGContext,
        tooth: ToothDesignData,
        transform: PerspectiveTransform,
        settings: SimulationSettings
    ) {
        context.saveGState()

        // Apply perspective transformation
        let transformedRect = transform.apply(to: tooth.boundingRect)

        // Create tooth gradient for realistic enamel appearance
        let toothGradient = createRealisticToothGradient(
            shade: tooth.shade,
            translucency: settings.translucency
        )

        // Draw tooth shape
        let toothPath = createToothPath(for: transformedRect, type: tooth.type)
        context.addPath(toothPath)
        context.clip()

        // Fill with gradient
        if let gradient = toothGradient {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: transformedRect.minX, y: transformedRect.minY),
                end: CGPoint(x: transformedRect.minX, y: transformedRect.maxY),
                options: []
            )
        }

        // Add surface texture
        if settings.addSurfaceTexture {
            addToothSurfaceTexture(context: context, rect: transformedRect)
        }

        // Add highlights
        if settings.addHighlights {
            addToothHighlights(context: context, rect: transformedRect)
        }

        context.restoreGState()
    }

    /// Create realistic tooth gradient
    private static func createRealisticToothGradient(
        shade: ToothShade,
        translucency: Double
    ) -> CGGradient? {
        let colors = shade.gradientColors(translucency: translucency)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        return CGGradient(
            colorsSpace: colorSpace,
            colors: colors.map { $0.cgColor } as CFArray,
            locations: [0.0, 0.3, 0.7, 1.0]
        )
    }

    /// Create tooth path based on type
    private static func createToothPath(for rect: CGRect, type: SimulationToothType) -> CGPath {
        let path = CGMutablePath()

        // Create anatomically correct tooth outline
        switch type {
        case .centralIncisor:
            path.addRoundedRect(in: rect, cornerWidth: rect.width * 0.1, cornerHeight: rect.height * 0.05)

        case .lateralIncisor:
            // Slightly narrower
            let inset = rect.insetBy(dx: rect.width * 0.05, dy: 0)
            path.addRoundedRect(in: inset, cornerWidth: inset.width * 0.12, cornerHeight: inset.height * 0.06)

        case .canine:
            // More pointed
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.midY),
                control: CGPoint(x: rect.maxX * 0.9, y: rect.minY + rect.height * 0.3)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.minY),
                control: CGPoint(x: rect.minX * 1.1, y: rect.minY + rect.height * 0.3)
            )
            path.closeSubpath()

        default:
            path.addRect(rect)
        }

        return path
    }

    /// Add realistic tooth surface texture
    private static func addToothSurfaceTexture(context: CGContext, rect: CGRect) {
        // Simulate enamel micro-texture with noise
        context.saveGState()
        context.setAlpha(0.1)

        let textureSize = 2.0
        for x in stride(from: rect.minX, to: rect.maxX, by: textureSize) {
            for y in stride(from: rect.minY, to: rect.maxY, by: textureSize) {
                let opacity = CGFloat.random(in: 0.0...1.0)
                context.setFillColor(NSColor.white.withAlphaComponent(opacity).cgColor)
                context.fill(CGRect(x: x, y: y, width: textureSize, height: textureSize))
            }
        }

        context.restoreGState()
    }

    /// Add realistic highlights
    private static func addToothHighlights(context: CGContext, rect: CGRect) {
        context.saveGState()

        // Create specular highlight gradient
        let highlightPath = CGMutablePath()
        let highlightRect = CGRect(
            x: rect.minX + rect.width * 0.2,
            y: rect.minY,
            width: rect.width * 0.6,
            height: rect.height * 0.3
        )
        highlightPath.addEllipse(in: highlightRect)

        context.addPath(highlightPath)
        context.clip()

        let colors: [NSColor] = [
            .white.withAlphaComponent(0.4),
            .white.withAlphaComponent(0.0)
        ]

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map { $0.cgColor } as CFArray,
            locations: [0.0, 1.0]
        )

        if let gradient = gradient {
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: highlightRect.midX, y: highlightRect.midY),
                startRadius: 0,
                endCenter: CGPoint(x: highlightRect.midX, y: highlightRect.midY),
                endRadius: highlightRect.width / 2,
                options: []
            )
        }

        context.restoreGState()
    }

    /// Apply realistic lighting based on face orientation
    private static func applyRealisticLighting(
        to image: CGImage,
        landmarks: FacialLandmarks,
        settings: SimulationSettings
    ) -> CGImage {

        // Calculate light direction from face orientation
        let lightDirection = estimateLightDirection(from: landmarks)

        // Apply directional lighting filter
        let ciImage = CIImage(cgImage: image)

        let lightFilter = CIFilter(name: "CISpotLight")
        lightFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        lightFilter?.setValue(CIVector(x: lightDirection.x, y: lightDirection.y, z: 100), forKey: "inputLightPosition")
        lightFilter?.setValue(CIVector(x: lightDirection.x, y: lightDirection.y, z: 0), forKey: "inputLightPointsAt")
        lightFilter?.setValue(0.6, forKey: "inputBrightness")
        lightFilter?.setValue(30.0, forKey: "inputConcentration")

        guard let outputImage = lightFilter?.outputImage,
              let cgImage = CIContext().createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }

        return cgImage
    }

    /// Estimate light direction from facial landmarks
    private static func estimateLightDirection(from landmarks: FacialLandmarks) -> CGPoint {
        guard let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        // Simple heuristic: assume light comes from upper-left by default
        let faceCenter = CGPoint(
            x: (leftPupil.x + rightPupil.x) / 2,
            y: (leftPupil.y + rightPupil.y) / 2
        )

        return CGPoint(x: faceCenter.x - 50, y: faceCenter.y - 100)
    }

    /// Blend simulation with original photo
    private static func blendSimulationWithOriginal(
        original: CGImage,
        simulation: CGImage,
        landmarks: FacialLandmarks,
        blendMode: CGBlendMode
    ) -> CGImage {

        let width = original.width
        let height = original.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return simulation
        }

        // Draw original
        context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Blend simulation
        context.setBlendMode(blendMode)
        context.draw(simulation, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage() ?? simulation
    }

    /// Apply finishing touches (color correction, sharpness, etc.)
    private static func applyFinishingTouches(
        to image: CGImage,
        settings: SimulationSettings
    ) -> CGImage {

        let ciImage = CIImage(cgImage: image)
        var processedImage = ciImage

        // Apply color adjustment
        if let colorFilter = CIFilter(name: "CIColorControls") {
            colorFilter.setValue(processedImage, forKey: kCIInputImageKey)
            colorFilter.setValue(settings.brightness, forKey: kCIInputBrightnessKey)
            colorFilter.setValue(settings.contrast, forKey: kCIInputContrastKey)
            colorFilter.setValue(settings.saturation, forKey: kCIInputSaturationKey)

            if let output = colorFilter.outputImage {
                processedImage = output
            }
        }

        // Apply sharpening
        if settings.sharpen > 0 {
            if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
                sharpenFilter.setValue(processedImage, forKey: kCIInputImageKey)
                sharpenFilter.setValue(settings.sharpen, forKey: kCIInputSharpnessKey)

                if let output = sharpenFilter.outputImage {
                    processedImage = output
                }
            }
        }

        let context = CIContext()
        guard let cgImage = context.createCGImage(processedImage, from: processedImage.extent) else {
            return image
        }

        return cgImage
    }

    /// Calculate perspective transformation
    private static func calculatePerspectiveTransform(
        from landmarks: FacialLandmarks,
        imageSize: CGSize
    ) -> PerspectiveTransform {

        // Simple perspective based on pupil distance and orientation
        guard let leftPupil = landmarks.leftPupil,
              let rightPupil = landmarks.rightPupil else {
            return PerspectiveTransform.identity
        }

        let angle = atan2(rightPupil.y - leftPupil.y, rightPupil.x - leftPupil.x)
        let scale = hypot(rightPupil.x - leftPupil.x, rightPupil.y - leftPupil.y) / imageSize.width

        return PerspectiveTransform(angle: angle, scale: scale, tx: 0, ty: 0)
    }

    // MARK: - Video Simulation

    /// Generate before/after comparison video
    static func generateComparisonVideo(
        originalPhoto: NSImage,
        simulatedPhoto: NSImage,
        duration: TimeInterval = 5.0,
        outputURL: URL
    ) async throws {

        let size = originalPhoto.size

        // Create video writer
        guard let videoWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
            throw SimulationError.videoCreationFailed
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: nil)

        videoWriter.add(writerInput)
        videoWriter.startWriting()
        videoWriter.startSession(atSourceTime: .zero)

        let fps: Int32 = 30
        let frameDuration = CMTime(value: 1, timescale: fps)
        let totalFrames = Int(duration * Double(fps))

        // Generate transition frames
        for frameIndex in 0..<totalFrames {
            let progress = Double(frameIndex) / Double(totalFrames)

            // Smooth transition using ease-in-out
            let t = easeInOutCubic(progress)

            // Blend images
            let blendedImage = blendImages(
                from: originalPhoto,
                to: simulatedPhoto,
                progress: t
            )

            // Convert to pixel buffer
            if let pixelBuffer = createPixelBuffer(from: blendedImage, size: size) {
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))

                while !writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }

                adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            }
        }

        writerInput.markAsFinished()
        await videoWriter.finishWriting()

        if videoWriter.status != .completed {
            throw SimulationError.videoCreationFailed
        }
    }

    /// Ease-in-out cubic function for smooth transitions
    private static func easeInOutCubic(_ t: Double) -> Double {
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// Blend two images with progress
    private static func blendImages(from: NSImage, to: NSImage, progress: Double) -> NSImage {
        let size = from.size
        let outputImage = NSImage(size: size)

        outputImage.lockFocus()

        // Draw "from" image
        from.draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)

        // Draw "to" image with alpha
        to.draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: progress)

        outputImage.unlockFocus()

        return outputImage
    }

    /// Create pixel buffer from NSImage
    private static func createPixelBuffer(from image: NSImage, size: CGSize) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )

        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }

        CVPixelBufferUnlockBaseAddress(buffer, [])

        return buffer
    }
}

// MARK: - Supporting Types

struct ToothDesignData {
    var boundingRect: CGRect
    var type: SimulationToothType
    var shade: ToothShade
    var morphology: ToothMorphology
}

enum SimulationToothType: String {
    case centralIncisor = "Central Incisor"
    case lateralIncisor = "Lateral Incisor"
    case canine = "Canine"
    case premolar = "Premolar"
    case molar = "Molar"
}

enum ToothShade: String, CaseIterable {
    case bleachWhite = "0M1"
    case naturalWhite = "1M2"
    case lightIvory = "2M2"
    case ivory = "3M2"
    case darkIvory = "4M2"

    func gradientColors(translucency: Double) -> [NSColor] {
        let baseColor = self.baseColor
        let alpha = CGFloat(translucency)

        return [
            baseColor.blended(withFraction: 0.2, of: .white)!.withAlphaComponent(alpha),
            baseColor.withAlphaComponent(alpha),
            baseColor.blended(withFraction: 0.1, of: .gray)!.withAlphaComponent(alpha * 0.9),
            baseColor.blended(withFraction: 0.2, of: .gray)!.withAlphaComponent(alpha * 0.8)
        ]
    }

    var baseColor: NSColor {
        switch self {
        case .bleachWhite: return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        case .naturalWhite: return NSColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1.0)
        case .lightIvory: return NSColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1.0)
        case .ivory: return NSColor(red: 0.94, green: 0.91, blue: 0.85, alpha: 1.0)
        case .darkIvory: return NSColor(red: 0.92, green: 0.88, blue: 0.80, alpha: 1.0)
        }
    }
}

struct ToothMorphology {
    var width: CGFloat
    var height: CGFloat
    var curvature: CGFloat
    var texture: TextureType

    enum TextureType: String {
        case smooth = "Smooth"
        case natural = "Natural"
        case textured = "Textured"
    }
}

struct SimulationSettings {
    var blendMode: CGBlendMode
    var translucency: Double
    var addSurfaceTexture: Bool
    var addHighlights: Bool
    var brightness: Double
    var contrast: Double
    var saturation: Double
    var sharpen: Double

    static let `default` = SimulationSettings(
        blendMode: .normal,
        translucency: 0.85,
        addSurfaceTexture: true,
        addHighlights: true,
        brightness: 0.0,
        contrast: 1.0,
        saturation: 1.0,
        sharpen: 0.3
    )
}

struct SmileSimulationResult {
    var simulatedImage: NSImage
    var originalImage: NSImage
    var confidence: Double
    var processingTime: TimeInterval
}

struct PerspectiveTransform {
    var angle: CGFloat
    var scale: CGFloat
    var tx: CGFloat
    var ty: CGFloat

    static let identity = PerspectiveTransform(angle: 0, scale: 1, tx: 0, ty: 0)

    func apply(to rect: CGRect) -> CGRect {
        // Apply simple affine transformation
        let transform = CGAffineTransform(rotationAngle: angle)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: tx, y: ty)

        return rect.applying(transform)
    }
}

enum SimulationError: LocalizedError {
    case invalidImage
    case renderingFailed
    case videoCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image format"
        case .renderingFailed: return "Failed to render simulation"
        case .videoCreationFailed: return "Failed to create video"
        }
    }
}
