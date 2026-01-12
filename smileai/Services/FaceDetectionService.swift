//
//  FaceDetectionService.swift
//  smileai
//
//  Helper service for Task 1.1 - Face landmark detection
//

import Foundation
import Vision
import AppKit

class FaceDetectionService {

    // MARK: - Main Detection Method

    /// Detect facial landmarks from photo using Vision framework
    static func detectLandmarks(in image: NSImage) async throws -> FacialLandmarks? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw FaceDetectionError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            // Create face detection request with landmarks
            let request = VNDetectFaceLandmarksRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNFaceObservation],
                      let face = observations.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Convert Vision landmarks to our structure
                if let landmarks = FacialLandmarks.from(face, imageSize: image.size) {
                    continuation.resume(returning: landmarks)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            // Use latest revision for best accuracy
            request.revision = VNDetectFaceLandmarksRequestRevision3
            
            // Perform detection
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert normalized Vision coordinates to pixel coordinates
    static func convertToPixelCoordinates(
        _ normalizedPoint: CGPoint,
        imageSize: CGSize
    ) -> CGPoint {
        return CGPoint(
            x: normalizedPoint.x * imageSize.width,
            y: (1 - normalizedPoint.y) * imageSize.height // Flip Y axis
        )
    }
    
    // MARK: - Visualization Helper
    
    /// Create debug overlay showing detected landmarks
    static func visualizeLandmarks(
        _ landmarks: FacialLandmarks,
        on image: NSImage
    ) -> NSImage {
        let size = image.size
        let outputImage = NSImage(size: size)
        
        outputImage.lockFocus()
        
        // Draw original image
        image.draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        
        // Draw landmarks
        NSColor.green.setFill()
        NSColor.white.setStroke()
        
        let drawPoint = { (point: CGPoint?) in
            guard let p = point else { return }
            let rect = NSRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
            let path = NSBezierPath(ovalIn: rect)
            path.fill()
            path.lineWidth = 2
            path.stroke()
        }
        
        // Draw pupils
        drawPoint(landmarks.leftPupil)
        drawPoint(landmarks.rightPupil)
        
        // Draw IPD line
        if let left = landmarks.leftPupil, let right = landmarks.rightPupil {
            NSColor.yellow.setStroke()
            let line = NSBezierPath()
            line.move(to: left)
            line.line(to: right)
            line.lineWidth = 3
            line.stroke()
            
            // Draw IPD distance label
            let midPoint = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2 - 20)
            let distance = hypot(right.x - left.x, right.y - left.y)
            let label = String(format: "IPD: %.0fpx", distance)
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: NSColor.yellow,
                .strokeColor: NSColor.black,
                .strokeWidth: -3
            ]
            
            let attrString = NSAttributedString(string: label, attributes: attrs)
            attrString.draw(at: midPoint)
        }
        
        // Draw nose
        NSColor.cyan.setFill()
        drawPoint(landmarks.noseTip)
        
        // Draw mouth corners
        NSColor.red.setFill()
        drawPoint(landmarks.leftMouthCorner)
        drawPoint(landmarks.rightMouthCorner)
        
        outputImage.unlockFocus()

        return outputImage
    }

    // MARK: - Enhanced AI-Powered Analysis

    /// Perform comprehensive facial analysis including smile line detection
    static func performEnhancedAnalysis(in image: NSImage) async throws -> EnhancedFacialAnalysis? {
        // First detect basic landmarks
        guard let landmarks = try await detectLandmarks(in: image) else {
            return nil
        }

        let imageSize = image.size

        // Detect smile line
        let smileLine = SmileLineDetectionService.detectSmileLine(
            from: landmarks,
            imageSize: imageSize
        )

        // Predict tooth positions
        var toothPositions: [ToothPosition] = []
        if let smileLine = smileLine {
            toothPositions = SmileLineDetectionService.predictToothPositions(
                from: smileLine,
                landmarks: landmarks
            )
        }

        // Analyze facial proportions
        let proportions = SmileLineDetectionService.analyzeFacialProportions(landmarks: landmarks)

        // Detect asymmetry
        let asymmetry = SmileLineDetectionService.detectSmileAsymmetry(landmarks: landmarks)

        return EnhancedFacialAnalysis(
            landmarks: landmarks,
            smileLine: smileLine,
            predictedToothPositions: toothPositions,
            facialProportions: proportions,
            smileAsymmetry: asymmetry
        )
    }
}

// MARK: - Enhanced FacialLandmarks Extension

extension FacialLandmarks {
    
    /// Create from VNFaceObservation with pixel coordinates
    static func from(_ observation: VNFaceObservation, imageSize: CGSize) -> FacialLandmarks? {
        guard let landmarks = observation.landmarks else {
            return nil
        }
        
        var result = FacialLandmarks()
        
        // Helper to convert normalized to pixel coordinates
        let toPixels = { (point: CGPoint) -> CGPoint in
            FaceDetectionService.convertToPixelCoordinates(point, imageSize: imageSize)
        }
        
        // Extract pupils
        if let leftEye = landmarks.leftPupil?.normalizedPoints.first {
            result.leftPupil = toPixels(leftEye)
        }
        
        if let rightEye = landmarks.rightPupil?.normalizedPoints.first {
            result.rightPupil = toPixels(rightEye)
        }
        
        // Extract nose
        if let nose = landmarks.nose?.normalizedPoints.first {
            result.noseTip = toPixels(nose)
        }
        
        // Extract mouth
        if let outerLips = landmarks.outerLips?.normalizedPoints {
            // Convert all points
            let pixelPoints = outerLips.map(toPixels)
            
            // Find corners (leftmost and rightmost)
            if let leftCorner = pixelPoints.min(by: { $0.x < $1.x }) {
                result.leftMouthCorner = leftCorner
            }
            if let rightCorner = pixelPoints.max(by: { $0.x < $1.x }) {
                result.rightMouthCorner = rightCorner
            }
            
            // Find lip centers (topmost and bottommost)
            if let topCenter = pixelPoints.min(by: { $0.y < $1.y }) {
                result.upperLipCenter = topCenter
            }
            if let bottomCenter = pixelPoints.max(by: { $0.y < $1.y }) {
                result.lowerLipCenter = bottomCenter
            }
        }
        
        // Verify we have minimum required landmarks
        guard result.leftPupil != nil && result.rightPupil != nil else {
            return nil
        }
        
        return result
    }
}

// MARK: - Enhanced Analysis Result

struct EnhancedFacialAnalysis {
    var landmarks: FacialLandmarks
    var smileLine: SmileLine?
    var predictedToothPositions: [ToothPosition]
    var facialProportions: FacialProportions?
    var smileAsymmetry: SmileAsymmetry?
}

// MARK: - Errors

enum FaceDetectionError: LocalizedError {
    case invalidImage
    case noFaceDetected
    case insufficientLandmarks
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not process image"
        case .noFaceDetected:
            return "No face detected in photo"
        case .insufficientLandmarks:
            return "Could not detect required facial landmarks (eyes)"
        }
    }
}
