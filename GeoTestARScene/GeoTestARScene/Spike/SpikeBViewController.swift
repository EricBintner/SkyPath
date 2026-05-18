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
//  This file ships as a SCAFFOLD. The two render paths are stubbed with
//  detailed TODOs because the configuration depends on Spike A's outcome
//  (the ARSession config to pair with GARSession). Fill in once Spike A
//  is recorded.
//

import UIKit
import ARKit
import SceneKit
import RealityKit
import ARCore

final class SpikeBViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {

    private enum RenderMode: Int { case sceneKit = 0, realityKit = 1 }
    private var mode: RenderMode = .sceneKit

    private let modeSelector = UISegmentedControl(items: ["SceneKit", "RealityKit"])
    private let hudLabel = UILabel()
    private let dismissButton = UIButton(type: .system)

    // SceneKit container
    private let sceneView = ARSCNView()
    // RealityKit container
    private let realityView = ARView(frame: .zero)

    private var garSession: GARSession?

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

    private func setupViewsForCurrentMode() {
        sceneView.removeFromSuperview()
        realityView.removeFromSuperview()
        let container: UIView
        switch mode {
        case .sceneKit:
            sceneView.frame = view.bounds
            sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            sceneView.session.delegate = self
            sceneView.delegate = self
            view.addSubview(sceneView)
            container = sceneView
        case .realityKit:
            realityView.frame = view.bounds
            realityView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            realityView.session.delegate = self
            view.addSubview(realityView)
            container = realityView
        }
        view.sendSubviewToBack(container)
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
        hudLabel.text = "Spike B — TODO: fill in render paths"

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
        // TODO: spike-b configuration
        // Use whichever ARSessionConfiguration Spike A confirmed works:
        //   - If Spike A passed: ARGeoTrackingConfiguration
        //   - If Spike A failed and fallback passed: ARWorldTrackingConfiguration
        let config: ARConfiguration = {
            if ARGeoTrackingConfiguration.isSupported {
                let c = ARGeoTrackingConfiguration()
                c.worldAlignment = .gravityAndHeading
                return c
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
        // Feed GARSession; harvest streetscape geometries.
        guard let gar = garSession else { return }
        do {
            let garFrame = try gar.update(frame)
            renderStreetscapeGeometries(garFrame.streetscapeGeometries ?? [])
        } catch {
            NSLog("[SpikeB] GARSession.update threw: \(error)")
        }
    }

    // MARK: - Rendering (the actual experiment)

    private func renderStreetscapeGeometries(_ geometries: [GARStreetscapeGeometry]) {
        switch mode {
        case .sceneKit:   renderSceneKit(geometries)
        case .realityKit: renderRealityKit(geometries)
        }
    }

    private func renderSceneKit(_ geometries: [GARStreetscapeGeometry]) {
        // TODO: spike-b SceneKit path
        //
        // For each GARStreetscapeGeometry in `geometries`:
        //   1. Convert geom.mesh (vertices + triangleIndices) into SCNGeometry:
        //        let positions = SCNGeometrySource(vertices: vertexArray)
        //        let element = SCNGeometryElement(indices: indexArray, primitiveType: .triangles)
        //        let scnGeom = SCNGeometry(sources: [positions], elements: [element])
        //   2. Apply a depth-only SCNMaterial:
        //        let mat = SCNMaterial()
        //        mat.writesToDepthBuffer = true
        //        mat.readsFromDepthBuffer = true
        //        mat.colorBufferWriteMask = []
        //        mat.isDoubleSided = false
        //        scnGeom.materials = [mat]
        //   3. Wrap in SCNNode, set .simdTransform = geom.meshTransform, .renderingOrder = -1.
        //   4. Track existing geometries by GARStreetscapeGeometry.identifier so you
        //      update/remove rather than duplicate.
        //
        // Then place three debug magenta cubes at +50m, +80m, +120m along
        // camera forward (post-localization) to visually verify occlusion.
        //
        // Throttle mesh rebuilds to ~4 Hz max per geometry.
        hudLabel.text = "Spike B — SceneKit\n\nStreetscape count: \(geometries.count)\n\n(TODO: render path)"
    }

    private func renderRealityKit(_ geometries: [GARStreetscapeGeometry]) {
        // TODO: spike-b RealityKit path
        //
        // For each GARStreetscapeGeometry:
        //   1. Build a MeshResource from geom.mesh — use MeshResource.generate(from:)
        //      with a MeshDescriptor populated from vertices/triangleIndices.
        //   2. ModelComponent with materials = [OcclusionMaterial()].
        //   3. Place as a ModelEntity under an AnchorEntity at world position
        //      derived from geom.meshTransform.
        //   4. Track existing entities by GARStreetscapeGeometry.identifier.
        //
        // Place three debug magenta cubes at the same +50m, +80m, +120m
        // positions for an apples-to-apples comparison.
        hudLabel.text = "Spike B — RealityKit\n\nStreetscape count: \(geometries.count)\n\n(TODO: render path)"
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
