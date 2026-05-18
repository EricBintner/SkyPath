//
//  SpikeCViewController.swift
//  Phase 02 — Spike branch only. Do not merge to main.
//
//  Spike C: capture quantitative baseline metrics for the "sliding" bug on
//  the unmodified SceneKit + ARGeoAnchor path. The numbers from this spike
//  become the reference against which the M02.5 bounded-correction loop
//  is measured.
//
//  Approach: run an ARGeoTrackingConfiguration session, place test
//  anchors when the user taps, and emit prominent OSLog telemetry at every
//  meaningful boundary. The user walks a documented block; we read the
//  console afterwards to measure drift.
//
//  This file ships as a thin harness around the existing pre-Metal
//  sliding behavior — intentionally minimal so it stays comparable to
//  what the old SceneKit baseline was producing.
//

import UIKit
import ARKit
import SceneKit
import CoreLocation
import os.log

final class SpikeCViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {

    private let sceneView = ARSCNView()
    private let hudLabel = UILabel()
    private let placeButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)

    private let log = OSLog(subsystem: "com.ericbintner.SkyPath", category: "spike.c.sliding")

    private var anchors: [ARGeoAnchor] = []
    private var anchorPlacedAt: [String: Date] = [:]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        view.addSubview(sceneView)

        hudLabel.translatesAutoresizingMaskIntoConstraints = false
        hudLabel.numberOfLines = 0
        hudLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hudLabel.textColor = .white
        hudLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        hudLabel.text = "Spike C — waiting for localization…"

        placeButton.setTitle("Place anchor here", for: .normal)
        placeButton.setTitleColor(.white, for: .normal)
        placeButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.85)
        placeButton.layer.cornerRadius = 8
        placeButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        placeButton.addTarget(self, action: #selector(placeTapped), for: .touchUpInside)
        placeButton.translatesAutoresizingMaskIntoConstraints = false

        dismissButton.setTitle("Done", for: .normal)
        dismissButton.setTitleColor(.white, for: .normal)
        dismissButton.backgroundColor = UIColor.darkGray.withAlphaComponent(0.85)
        dismissButton.layer.cornerRadius = 8
        dismissButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(hudLabel)
        view.addSubview(placeButton)
        view.addSubview(dismissButton)
        NSLayoutConstraint.activate([
            hudLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hudLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            hudLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            placeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            placeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            dismissButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            dismissButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard ARGeoTrackingConfiguration.isSupported else {
            hudLabel.text = "ARGeoTrackingConfiguration unsupported on this device."
            return
        }
        let config = ARGeoTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        sceneView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
        os_log("spike.c started", log: log, type: .info)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    @objc private func placeTapped() {
        guard let frame = sceneView.session.currentFrame else { return }
        sceneView.session.getGeoLocation(forPoint: frame.camera.transform.columns.3.xyz) { [weak self] coord, alt, error in
            guard let self = self, error == nil else {
                NSLog("[SpikeC] getGeoLocation error: \(String(describing: error))")
                return
            }
            let name = String(format: "anchor-%d", self.anchors.count + 1)
            let anchor = ARGeoAnchor(name: name, coordinate: coord, altitude: alt)
            self.sceneView.session.add(anchor: anchor)
            self.anchors.append(anchor)
            self.anchorPlacedAt[anchor.identifier.uuidString] = Date()
            os_log("spike.c placed anchor name=%{public}@ lat=%.6f lon=%.6f alt=%.2f",
                   log: self.log, type: .info, name, coord.latitude, coord.longitude, alt)
        }
    }

    @objc private func dismissTapped() { dismiss(animated: true) }

    // MARK: - ARSCNViewDelegate (visualize placed anchors)

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARGeoAnchor else { return }
        let geom = SCNSphere(radius: 0.25)
        geom.firstMaterial?.diffuse.contents = UIColor.systemPink
        geom.firstMaterial?.lightingModel = .constant
        node.geometry = geom
    }

    // MARK: - ARSessionDelegate (the telemetry harness)

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateHUD(frame: frame)
    }

    func session(_ session: ARSession, didUpdate geoTrackingStatus: ARGeoTrackingStatus) {
        os_log("spike.c geoTracking state=%{public}@ accuracy=%{public}@",
               log: log, type: .info,
               String(describing: geoTrackingStatus.state),
               String(describing: geoTrackingStatus.accuracy))
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for a in anchors {
            guard let ga = a as? ARGeoAnchor else { continue }
            let p = a.transform.columns.3
            os_log("spike.c anchor.update name=%{public}@ xyz=(%.3f,%.3f,%.3f) coord=(%.6f,%.6f)",
                   log: log, type: .info,
                   ga.name ?? "?",
                   p.x, p.y, p.z,
                   ga.coordinate.latitude, ga.coordinate.longitude)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        os_log("spike.c session failed: %{public}@", log: log, type: .error, error.localizedDescription)
    }

    private func updateHUD(frame: ARFrame) {
        let s = frame.geoTrackingStatus
        var lines: [String] = []
        lines.append("Spike C — Sliding baseline")
        lines.append("AR.GeoTracking.state: \(s.state)")
        lines.append("AR.GeoTracking.accuracy: \(s.accuracy)")
        lines.append("Anchors placed: \(anchors.count)")
        lines.append("")
        lines.append("Tap 'Place anchor here' over a visual landmark.")
        lines.append("Walk a documented block; return; record drift.")
        lines.append("All updates logged via OSLog category 'spike.c.sliding'.")
        hudLabel.text = lines.joined(separator: "\n")
    }
}

// Small helper to extract translation from a 4x4.
private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
