import SwiftUI
import SceneKit

struct SmileDesignView: View {
    @EnvironmentObject var session: PatientSession
    
    // Tools
    @State private var isCleanupMode: Bool = false
    
    // Cleanup/Crop States (Values 0.0 to 1.0 representing percentage of box)
    @State private var cropMinX: Float = -0.5
    @State private var cropMaxX: Float = 0.5
    @State private var cropMinY: Float = -0.5
    @State private var cropMaxY: Float = 0.5
    @State private var cropMinZ: Float = -0.5
    @State private var cropMaxZ: Float = 0.5
    
    var body: some View {
        HStack(spacing: 0) {
            // TOOLBAR
            VStack(alignment: .leading, spacing: 20) {
                Text("Smile Studio").font(.title2).fontWeight(.bold)
                Divider()
                
                if session.activeScanURL == nil {
                    Text("No Scan Loaded").foregroundStyle(.secondary)
                    Text("Process a scan first.").font(.caption)
                } else {
                    // MODE TOGGLE
                    Toggle("Cleanup Mode", isOn: $isCleanupMode)
                        .toggleStyle(.switch)
                        .padding(.vertical)
                    
                    if isCleanupMode {
                        // CLEANUP TOOLS
                        ScrollView {
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Crop / Clip").font(.headline)
                                GroupBox("Width (X)") {
                                    Slider(value: Binding(get: { Double(cropMinX) }, set: { cropMinX = Float($0) }), in: -1.0...0.0)
                                    Slider(value: Binding(get: { Double(cropMaxX) }, set: { cropMaxX = Float($0) }), in: 0.0...1.0)
                                }
                                GroupBox("Height (Y)") {
                                    Slider(value: Binding(get: { Double(cropMinY) }, set: { cropMinY = Float($0) }), in: -1.0...0.0)
                                    Slider(value: Binding(get: { Double(cropMaxY) }, set: { cropMaxY = Float($0) }), in: 0.0...1.0)
                                }
                                GroupBox("Depth (Z)") {
                                    Slider(value: Binding(get: { Double(cropMinZ) }, set: { cropMinZ = Float($0) }), in: -1.0...0.0)
                                    Slider(value: Binding(get: { Double(cropMaxZ) }, set: { cropMaxZ = Float($0) }), in: 0.0...1.0)
                                }
                            }
                        }
                    } else {
                        // NORMAL DESIGN TOOLS
                        Text("Select Cleanup to trim the model.")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .frame(width: 250).padding().background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // 3D CANVAS
            ZStack {
                Color.black
                if let scanURL = session.activeScanURL {
                    DesignSceneWrapper(
                        scanURL: scanURL,
                        isCleanupMode: isCleanupMode,
                        cropBox: (min: SCNVector3(cropMinX, cropMinY, cropMinZ),
                                  max: SCNVector3(cropMaxX, cropMaxY, cropMaxZ))
                    )
                } else {
                    Text("Ready to Design").foregroundStyle(.gray)
                }
            }
        }
    }
}
