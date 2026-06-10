//
//  SpikeAViewController.swift
//  Phase 02 — M02.0 spike code. Deleted after spikes complete.
//
//  Spike A: confirm ARGeoTrackingConfiguration + GARSession (Geospatial +
//  Streetscape Geometry) can run together on iOS. This is the riskiest
//  unknown in the Phase 02 plan. See Phase02_Spike_Playbook.md §1 for the
//  field procedure and pass criteria.
//
//  Requires:
//  - ARCore iOS SDK added via SPM (https://github.com/google-ar/arcore-ios-sdk)
//  - Google Cloud API key with ARCore API enabled, restricted to this
//    bundle ID, exposed via Info.plist as ARCORE_API_KEY
//

import UIKit
import ARKit
import SceneKit
import ARCore   // GARSession, GAREarth, GARSessionConfiguration, etc.

final class SpikeAViewController: UIViewController, ARSessionDelegate {

    // MARK: - UI

    private let sceneView = ARSCNView()
    private let hudLabel = UILabel()
    private let restartButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)
    private let fallbackSwitch = UISwitch()
    private let fallbackLabel = UILabel()

    // MARK: - Sessions

    private var garSession: GARSession?

    // MARK: - Tracking metrics

    private var spikeStartTime: Date?
    private var arGeoFirstLocalizedAt: Date?
    private var garEarthFirstEnabledAt: Date?
    private var firstStreetscapeAt: Date?
    private var lastStreetscapeCount: Int = 0

    // FALLBACK: when true, run ARWorldTrackingConfiguration instead of
    // ARGeoTrackingConfiguration. Toggle via the on-screen switch. This is
    // the documented Phase 02 §3 fallback path.
    private var useFallbackConfig = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSceneView()
        setupHUD()
        setupControls()
        initGARSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // MARK: - Setup

    private func setupSceneView() {
        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        view.addSubview(sceneView)
    }

    private func setupHUD() {
        hudLabel.translatesAutoresizingMaskIntoConstraints = false
        hudLabel.numberOfLines = 0
        hudLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hudLabel.textColor = .white
        hudLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        hudLabel.text = "Spike A — starting…"
        view.addSubview(hudLabel)
        NSLayoutConstraint.activate([
            hudLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hudLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            hudLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
        ])
    }

    private func setupControls() {
        restartButton.setTitle("Restart", for: .normal)
        restartButton.setTitleColor(.white, for: .normal)
        restartButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        restartButton.layer.cornerRadius = 8
        restartButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        restartButton.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)
        restartButton.translatesAutoresizingMaskIntoConstraints = false

        dismissButton.setTitle("Done", for: .normal)
        dismissButton.setTitleColor(.white, for: .normal)
        dismissButton.backgroundColor = UIColor.darkGray.withAlphaComponent(0.85)
        dismissButton.layer.cornerRadius = 8
        dismissButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false

        fallbackLabel.text = "Fallback (ARWorldTracking)"
        fallbackLabel.textColor = .white
        fallbackLabel.font = .systemFont(ofSize: 13)
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false

        fallbackSwitch.isOn = false
        fallbackSwitch.addTarget(self, action: #selector(fallbackToggled), for: .valueChanged)
        fallbackSwitch.translatesAutoresizingMaskIntoConstraints = false

        let bottomStack = UIStackView(arrangedSubviews: [fallbackLabel, fallbackSwitch, restartButton, dismissButton])
        bottomStack.axis = .horizontal
        bottomStack.spacing = 12
        bottomStack.alignment = .center
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomStack)
        NSLayoutConstraint.activate([
            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            bottomStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    // MARK: - GARSession init

    private func initGARSession() {
        guard let apiKey = Self.apiKey() else {
            hudLabel.text = "ERROR: ARCORE_API_KEY missing.\nSee Phase02_Spike_Playbook.md §0.4."
            return
        }
        do {
            garSession = try GARSession(apiKey: apiKey, bundleIdentifier: Bundle.main.bundleIdentifier)
        } catch {
            hudLabel.text = "GARSession init failed:\n\(error.localizedDescription)"
            garSession = nil
            return
        }

        let config = GARSessionConfiguration()
        config.geospatialMode = .enabled
        config.streetscapeGeometryMode = .enabled

        var configError: NSError?
        garSession?.setConfiguration(config, error: &configError)
        if let configError = configError {
            hudLabel.text = "GARSession setConfiguration failed:\n\(configError.localizedDescription)"
            garSession = nil
        }
    }

    // MARK: - Session control

    private func startSession() {
        spikeStartTime = Date()
        arGeoFirstLocalizedAt = nil
        garEarthFirstEnabledAt = nil
        firstStreetscapeAt = nil
        lastStreetscapeCount = 0

        let config: ARConfiguration
        if useFallbackConfig {
            // FALLBACK: ARWorldTrackingConfiguration path.
            let world = ARWorldTrackingConfiguration()
            world.worldAlignment = .gravityAndHeading
            config = world
            NSLog("[SpikeA] Starting ARWorldTrackingConfiguration (fallback)")
        } else {
            guard ARGeoTrackingConfiguration.isSupported else {
                hudLabel.text = "ARGeoTrackingConfiguration unsupported on this device.\nFlip the Fallback switch to test ARWorldTracking + GARSession."
                return
            }
            // ARGeoTrackingConfiguration.worldAlignment is unavailable in iOS 18+
            // (the framework forces .gravityAndHeading). Just construct the config.
            let geo = ARGeoTrackingConfiguration()
            config = geo
            NSLog("[SpikeA] Starting ARGeoTrackingConfiguration (primary)")
        }
        sceneView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
    }

    // MARK: - Actions

    @objc private func restartTapped() {
        sceneView.session.pause()
        initGARSession()
        startSession()
    }

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }

    @objc private func fallbackToggled() {
        useFallbackConfig = fallbackSwitch.isOn
        restartTapped()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Feed GARSession every frame.
        if let gar = garSession {
            do {
                let garFrame = try gar.update(frame)
                // Streetscape geometries snapshot for HUD.
                let count = garFrame.streetscapeGeometries?.count ?? 0
                if count > 0, firstStreetscapeAt == nil {
                    firstStreetscapeAt = Date()
                }
                lastStreetscapeCount = count
            } catch {
                NSLog("[SpikeA] GARSession.update threw: \(error)")
            }
        }
        updateHUD()
    }

    func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {
        // ARKit selector is session:didChangeGeoTrackingStatus: (iOS 14+).
        // Using `didUpdate` here silently no-ops because the selector never matches.
        if geoTrackingStatus.state == .localized, arGeoFirstLocalizedAt == nil {
            arGeoFirstLocalizedAt = Date()
            let elapsed = arGeoFirstLocalizedAt!.timeIntervalSince(spikeStartTime ?? Date())
            NSLog("[SpikeA] AR.GeoTracking localized at +%.2fs accuracy=%@", elapsed, String(describing: geoTrackingStatus.accuracy))
        }
        updateHUD()
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        NSLog("[SpikeA] ARSession failed: \(error)")
        hudLabel.text = "ARSession failed:\n\(error.localizedDescription)"
    }

    // MARK: - HUD

    private func updateHUD() {
        guard let start = spikeStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        var lines: [String] = []
        lines.append("Spike A — Pose stack coexistence")
        lines.append(String(format: "Config: %@", useFallbackConfig ? "ARWorldTracking (FALLBACK)" : "ARGeoTracking (primary)"))
        lines.append(String(format: "Elapsed: %.1fs", elapsed))
        lines.append("")

        // Apple GeoTracking
        if !useFallbackConfig, let frame = sceneView.session.currentFrame {
            if let s = frame.geoTrackingStatus {
                lines.append("AR.GeoTracking.state: \(s.state)")
                lines.append("AR.GeoTracking.accuracy: \(s.accuracy)")
                if let t = arGeoFirstLocalizedAt {
                    lines.append(String(format: "  localized at: +%.1fs", t.timeIntervalSince(start)))
                }
            } else {
                lines.append("AR.GeoTracking: awaiting status")
            }
        } else if useFallbackConfig {
            lines.append("AR.GeoTracking: disabled (fallback)")
        } else {
            lines.append("AR.GeoTracking: awaiting first frame")
        }
        lines.append("")

        // Google Geospatial
        if let gar = garSession {
            // gar.earth can be nil in some SDK versions before the session
            // is ready; treat as transient and print a placeholder rather
            // than crashing on a force-unwrap (Playbook §4.5).
            if let earth = gar.earth {
                lines.append("GAR.Earth.state: \(earth.earthState)")
                if earth.earthState == GAREarthState.enabled, garEarthFirstEnabledAt == nil {
                    garEarthFirstEnabledAt = Date()
                }
                if let t = garEarthFirstEnabledAt {
                    lines.append(String(format: "  enabled at: +%.1fs", t.timeIntervalSince(start)))
                }
                if let xform = earth.cameraGeospatialTransform {
                    lines.append(String(format: "  yaw accuracy: %.1f°", xform.orientationYawAccuracy))
                    lines.append(String(format: "  horizontal accuracy: %.1f m", xform.horizontalAccuracy))
                } else {
                    lines.append("  camera transform: nil")
                }
            } else {
                lines.append("GAR.Earth: not ready yet")
            }
            lines.append("Streetscape geometries: \(lastStreetscapeCount)")
            if let t = firstStreetscapeAt {
                lines.append(String(format: "  first arrived at: +%.1fs", t.timeIntervalSince(start)))
            }
        } else {
            lines.append("GARSession: NOT INITIALIZED")
        }

        // Pass criteria
        lines.append("")
        let arOK = useFallbackConfig || arGeoFirstLocalizedAt != nil
        let garOK = garEarthFirstEnabledAt != nil
        let streetOK = lastStreetscapeCount > 0
        lines.append("Pass criteria (within 60–90s):")
        lines.append("  [\(arOK ? "✓" : " ")] AR.GeoTracking localized (or fallback)")
        lines.append("  [\(garOK ? "✓" : " ")] GAR.Earth enabled")
        lines.append("  [\(streetOK ? "✓" : " ")] Streetscape geometries ≥ 1")

        hudLabel.text = lines.joined(separator: "\n")
    }

    // MARK: - API key resolution

    private static func apiKey() -> String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: "ARCORE_API_KEY") as? String,
           !key.isEmpty, key != "$(ARCORE_API_KEY)" {
            return key
        }
        // HACK: paste your key here for quick branch-only testing if Info.plist
        // wiring isn't set up yet. Never commit a real key — this branch is
        // throwaway but the file still lives on origin.
        // return "AIzaSyExampleReplaceMe"
        return nil
    }
}
