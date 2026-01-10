//
//  SmileOverlayCanvas.swift
//  smileai
//
//  2D Smile Overlay System - Main Canvas View
//  Phase 4: UI Components
//

import SwiftUI
import UniformTypeIdentifiers

/// Main interactive canvas for 2D smile design overlay
struct SmileOverlayCanvas: View {
    
    // MARK: - State
    
    @StateObject private var state: SmileOverlayState
    @StateObject private var transformController: TransformController
    
    // MARK: - View Settings
    
    @State private var showHandles: Bool = true
    @State private var canvasSize: CGSize = .zero
    
    // MARK: - Initialization
    
    init(state: SmileOverlayState) {
        let transformController = TransformController(state: state)
        
        _state = StateObject(wrappedValue: state)
        _transformController = StateObject(wrappedValue: transformController)
    }
    
    // Convenience init with photo
    init(photo: NSImage? = nil) {
        let state = SmileOverlayState()
        if let photo = photo {
            state.loadPhoto(photo)
        }
        
        let transformController = TransformController(state: state)
        
        _state = StateObject(wrappedValue: state)
        _transformController = StateObject(wrappedValue: transformController)
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color
                Color.black.opacity(0.9)
                
                // 1. Base photo layer
                if let photo = state.sourcePhoto {
                    Image(nsImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                } else {
                    placeholderView
                }
                
                // 2. Measurement grid layer
                if state.showGrid && state.hasContent {
                    MeasurementOverlayView(
                        grid: state.measurementGrid,
                        bounds: geometry.size
                    )
                    .opacity(0.5)
                }
                
                // 3. Tooth overlays layer
                if state.hasContent {
                    ForEach(state.transformedTeeth) { tooth in
                        if tooth.visible {
                            ToothOverlayView(
                                tooth: tooth,
                                outlineColor: state.outlineColor,
                                outlineThickness: state.outlineThickness,
                                fillOpacity: state.showFill ? state.fillOpacity : 0,
                                isSelected: state.selectedToothID == tooth.id
                            )
                            .opacity(state.overlayOpacity)
                        }
                    }
                }
                
                // 4. Transform handles layer
                if showHandles && !state.isLocked && state.hasContent {
                    ForEach(transformController.handles) { handle in
                        TransformHandleView(
                            handle: handle,
                            isActive: transformController.activeHandle == handle.type
                        )
                    }
                }
                
                // 5. Interaction layer (transparent overlay for gestures)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(transformController.dragGesture())
                    .gesture(transformController.magnificationGesture())
                    .gesture(transformController.rotationGesture())
            }
            .onAppear {
                canvasSize = geometry.size
            }
            .onChange(of: geometry.size) { oldSize, newSize in
                canvasSize = newSize
            }
        }
        .toolbar {
            toolbarContent
        }
        .onAppear {
            transformController.updateHandles()
        }
    }
    
    // MARK: - Placeholder View
    
    private var placeholderView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Load an intraoral photograph to begin")
                .font(.headline)
                .foregroundColor(.gray)
            
            Button("Load Photo") {
                loadPhotoDialog()
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        
        // Left side tools
        ToolbarItemGroup(placement: .navigation) {
            
            // Grid toggle
            Button(action: { state.showGrid.toggle() }) {
                Label(
                    "Grid",
                    systemImage: state.showGrid ? "grid" : "grid.slash"
                )
            }
            .help("Toggle measurement grid")
            
            // Measurements toggle
            Button(action: { state.showMeasurements.toggle() }) {
                Label(
                    "Measurements",
                    systemImage: state.showMeasurements ? "ruler" : "ruler.fill"
                )
            }
            .help("Toggle measurements")
            
            Divider()
            
            // Handles toggle
            Button(action: { showHandles.toggle() }) {
                Label(
                    "Handles",
                    systemImage: showHandles ? "hand.draw" : "hand.draw.fill"
                )
            }
            .help("Toggle transform handles")
            
            // Lock toggle
            Button(action: { state.isLocked.toggle() }) {
                Label(
                    "Lock",
                    systemImage: state.isLocked ? "lock.fill" : "lock.open"
                )
            }
            .help("Lock transforms")
        }
        
        // Center controls
        ToolbarItemGroup(placement: .principal) {
            
            // Opacity slider
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .foregroundColor(.secondary)
                
                Slider(
                    value: $state.overlayOpacity,
                    in: 0.1...1.0
                ) {
                    Text("Opacity")
                }
                .frame(width: 120)
                .help("Overlay opacity")
                
                Text("\(Int(state.overlayOpacity * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
            
            Divider()
            
            // Transform presets
            Menu {
                Button("Fit to Photo") {
                    transformController.applyPreset(.fit)
                }
                
                Button("Center") {
                    transformController.applyPreset(.center)
                }
                
                Button("Reset") {
                    transformController.applyPreset(.original)
                }
                
                Divider()
                
                Button("Align to Midline") {
                    transformController.alignToMidline()
                }
                .disabled(state.measurementGrid.midline == nil)
                
                Button("Auto Level") {
                    transformController.autoLevel()
                }
            } label: {
                Label("Transform", systemImage: "slider.horizontal.3")
            }
            .help("Transform presets")
        }
        
        // Right side controls
        ToolbarItemGroup(placement: .automatic) {
            
            // Undo/Redo
            Button(action: { state.undoTransform() }) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!state.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            
            Button(action: { state.redoTransform() }) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!state.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            
            Divider()
            
            // View options
            Menu {
                Toggle("Show Grid", isOn: $state.showGrid)
                Toggle("Show Measurements", isOn: $state.showMeasurements)
                Toggle("Show Fill", isOn: $state.showFill)
                Toggle("Snap to Grid", isOn: $transformController.snapToGrid)
                
                Divider()
                
                Picker("Grid Spacing", selection: $state.gridSpacing) {
                    Text("1mm").tag(Float(1.0))
                    Text("2mm").tag(Float(2.0))
                    Text("5mm").tag(Float(5.0))
                    Text("10mm").tag(Float(10.0))
                }
            } label: {
                Label("View", systemImage: "eye.circle")
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadPhotoDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = "Select an intraoral photograph"
        
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let image = NSImage(contentsOf: url) else {
                return
            }
            
            state.loadPhoto(image)
            transformController.updateHandles()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SmileOverlayCanvas_Previews: PreviewProvider {
    static var previews: some View {
        // Preview with mock photo
        let state = SmileOverlayState()
        
        // Create mock teeth
        var mockTeeth: [ToothOverlay2D] = []
        for i in 0..<8 {
            let x = CGFloat(400 + i * 50)
            let y: CGFloat = 300
            
            var tooth = ToothOverlay2D(
                toothNumber: "\(i + 1)",
                toothType: .central,
                position: CGPoint(x: x, y: y),
                width: 8.5,
                height: 10.5
            )
            
            // Generate placeholder outline
            tooth.generatePlaceholderOutline()
            
            mockTeeth.append(tooth)
        }
        
        state.toothOverlays = mockTeeth
        state.photoSize = CGSize(width: 1920, height: 1080)
        
        return SmileOverlayCanvas(state: state)
            .frame(width: 1200, height: 800)
    }
}
#endif
