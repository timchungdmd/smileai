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
    
    // State is owned by parent (Smile2DOverlaySheet), so we observe it
    @ObservedObject var state: SmileOverlayState
    
    // TransformController is local to this view (manages gestures)
    @StateObject private var transformController: TransformController
    
    // MARK: - View Settings
    
    @State private var showHandles: Bool = true
    @State private var canvasSize: CGSize = .zero
    
    // MARK: - Initialization
    
    init(state: SmileOverlayState) {
        self.state = state
        // Initialize StateObject with dependency
        _transformController = StateObject(wrappedValue: TransformController(state: state))
    }
    
    // Convenience init for previews
    init(photo: NSImage? = nil) {
        let tempState = SmileOverlayState()
        if let photo = photo {
            tempState.loadPhoto(photo)
        }
        self.state = tempState
        _transformController = StateObject(wrappedValue: TransformController(state: tempState))
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
                // FIX: Only enable gestures if a photo is loaded.
                // Otherwise, this layer blocks the "Load Photo" button.
                if state.sourcePhoto != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(transformController.dragGesture())
                        .gesture(transformController.magnificationGesture())
                        .gesture(transformController.rotationGesture())
                }
            }
            .onAppear {
                canvasSize = geometry.size
                transformController.updateHandles()
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
            }
        }
        .toolbar {
            toolbarContent
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
            Button(action: { state.showGrid.toggle() }) {
                Label("Grid", systemImage: state.showGrid ? "grid" : "grid.slash")
            }
            .help("Toggle measurement grid")
            
            Button(action: { state.showMeasurements.toggle() }) {
                Label("Measurements", systemImage: state.showMeasurements ? "ruler" : "ruler.fill")
            }
            .help("Toggle measurements")
            
            Divider()
            
            Button(action: { showHandles.toggle() }) {
                Label("Handles", systemImage: showHandles ? "hand.draw" : "hand.draw.fill")
            }
            .help("Toggle transform handles")
            
            Button(action: { state.isLocked.toggle() }) {
                Label("Lock", systemImage: state.isLocked ? "lock.fill" : "lock.open")
            }
            .help("Lock transforms")
        }
        
        // Center controls
        ToolbarItemGroup(placement: .principal) {
            HStack(spacing: 8) {
                Image(systemName: "eye").foregroundColor(.secondary)
                Slider(value: $state.overlayOpacity, in: 0.1...1.0) {
                    Text("Opacity")
                }
                .frame(width: 120)
                Text("\(Int(state.overlayOpacity * 100))%")
                    .font(.caption).foregroundColor(.secondary).frame(width: 40)
            }
            
            Divider()
            
            Menu {
                Button("Fit to Photo") { transformController.applyPreset(.fit) }
                Button("Center") { transformController.applyPreset(.center) }
                Button("Reset") { transformController.applyPreset(.original) }
                Divider()
                Button("Align to Midline") { transformController.alignToMidline() }
                    .disabled(state.measurementGrid.midline == nil)
                Button("Auto Level") { transformController.autoLevel() }
            } label: {
                Label("Transform", systemImage: "slider.horizontal.3")
            }
        }
        
        // Right side controls
        ToolbarItemGroup(placement: .automatic) {
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
            guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
            
            // UI updates must be on main thread
            DispatchQueue.main.async {
                state.loadPhoto(image)
                transformController.updateHandles()
            }
        }
    }
}
