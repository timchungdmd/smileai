import Foundation
import SceneKit

// MARK: - Tooth State
struct ToothState: Equatable, Codable {
    var positionOffset: SIMD3<Float> = .zero
    var rotation: SIMD3<Float> = .zero // x=Torque, y=Rotation, z=Tip
    var scale: SIMD3<Float> = .one     // x=Width, y=Length, z=Thickness
}

// MARK: - Template Params
struct SmileTemplateParams: Equatable, Codable {
    var posX: Float
    var posY: Float
    var posZ: Float
    var scale: Float
    var curve: Float
    var length: Float
    var ratio: Float
}

