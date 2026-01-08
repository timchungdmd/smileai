//
//  PhotoAnalysisView.swift
//  smileai
//
//  Created by Tim Chung on 1/7/26.
//

import SwiftUI
import AVFoundation
import AppKit

struct PhotoAnalysisView: View {
    let image: NSImage
    @Binding var landmarks: [LandmarkType: CGPoint]
    var isPlacing: Bool
    var isLocked: Bool
    var activeType: LandmarkType?
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .coordinateSpace(name: "AnalysisSpace")
                        .onTapGesture(count: 1, coordinateSpace: .named("AnalysisSpace")) { loc in
                            handleTap(at: loc, in: geo.size)
                        }
                    
                    EstheticLines2D(landmarks: landmarks, rect: imageRect(in: geo.size))
                    
                    ForEach(LandmarkType.allCases, id: \.self) { type in
                        if let norm = landmarks[type] {
                            landmarkView(for: type, normalized: norm, in: geo.size)
                        }
                    }
                }
                .scaleEffect(scale)
                .offset(offset)
                
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(magnificationGesture)
                    .simultaneousGesture(dragGesture)
                    .onTapGesture(count: 2) {
                        resetTransform()
                    }
                    .allowsHitTesting(!isPlacing || isLocked)
            }
            .clipped()
        }
    }
    
    private func imageRect(in size: CGSize) -> CGRect {
        AVMakeRect(aspectRatio: image.size, insideRect: CGRect(origin: .zero, size: size))
    }
    
    private func handleTap(at location: CGPoint, in size: CGSize) {
        guard !isLocked && isPlacing, let type = activeType else { return }
        let rect = imageRect(in: size)
        
        if rect.contains(location) {
            landmarks[type] = CGPoint(
                x: (location.x - rect.minX) / rect.width,
                y: (location.y - rect.minY) / rect.height
            )
        }
    }
    
    private func landmarkView(for type: LandmarkType, normalized: CGPoint, in size: CGSize) -> some View {
        let rect = imageRect(in: size)
        let x = rect.minX + normalized.x * rect.width
        let y = rect.minY + normalized.y * rect.height
        
        return Group {
            Circle()
                .fill(type == .midline ? Color.cyan : Color.yellow)
                .frame(width: 12 / scale, height: 12 / scale)
                .position(x: x, y: y)
                .gesture(
                    DragGesture(coordinateSpace: .named("AnalysisSpace"))
                        .onChanged { val in
                            if !isLocked {
                                updateLandmark(type, at: val.location, in: rect)
                            }
                        }
                )
            
            if isPlacing {
                Text(type.rawValue)
                    .font(.system(size: 10))
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                    .position(x: x, y: y - (20 / scale))
                    .scaleEffect(1 / scale)
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
            }
        }
    }
    
    private func updateLandmark(_ type: LandmarkType, at location: CGPoint, in rect: CGRect) {
        let clampedX = min(max(location.x, rect.minX), rect.maxX)
        let clampedY = min(max(location.y, rect.minY), rect.maxY)
        
        landmarks[type] = CGPoint(
            x: (clampedX - rect.minX) / rect.width,
            y: (clampedY - rect.minY) / rect.height
        )
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1.0, lastScale * value)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isPlacing || isLocked {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                if !isPlacing || isLocked {
                    lastOffset = offset
                }
            }
    }
    
    private func resetTransform() {
        withAnimation {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
}

struct EstheticLines2D: View {
    var landmarks: [LandmarkType: CGPoint]
    var rect: CGRect
    
    func pt(_ t: LandmarkType) -> CGPoint? {
        guard let n = landmarks[t] else { return nil }
        return CGPoint(
            x: rect.minX + n.x * rect.width,
            y: rect.minY + n.y * rect.height
        )
    }
    
    var body: some View {
        Path { path in
            // Pupillary line + midline
            if let l = pt(.leftPupil), let r = pt(.rightPupil) {
                path.move(to: l)
                path.addLine(to: r)
                
                let mid = CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
                path.move(to: mid)
                path.addLine(to: CGPoint(x: mid.x, y: rect.maxY))
            }
            
            // Commissure line
            if let l = pt(.leftCommissure), let r = pt(.rightCommissure) {
                path.move(to: l)
                path.addLine(to: r)
            }
            
            // Facial thirds
            for landmark in [LandmarkType.glabella, .subnasale, .menton] {
                if let p = pt(landmark) {
                    path.move(to: CGPoint(x: rect.minX, y: p.y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: p.y))
                }
            }
        }
        .stroke(Color.white.opacity(0.6), lineWidth: 1)
        .allowsHitTesting(false)
    }
}
