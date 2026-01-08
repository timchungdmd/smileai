import SwiftUI

struct DesignToolsView: View {
    @Binding var templateVisible: Bool
    @Binding var showGoldenRatio: Bool
    @Binding var selectedToothName: String?
    @Binding var toothStates: [String: ToothState]
    @Binding var archPosX: Float
    @Binding var archPosY: Float
    @Binding var archPosZ: Float
    @Binding var archWidth: Float
    @Binding var archCurve: Float
    @Binding var toothLength: Float
    @Binding var toothRatio: Float
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show Template", isOn: $templateVisible)
                Toggle("Golden Ratio", isOn: $showGoldenRatio)
                Divider()
                
                if let selected = selectedToothName {
                    Text("Selected: \(selected)").font(.headline).foregroundStyle(.blue)
                    
                    let binding = Binding(
                        get: { toothStates[selected] ?? ToothState() },
                        set: { toothStates[selected] = $0 }
                    )
                    
                    Group {
                        Text("Rotation").font(.caption).bold()
                        SliderRow(label: "Torque (X)", value: Binding(get: { binding.wrappedValue.rotation.x }, set: { var n = binding.wrappedValue; n.rotation.x = $0; binding.wrappedValue = n }), range: -1.0...1.0)
                        SliderRow(label: "Rotate (Y)", value: Binding(get: { binding.wrappedValue.rotation.y }, set: { var n = binding.wrappedValue; n.rotation.y = $0; binding.wrappedValue = n }), range: -1.0...1.0)
                        SliderRow(label: "Tip (Z)", value: Binding(get: { binding.wrappedValue.rotation.z }, set: { var n = binding.wrappedValue; n.rotation.z = $0; binding.wrappedValue = n }), range: -1.0...1.0)
                    }
                    Divider()
                    Group {
                        Text("Dimensions").font(.caption).bold()
                        SliderRow(label: "Width (X)", value: Binding(get: { binding.wrappedValue.scale.x }, set: { var n = binding.wrappedValue; n.scale.x = $0; binding.wrappedValue = n }), range: 0.5...2.0)
                        SliderRow(label: "Length (Y)", value: Binding(get: { binding.wrappedValue.scale.y }, set: { var n = binding.wrappedValue; n.scale.y = $0; binding.wrappedValue = n }), range: 0.5...2.0)
                        SliderRow(label: "Thick (Z)", value: Binding(get: { binding.wrappedValue.scale.z }, set: { var n = binding.wrappedValue; n.scale.z = $0; binding.wrappedValue = n }), range: 0.5...2.0)
                    }
                    
                    Button("Deselect") { selectedToothName = nil }.font(.caption).padding(.top, 5)
                } else {
                    Group {
                        Text("Arch Position").font(.headline)
                        SliderRow(label: "Up/Down", value: $archPosY, range: -0.1...0.1)
                        SliderRow(label: "Left/Right", value: $archPosX, range: -0.05...0.05)
                        SliderRow(label: "Fwd/Back", value: $archPosZ, range: -0.1...0.2)
                    }
                    Divider()
                    Group {
                        Text("Arch Shape").font(.headline)
                        SliderRow(label: "Width", value: $archWidth, range: 0.5...2.0)
                        SliderRow(label: "Curve", value: $archCurve, range: 0.0...1.0)
                    }
                }
            }
        }
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    
    var body: some View {
        HStack {
            Text(label).font(.caption).frame(width: 60, alignment: .leading)
            Slider(value: $value, in: range)
        }
    }
}
