//
//  SpikeBViewController.swift
//  Phase 02 — M02.0 spike code. Deleted after spikes complete.
//
//  Spike B: SceneKit (depth-only SCNMaterial) vs RealityKit
//  (OcclusionMaterial) as the renderer for Streetscape Geometry occluders.
//
//  Procedure in Phase02_Spike_Playbook.md §2. Pick the winner; record
//  result in Phase02_Spike_Results.md.
//
//  Both render paths consume the same GARStreetscapeGeometry stream:
//    * Triangle mesh comes in as GARMesh (vertices + triangle indices),
//      with a world-space meshTransform.
//    * Three magenta debug cubes are placed at +50/+80/+120 m along the
//      camera's forward axis the first frame streetscape geometries
//      arrive, so the user can walk around and see them get occluded.
//    * Mesh rebuilds are throttled to ≤4 Hz per geometry id.
//

import UIKit
import ARKit
import SceneKit
import RealityKit
import ARCore

final class SpikeBViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {

    private enum RenderMode: Int { case sceneKit = 0, realityKit = 1 }
    private var mode: RenderMode = .sceneKit

    // MARK: - Chrome

    private let modeSelector = UISegmentedControl(items: ["SceneKit", "RealityKit"])
    private let hudLabel = UILabel()
    private let dismissButton = UIButton(type: .system)

    // MARK: - AR containers

    private let sceneView = ARSCNView()
    private let realityView = ARView(frame: .zero)

    // MARK: - GARSession

    private var garSession: GARSession?

    // MARK: - Render state (cleared on mode switch)

    private var scnStreetscapeNodes: [UUID: SCNNode] = [:]
    private var rkStreetscapeEntities: [UUID: ModelEntity] = [:]
    private var rkRootAnchor: AnchorEntity?

    // Mesh rebuilds throttled to 4 Hz max per geometry id.
    private let rebuildInterval: TimeInterval = 0.25
    private var lastBuiltAt: [UUID: TimeInterval] = [:]

    private let debugDistances: [Float] = [50, 80, 120]
    private var debugCubesPlaced = false

    private var lastGeometryCount = 0
    private var lastCameraTrackingState = "initializing"

