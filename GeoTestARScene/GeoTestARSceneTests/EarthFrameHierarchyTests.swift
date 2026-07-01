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

    @Test func isIdentity_detectsNonIdentity() {
        let h = EarthFrameHierarchy.make()
        #expect(EarthFrameHierarchy.isIdentity(h.earthFrame) == true)

        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4<Float>(1, 2, 3, 1) // translation → non-identity
        h.earthFrame.simdTransform = t

        #expect(EarthFrameHierarchy.isIdentity(h.earthFrame) == false)
    }
}
