import Testing
import SceneKit
@testable import SkyPath

struct EarthFrameHierarchyTests {

    @Test func make_buildsNamedIdentityHierarchy() {
        let h = EarthFrameHierarchy.make()

        #expect(h.earthFrame.name == "earth_frame")
        #expect(h.anchorsFrame.name == "earth_anchors")
        #expect(h.occludersFrame.name == "earth_occluders")

        #expect(h.anchorsFrame.parent === h.earthFrame)
        #expect(h.occludersFrame.parent === h.earthFrame)
        #expect(h.earthFrame.childNodes.count == 2)

        #expect(h.earthFrame.simdTransform == matrix_identity_float4x4)
        #expect(h.anchorsFrame.simdTransform == matrix_identity_float4x4)
        #expect(h.occludersFrame.simdTransform == matrix_identity_float4x4)
    }
}