    private lazy var depthOnlyMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.writesToDepthBuffer = true
        m.readsFromDepthBuffer = true
        m.colorBufferWriteMask = []
        m.isDoubleSided = false
        return m
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupViewsForCurrentMode()
        setupChrome()
        initGARSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
        realityView.session.pause()
    }

    // MARK: - View setup

    private func setupViewsForCurrentMode() {
        // Pause the outgoing session so it doesn't keep running in the
        // background and skew the bake-off's FPS/thermal numbers.
        sceneView.session.pause()
        realityView.session.pause()
        sceneView.removeFromSuperview()
        realityView.removeFromSuperview()
        clearRenderState()

        let container: UIView
        switch mode {
        case .sceneKit:
            sceneView.frame = view.bounds
            sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            sceneView.session.delegate = self
            sceneView.delegate = self
            sceneView.showsStatistics = true
            view.addSubview(sceneView)
            container = sceneView
        case .realityKit:
            realityView.frame = view.bounds
            realityView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            realityView.session.delegate = self
            realityView.debugOptions.insert(.showStatistics)
            let root = AnchorEntity(world: matrix_identity_float4x4)
            realityView.scene.addAnchor(root)
            rkRootAnchor = root
            view.addSubview(realityView)
            container = realityView
        }
        view.sendSubviewToBack(container)
    }

    private func clearRenderState() {
        scnStreetscapeNodes.values.forEach { $0.removeFromParentNode() }
        scnStreetscapeNodes.removeAll()
        rkStreetscapeEntities.values.forEach { $0.removeFromParent() }
        rkStreetscapeEntities.removeAll()
        if let root = rkRootAnchor {
            realityView.scene.removeAnchor(root)
        }
        rkRootAnchor = nil
        lastBuiltAt.removeAll()
        debugCubesPlaced = false
        lastGeometryCount = 0
    }

    private func setupChrome() {
        modeSelector.selectedSegmentIndex = mode.rawValue
        modeSelector.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeSelector.translatesAutoresizingMaskIntoConstraints = false

        hudLabel.translatesAutoresizingMaskIntoConstraints = false
        hudLabel.numberOfLines = 0
        hudLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hudLabel.textColor = .white
        hudLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        hudLabel.text = "Spike B — starting…"

        dismissButton.setTitle("Done", for: .normal)
        dismissButton.setTitleColor(.white, for: .normal)
        dismissButton.backgroundColor = UIColor.darkGray.withAlphaComponent(0.85)
        dismissButton.layer.cornerRadius = 8
        dismissButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(modeSelector)
        view.addSubview(hudLabel)
        view.addSubview(dismissButton)
        NSLayoutConstraint.activate([
            modeSelector.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            modeSelector.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            hudLabel.topAnchor.constraint(equalTo: modeSelector.bottomAnchor, constant: 8),
            hudLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            hudLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            dismissButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            dismissButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    @objc private func modeChanged() {
        guard let new = RenderMode(rawValue: modeSelector.selectedSegmentIndex) else { return }
        mode = new
        setupViewsForCurrentMode()
        setupChrome()
        startSession()
    }

    @objc private func dismissTapped() { dismiss(animated: true) }

    // MARK: - GARSession

    private func initGARSession() {
        guard let apiKey = SpikeAViewController.exposedAPIKey() else {
            hudLabel.text = "ERROR: ARCORE_API_KEY missing. See Playbook §0.4."
            return
        }
        do {
            garSession = try GARSession(apiKey: apiKey, bundleIdentifier: Bundle.main.bundleIdentifier)
            let config = GARSessionConfiguration()
            config.geospatialMode = .enabled
            config.streetscapeGeometryMode = .enabled
            var err: NSError?
            garSession?.setConfiguration(config, error: &err)
            if let err = err {
                hudLabel.text = "GARSession config failed:\n\(err.localizedDescription)"
                garSession = nil
            }
        } catch {
            hudLabel.text = "GARSession init failed:\n\(error.localizedDescription)"
        }
    }

    private func startSession() {
        // ARGeoTrackingConfiguration when supported; fallback to
        // ARWorldTrackingConfiguration so the spike still produces
        // numbers on devices Apple doesn't cover.
        let config: ARConfiguration = {
            if ARGeoTrackingConfiguration.isSupported {
                return ARGeoTrackingConfiguration()
            } else {
                let c = ARWorldTrackingConfiguration()
                c.worldAlignment = .gravityAndHeading
                return c
            }
        }()
        switch mode {
        case .sceneKit:
            sceneView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
        case .realityKit:
            realityView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastCameraTrackingState = String(describing: frame.camera.trackingState)
        guard let gar = garSession else {
            updateHUD()
            return
        }
        do {
            let garFrame = try gar.update(frame)
            let geometries = garFrame.streetscapeGeometries ?? []
            lastGeometryCount = geometries.count
            renderStreetscapeGeometries(geometries)
            if !debugCubesPlaced, !geometries.isEmpty {
                placeDebugCubes(frame: frame)
                debugCubesPlaced = true
            }
        } catch {
            NSLog("[SpikeB] GARSession.update threw: \(error)")
        }
        updateHUD()
    }

    // MARK: - Render dispatch

    private func renderStreetscapeGeometries(_ geometries: [GARStreetscapeGeometry]) {
        let now = CACurrentMediaTime()
        let incoming = Set(geometries.map(\.identifier))
        for geom in geometries where geom.trackingState == .tracking {
            switch mode {
            case .sceneKit:   renderSceneKit(geom: geom, now: now)
            case .realityKit: renderRealityKit(geom: geom, now: now)
            }
        }
        sweepDead(incoming: incoming)
    }

    private func sweepDead(incoming: Set<UUID>) {
        for (id, node) in scnStreetscapeNodes where !incoming.contains(id) {
            node.removeFromParentNode()
            scnStreetscapeNodes.removeValue(forKey: id)
            lastBuiltAt.removeValue(forKey: id)
        }
        for (id, entity) in rkStreetscapeEntities where !incoming.contains(id) {
            entity.removeFromParent()
            rkStreetscapeEntities.removeValue(forKey: id)
            lastBuiltAt.removeValue(forKey: id)
        }
    }

    // MARK: - SceneKit render

    private func renderSceneKit(geom: GARStreetscapeGeometry, now: TimeInterval) {
        let id = geom.identifier
        let lastBuild = lastBuiltAt[id] ?? -.infinity
        let shouldRebuild = (now - lastBuild) >= rebuildInterval

        if let existing = scnStreetscapeNodes[id] {
            existing.simdTransform = geom.meshTransform
            if shouldRebuild, let scnGeom = makeSCNGeometry(from: geom.mesh) {
                scnGeom.materials = [depthOnlyMaterial]
                existing.geometry = scnGeom
                lastBuiltAt[id] = now
            }
            return
        }
        guard let scnGeom = makeSCNGeometry(from: geom.mesh) else { return }
        scnGeom.materials = [depthOnlyMaterial]
        let node = SCNNode(geometry: scnGeom)
        node.simdTransform = geom.meshTransform
        node.renderingOrder = -1
        sceneView.scene.rootNode.addChildNode(node)
        scnStreetscapeNodes[id] = node
        lastBuiltAt[id] = now
    }

    private func makeSCNGeometry(from mesh: GARMesh) -> SCNGeometry? {
        let vertexCount = Int(mesh.vertexCount)
        let triangleCount = Int(mesh.triangleCount)
        guard vertexCount > 0, triangleCount > 0 else { return nil }

        // GARVertex is { float x, y, z } packed (12 bytes), so we can
        // hand its raw buffer to SCNGeometrySource as-is.
        let vertexData = Data(bytes: mesh.vertices,
                              count: vertexCount * MemoryLayout<GARVertex>.size)
        let indexData = Data(bytes: mesh.triangles,
                             count: triangleCount * MemoryLayout<GARIndexTriangle>.size)

        let source = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<GARVertex>.size
        )
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: triangleCount,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        return SCNGeometry(sources: [source], elements: [element])
    }

    // MARK: - RealityKit render

    private func renderRealityKit(geom: GARStreetscapeGeometry, now: TimeInterval) {
        guard let root = rkRootAnchor else { return }
        let id = geom.identifier
        let lastBuild = lastBuiltAt[id] ?? -.infinity
        let shouldRebuild = (now - lastBuild) >= rebuildInterval

        if let existing = rkStreetscapeEntities[id] {
            existing.transform = Transform(matrix: geom.meshTransform)
            if shouldRebuild, let resource = try? makeMeshResource(from: geom.mesh) {
                existing.model = ModelComponent(mesh: resource, materials: [OcclusionMaterial()])
                lastBuiltAt[id] = now
            }
            return
        }
        guard let resource = try? makeMeshResource(from: geom.mesh) else { return }
        let entity = ModelEntity(mesh: resource, materials: [OcclusionMaterial()])
        entity.transform = Transform(matrix: geom.meshTransform)
        root.addChild(entity)
        rkStreetscapeEntities[id] = entity
        lastBuiltAt[id] = now
    }

    private func makeMeshResource(from mesh: GARMesh) throws -> MeshResource? {
        let vertexCount = Int(mesh.vertexCount)
        let triangleCount = Int(mesh.triangleCount)
        guard vertexCount > 0, triangleCount > 0 else { return nil }

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(vertexCount)
        for i in 0..<vertexCount {
            let v = mesh.vertices[i]
            positions.append(SIMD3<Float>(v.x, v.y, v.z))
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(triangleCount * 3)
        for i in 0..<triangleCount {
            let t = mesh.triangles[i].indices
            indices.append(t.0)
            indices.append(t.1)
            indices.append(t.2)
        }
        var desc = MeshDescriptor(name: "streetscape")
        desc.positions = MeshBuffers.Positions(positions)
        desc.primitives = .triangles(indices)
        return try MeshResource.generate(from: [desc])
    }

    // MARK: - Debug cubes

    private func placeDebugCubes(frame: ARFrame) {
        let t = frame.camera.transform
        let origin = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        // ARKit camera forward is -Z column.
        let forward = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)

        switch mode {
        case .sceneKit:
            let box = SCNBox(width: 0.5, height: 0.5, length: 0.5, chamferRadius: 0)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor.magenta
            mat.lightingModel = .constant
            box.materials = [mat]
            for d in debugDistances {
                let node = SCNNode(geometry: box)
                node.simdPosition = origin + forward * d
                sceneView.scene.rootNode.addChildNode(node)
            }
        case .realityKit:
            guard let root = rkRootAnchor else { return }
            let mesh = MeshResource.generateBox(size: 0.5)
            let mat = SimpleMaterial(color: .magenta, isMetallic: false)
            for d in debugDistances {
                let entity = ModelEntity(mesh: mesh, materials: [mat])
                entity.transform = Transform(translation: origin + forward * d)
                root.addChild(entity)
            }
        }
        NSLog("[SpikeB] Placed \(debugDistances.count) debug cubes at distances \(debugDistances) origin=\(origin) forward=\(forward)")
    }

    // MARK: - HUD

    private func updateHUD() {
        let modeName = mode == .sceneKit ? "SceneKit (depth-only SCNMaterial)" : "RealityKit (OcclusionMaterial)"
        let active = mode == .sceneKit ? scnStreetscapeNodes.count : rkStreetscapeEntities.count
        var lines: [String] = []
        lines.append("Spike B — \(modeName)")
        lines.append("Streetscape count: \(lastGeometryCount)")
        lines.append("Active occluders: \(active)")
        lines.append("Debug cubes placed: \(debugCubesPlaced)")
        lines.append("AR.camera: \(lastCameraTrackingState)")
        lines.append("")
        lines.append("Walk forward 50–120 m. Magenta cubes should")
        lines.append("disappear behind buildings as you pass them.")
        hudLabel.text = lines.joined(separator: "\n")
    }
}

// Expose API key helper to SpikeBViewController without duplicating logic.
extension SpikeAViewController {
    static func exposedAPIKey() -> String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: "ARCORE_API_KEY") as? String,
           !key.isEmpty, key != "$(ARCORE_API_KEY)" {
            return key
        }
        return nil
    }
}
