//
//  Smile2DOverlaySheet.swift
//  smileai
//
//  2D Smile Overlay System - Integration Wrapper
//

import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct Smile2DOverlaySheet: View {
    
    // MARK: - Properties
    
    // Shared state from parent
    @ObservedObject var state: SmileOverlayState
    @Binding var isPresented: Bool
    
    // Dependencies
    @StateObject private var toothLibrary = ToothLibraryManager()
    
    // Local UI state
    @State private var isLoadingLibrary = false
    @State private var showQualityReport = false
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Toolbar
                headerToolbar
                
                Divider()
                
                // Canvas
                SmileOverlayCanvas(state: state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.8))
                
                // Library Selector
                libraryScrollView
            }
            .navigationTitle("2D Smile Design")
            // FIX: Removed .navigationBarTitleDisplayMode(.inline) as it is iOS-only
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    // MARK: - Components
    
    private var headerToolbar: some View {
        HStack {
            Button(action: { state.clearAllTeeth() }) {
                Label("Clear", systemImage: "trash")
            }
            
            Spacer()
            
            // Toggle Grid
            Toggle("Grid", isOn: $state.showGrid)
                .toggleStyle(.switch)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var libraryScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ToothType.allCases, id: \.self) { type in
                    Button(action: { addTooth(type) }) {
                        VStack {
                            Image(systemName: "mouth")
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            
                            Text(type.rawValue.capitalized)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .frame(height: 100)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Logic
    
    private func addTooth(_ type: ToothType) {
        // Get standard dimensions for this tooth type
        let dimensions = type.typicalDimensions
        
        // Safely add tooth on MainActor
        // FIX: Added missing arguments (toothType, width, height)
        // FIX: Changed scale from CGSize to CGFloat (1.0)
        let tooth = ToothOverlay2D(
            id: UUID(),
            toothNumber: type.rawValue,
            toothType: type,
            position: CGPoint(x: state.photoSize.width/2, y: state.photoSize.height/2),
            rotation: 0,
            scale: 1.0,
            width: dimensions.width,
            height: dimensions.height
        )
        state.addTooth(tooth)
    }
}
