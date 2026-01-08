import Foundation
import SceneKit

struct ToothState: Equatable, Codable {
    var position: SCNVector3 = SCNVector3Zero
    var rotation: SCNVector4 = SCNVector4(0, 1, 0, 0)
    var scale: SCNVector3 = SCNVector3(1, 1, 1)
    var isLocked: Bool = false
    
    var quaternion: SCNQuaternion {
        get {
            let angle = Float(rotation.w)
            SCNQuaternion(
                x: Float(rotation.x) * sin(angle/2),
                y: Float(rotation.y) * sin(angle/2),
                z: Float(rotation.z) * sin(angle/2),
                w: cos(angle/2)
            )
        }
        set {
            let angle = 2 * acos(Float(newValue.w))
            let s = sqrt(1 - Float(newValue.w) * Float(newValue.w))
            if s < 0.001 {
                rotation = SCNVector4(1, 0, 0, 0)
            } else {
                rotation = SCNVector4(
                    Float(newValue.x) / s,
                    Float(newValue.y) / s,
                    Float(newValue.z) / s,
                    angle
                )
            }
        }
    }
    
    // Equatable conformance
    static func == (lhs: ToothState, rhs: ToothState) -> Bool {
        return lhs.position.x == rhs.position.x &&
               lhs.position.y == rhs.position.y &&
               lhs.position.z == rhs.position.z &&
               lhs.rotation.x == rhs.rotation.x &&
               lhs.rotation.y == rhs.rotation.y &&
               lhs.rotation.z == rhs.rotation.z &&
               lhs.rotation.w == rhs.rotation.w &&
               lhs.scale.x == rhs.scale.x &&
               lhs.scale.y == rhs.scale.y &&
               lhs.scale.z == rhs.scale.z &&
               lhs.isLocked == rhs.isLocked
    }
}

// MARK: - Codable Conformance
extension SCNVector3: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Float.self, forKey: .x)
        let y = try container.decode(Float.self, forKey: .y)
        let z = try container.decode(Float.self, forKey: .z)
        self.init(x, y, z)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Float(x), forKey: .x)
        try container.encode(Float(y), forKey: .y)
        try container.encode(Float(z), forKey: .z)
    }
    
    enum CodingKeys: String, CodingKey {
        case x, y, z
    }
}

extension SCNVector4: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Float.self, forKey: .x)
        let y = try container.decode(Float.self, forKey: .y)
        let z = try container.decode(Float.self, forKey: .z)
        let w = try container.decode(Float.self, forKey: .w)
        self.init(x, y, z, w)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Float(x), forKey: .x)
        try container.encode(Float(y), forKey: .y)
        try container.encode(Float(z), forKey: .z)
        try container.encode(Float(w), forKey: .w)
    }
    
    enum CodingKeys: String, CodingKey {
        case x, y, z, w
    }
}

// MARK: - Vector Math
extension SCNVector3 {
    static func +(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(
            Float(lhs.x) + Float(rhs.x),
            Float(lhs.y) + Float(rhs.y),
            Float(lhs.z) + Float(rhs.z)
        )
    }
    
    static func -(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(
            Float(lhs.x) - Float(rhs.x),
            Float(lhs.y) - Float(rhs.y),
            Float(lhs.z) - Float(rhs.z)
        )
    }
    
    static func *(lhs: SCNVector3, rhs: Float) -> SCNVector3 {
        SCNVector3(
            Float(lhs.x) * rhs,
            Float(lhs.y) * rhs,
            Float(lhs.z) * rhs
        )
    }
    
    var length: Float {
        let fx = Float(x)
        let fy = Float(y)
        let fz = Float(z)
        return sqrt(fx*fx + fy*fy + fz*fz)
    }
    
    var normalized: SCNVector3 {
        let len = length
        if len > 0 {
            return SCNVector3(
                Float(x)/len,
                Float(y)/len,
                Float(z)/len
            )
        }
        return self
    }
    
    func dot(_ v: SCNVector3) -> Float {
        Float(x) * Float(v.x) + Float(y) * Float(v.y) + Float(z) * Float(v.z)
    }
    
    func cross(_ v: SCNVector3) -> SCNVector3 {
        SCNVector3(
            Float(y) * Float(v.z) - Float(z) * Float(v.y),
            Float(z) * Float(v.x) - Float(x) * Float(v.z),
            Float(x) * Float(v.y) - Float(y) * Float(v.x)
        )
    }
}
