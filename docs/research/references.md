# References

Curated citations supporting the Phase 02 plan. Grouped by topic. Direct each link to the most authoritative source available (Apple/Google official docs first, then maintained reference repos, then secondary).

## ARKit geo-tracking (Apple)

- [`ARGeoTrackingConfiguration` — Apple Developer Documentation](https://developer.apple.com/documentation/arkit/argeotrackingconfiguration)
- [`ARGeoAnchor` — Apple Developer Documentation](https://developer.apple.com/documentation/arkit/argeoanchor)
- [`ARGeoTrackingStatus` and `ARGeoTrackingStatus.Accuracy` (enum: high / medium / low) — Apple](https://developer.apple.com/documentation/arkit/argeotrackingstatus)
- [Tracking geographic locations in AR — Apple sample-code-style guide](https://developer.apple.com/documentation/arkit/tracking-geographic-locations-in-ar)
- [Explore ARKit 4 — WWDC 2020 session 10611](https://developer.apple.com/videos/play/wwdc2020/10611/) (introduces Location Anchors; lifecycle and gating discussed in detail)
- [ARGeoTracking real-world behavior — Apple Developer Forums thread 745033](https://developer.apple.com/forums/thread/745033) (developer reports on accuracy in cities and re-localization windows)

## ARCore Geospatial (Google) — iOS

- [ARCore Geospatial API overview — Google for Developers](https://developers.google.com/ar/develop/geospatial)
- [Geospatial quickstart for iOS](https://developers.google.com/ar/develop/ios/geospatial/quickstart)
- [Enable the Geospatial API for your iOS app](https://developers.google.com/ar/develop/ios/geospatial/enable)
- [Use Geospatial anchors to position real-world content on iOS](https://developers.google.com/ar/develop/ios/geospatial/anchors) (WGS84 / Terrain / Rooftop anchor types; resolution states)
- [Obtain the device camera's Geospatial transform on iOS](https://developers.google.com/ar/develop/ios/geospatial/obtain-device-pose) (exposes `orientationYawAccuracy`, `horizontalAccuracy`)
- [Geospatial API usage quota](https://developers.google.com/ar/develop/c/geospatial/api-usage-quota) (1,000 sessions/min, 100,000 requests/min limits)
- [`GARSession` Class Reference (iOS)](https://developers.google.com/ar/reference/ios/interface/GARSession)
- [`GARSessionConfiguration(Geospatial)` category](https://developers.google.com/ar/reference/ios/category/GARSessionConfiguration(Geospatial))
- [`google-ar/arcore-ios-sdk` releases on GitHub](https://github.com/google-ar/arcore-ios-sdk/releases) (v1.54.0 was current as of April 2024)
- [`google-ar/arcore-ios-sdk/Examples/GeospatialExample`](https://github.com/google-ar/arcore-ios-sdk/tree/master/Examples/GeospatialExample) (Swift + SwiftUI sample app; demonstrates Streetscape Geometry integration)

## ARCore Streetscape Geometry (occlusion source)

- [Use buildings and terrain around you on iOS — Streetscape Geometry guide](https://developers.google.com/ar/develop/ios/geospatial/streetscape-geometry)
- [`GARStreetscapeGeometry` class reference (iOS)](https://developers.google.com/ar/reference/ios/interface/GARStreetscapeGeometry) (`.mesh`, `.meshTransform`, `.trackingState`, LOD1/LOD2 quality flags)
- [Build transformative AR experiences with new ARCore and geospatial features — Google Developers Blog](https://developers.googleblog.com/en/build-transformative-augmented-reality-experiences-with-new-arcore-and-geospatial-features/) (introduces Streetscape Geometry, Rooftop Anchors, Geospatial Depth)
- [Geospatial Depth (Android only) — Google for Developers](https://developers.google.com/ar/develop/depth) (confirms Geospatial Depth API is unavailable on iOS — informs the "render depth ourselves from Streetscape mesh" decision)

## SceneKit depth-only occlusion pattern

- [`SCNMaterial.writesToDepthBuffer` — Apple](https://developer.apple.com/documentation/scenekit/scnmaterial/writestodepthbuffer)
- [`SCNMaterial.readsFromDepthBuffer` — Apple](https://developer.apple.com/documentation/scenekit/scnmaterial/readsfromdepthbuffer)
- [`SCNMaterial.colorBufferWriteMask` (introduced iOS 11) — Apple](https://developer.apple.com/documentation/scenekit/scnmaterial/2867554-colorbufferwritemask)
- [`SCNTechnique` — Apple](https://developer.apple.com/documentation/scenekit/scntechnique) (for post-processing passes if we extend)

## glTF asset pipeline (iOS runtime)

- [`warrenm/GLTFKit2`](https://github.com/warrenm/GLTFKit2) (canonical loader; Objective-C / Swift; SceneKit + Model I/O + QuickLook bridges; Draco + KTX2 support; SwiftPM-ready)
- [GLTFKit2 README and load patterns](https://github.com/warrenm/GLTFKit2/blob/master/README.md)
- [Khronos Group — open-source iOS glTF Viewer (SceneKit + GLTFKit2 + DracoSwift + libktx)](https://www.khronos.org/blog/khronos-releases-open-source-ios-app-for-viewing-gltf-files) (production reference for SceneKit + glTF on iOS)

## Outdoor AR pose / drift correction (background)

- [Niantic Labs — Lightship VPS: Building Our 3D Map From Crowdsourced Scans](https://nianticlabs.com/news/vps-part-2) (their crowdsourced VPS approach; not adopted but instructive on hierarchical map caches and pose smoothing)
- [Niantic Labs — Lightship VPS: How Niantic's API service works](https://nianticlabs.com/news/vps-part-3)
- [Niantic Lightship VPS documentation](https://lightship.dev/docs/ardk/features/lightship_vps/)
- [A visual-GPS fusion based outdoor augmented reality method — ACM SIGGRAPH VRCAI 2017](https://dl.acm.org/doi/10.1145/3284398.3284414) (academic background on combining absolute GPS with VIO-style local tracking)
- [Direct and Indirect vSLAM Fusion for Augmented Reality — PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC8404931/) (background on SLAM fusion approaches relevant to bounded-correction patterns)

## VPS landscape, comparative

- [Google Developers Blog — Make the world your canvas with the ARCore Geospatial API](https://developers.googleblog.com/en/make-the-world-your-canvas-with-the-arcore-geospatial-api/) (Google's pitch with technical details on the Street View 3D point cloud + neural network localizer; "5 m / 5°" typical accuracy quoted)
- [What is Visual Positioning System (VPS)? — Geospatial World](https://geospatialworld.net/prime/business-and-industry-trends/what-is-visual-positioning-system-vps/) (general explainer; useful for stakeholder discussions)

## Carried forward from prior research

These two files predate this plan and remain valid background reading:

- [`VPS-research.md`](VPS-research.md) — initial VPS / occlusion landscape survey
- [`research-todos.md`](research-todos.md) — open questions, with confirmed findings on cesium-native tile budgets, Google Map Tiles attribution requirements, ARKit GeoTracking gating logic, key management
