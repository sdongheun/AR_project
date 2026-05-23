import RealityKit

struct RealityAnchorRenderer {
    func makeTextAnchor(title: String) -> AnchorEntity {
        let anchor = AnchorEntity(world: .zero)
        let text = MeshResource.generateText(title, extrusionDepth: 0.01, font: .systemFont(ofSize: 0.12))
        let material = SimpleMaterial(color: .systemBlue, isMetallic: false)
        let entity = ModelEntity(mesh: text, materials: [material])
        anchor.addChild(entity)
        return anchor
    }
}

