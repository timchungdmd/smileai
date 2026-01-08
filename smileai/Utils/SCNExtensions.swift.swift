import SceneKit

extension SCNVector3 {
    // MARK: - Properties
    var length: Float {
        return sqrt(Float(x*x + y*y + z*z))
    }
    
    var normalized: SCNVector3 {
        let len = length
        return len == 0 ? SCNVector3(0,0,0) : self / len
    }
    
    // MARK: - Operators
    static func + (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        return SCNVector3(left.x + right.x, left.y + right.y, left.z + right.z)
    }
    
    static func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        return SCNVector3(left.x - right.x, left.y - right.y, left.z - right.z)
    }
    
    static func * (vector: SCNVector3, scalar: Float) -> SCNVector3 {
        return SCNVector3(vector.x * CGFloat(scalar), vector.y * CGFloat(scalar), vector.z * CGFloat(scalar))
    }
    
    static func / (vector: SCNVector3, scalar: Float) -> SCNVector3 {
        return SCNVector3(vector.x / CGFloat(scalar), vector.y / CGFloat(scalar), vector.z / CGFloat(scalar))
    }
    
    // MARK: - Functions
    func dot(_ vector: SCNVector3) -> Float {
        return Float(x * vector.x + y * vector.y + z * vector.z)
    }
    
    func cross(_ vector: SCNVector3) -> SCNVector3 {
        return SCNVector3(
            y * vector.z - z * vector.y,
            z * vector.x - x * vector.z,
            x * vector.y - y * vector.x
        )
    }
    
    func distance(to vector: SCNVector3) -> Float {
        return (self - vector).length
    }
}//
//  SCNExtensions.swift.swift
//  smileai
//
//  Created by Tim Chung on 1/7/26.
//

