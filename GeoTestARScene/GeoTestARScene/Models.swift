import Foundation
import CoreLocation
import ARKit
import SceneKit

// MARK: - Data Structures

struct LocationPoint: Decodable {
    let id: String
    let latitude: Double
    let longitude: Double
    let description: String
    let rotation: Double
    let tilt: Double
    let distance_to_next: Int?
    let model_variant: String
    let model_column: String?
    let model_column1_place: Double?
    let model_column2_place: Double?
    let model_column3_place: Double?
    let model_column4_place: Double?
}

struct ARModelLocation {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let modelName: String
    let rotation: Double
    let tilt: Double
    let description: String
    let distanceToNext: Int?
    let modelVariant: String
    let columnModel: String?
    let columnOffsets: [Double]

    var isLoaded: Bool = false
    var anchor: ARGeoAnchor?
    var node: SCNNode?
}

// MARK: - SCNGeometry Extension for ARMeshGeometry
extension SCNGeometry {
    convenience init(arMeshGeometry: ARMeshGeometry, fillMaterial: SCNMaterial? = nil) {
        let vertices = arMeshGeometry.vertices
        let normals = arMeshGeometry.normals
        let faces = arMeshGeometry.faces

        let vertexSource = SCNGeometrySource(buffer: vertices.buffer, vertexFormat: vertices.format, semantic: .vertex, vertexCount: vertices.count, dataOffset: vertices.offset, dataStride: vertices.stride)
        let normalSource = SCNGeometrySource(buffer: normals.buffer, vertexFormat: normals.format, semantic: .normal, vertexCount: normals.count, dataOffset: normals.offset, dataStride: normals.stride)
        
        let faceData = Data(bytes: faces.buffer.contents(), count: faces.buffer.length)
        
        let geometryElement = SCNGeometryElement(data: faceData,
                                                primitiveType: .triangles,
                                                primitiveCount: faces.count,
                                                bytesPerIndex: faces.bytesPerIndex)

        self.init(sources: [vertexSource, normalSource], elements: [geometryElement])

        let debugOverrideMaterial = SCNMaterial()
        debugOverrideMaterial.name = "GEOMETRY_DEBUG_OVERRIDE"
        debugOverrideMaterial.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.5)
        debugOverrideMaterial.isDoubleSided = true
        debugOverrideMaterial.lightingModel = .constant
        self.materials = [debugOverrideMaterial]
    }
}
