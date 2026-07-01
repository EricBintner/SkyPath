import UIKit
import SceneKit
import ARKit
import CoreLocation

class ARViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    
    // MARK: - Properties
    
    // Delegates
    weak var delegate: ARViewControllerDelegate?
    
    // Views
    var sceneView: ARSCNView!
    private var statsContainerView: UIView!
    private var statusLabel: UILabel!
    private var statsProgressView: UIProgressView!
    
    // Location & AR properties
    private var isLidarDebugMode = false // Set to true to debug occlusion, false for geo-tracking
    private var allLocations: [ARModelLocation] = []
    private var loadedLocations: [String: ARModelLocation] = [:]
    
    // Constants
    private let proximityThreshold: Double = 600.0 // Load models within 600 meters
    private var lastLocationUpdateTime: Date = Date()
    private let updateFrequency: TimeInterval = 1.0
    
    // Model cache to prevent race conditions
    private var modelCache: [String: SCNNode] = [:]
    
    // Occlusion properties
    private var planeNodes: [UUID: SCNNode] = [:]
    private lazy var planeOcclusionMaterial: SCNMaterial = {
        let material = SCNMaterial()
        material.name = "PlaneOcclusionMaterial"
        material.colorBufferWriteMask = [] // Makes the plane invisible
        material.isDoubleSided = true
        return material
    }()
    
    
    // Session persistence properties
    private var hasSavedWorldMap = false // Flag to ensure we only save once per session
    
    // State tracking for logging
    private var previousGeoTrackingState: ARGeoTrackingStatus.State?
    private var previousCameraState: ARCamera.TrackingState = .normal
    
    // Track if geo-tracking is localized
    private var isGeoTrackingLocalized = false
    private var highAccuracyModelPlaced = false // Track if the high-accuracy model has been placed
    private var highAccuracyFrameCounter = 0 // Counter for sustained high accuracy
    private var frameUpdateCounter = 0 // For throttling logs
    private var startARButton: UIButton!
    
    // For Scene Reconstruction Occlusion
    private var meshNodes: [UUID: SCNNode] = [:]
    private lazy var occlusionMaterial: SCNMaterial = {
        let material = SCNMaterial()
        material.name = "OcclusionMaterial_DEBUG_MESH"
        material.diffuse.contents = UIColor.systemYellow.withAlphaComponent(0.4)
        material.lightingModel = .constant
        material.colorBufferWriteMask = .all
        material.isDoubleSided = true
        return material
    }()

    // MARK: - earthFrame hierarchy (M02.2)
    // earthFrame is a child of sceneView.scene.rootNode. Its transform MUST stay
    // identity until the M02.5 transform spec (MERGED-005): ARKit writes each
    // anchor node's transform as if parented to root, so an identity earthFrame
    // makes reparenting visually jump-free. The didSet enforces the invariant.
    private var m02_5CorrectionEnabled = false
    private var earthFrame: SCNNode? {
        didSet {
            if let earthFrame, !m02_5CorrectionEnabled {
                EarthFrameHierarchy.assertIdentity(earthFrame)
            }
        }
    }
    private var anchorsFrame: SCNNode?
    private var occludersFrame: SCNNode?

    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupARView()
        setupStatsOverlay()
        setupStartButton() // Add button setup
        loadLocationData()
        
        // Add observer for orientation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )

        // SPIKE: react to the Info tab's Developer Tools toggle so the
        // floating Spikes button appears/disappears immediately.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(devToolsDidChange),
            name: DevTools.didChangeNotification,
            object: nil
        )
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Run a basic session to show the camera feed. Geo-tracking will be started by the user.
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        sceneView.session.run(configuration)
    }

    // SPIKE: floating Spikes button overlay on the AR screen, gated by
    // DevTools.isEnabled (toggled from the Info tab). Default off, so
    // day-to-day builds and production-shaped runs don't see it.
    // Observes DevTools.didChangeNotification so toggling in the Info tab
    // shows/hides the button immediately on return to AR.
    // grep "// SPIKE:" to find all spike-related code for cleanup later.
    // See docs/phases/Phase02_Spike_Playbook.md.
    private var spikeButton: UIButton?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshSpikeButton()
    }

    @objc private func devToolsDidChange() {
        refreshSpikeButton()
    }

    private func refreshSpikeButton() {
        let shouldShow = DevTools.isEnabled
        if shouldShow {
            if spikeButton == nil { addSpikeButton() }
            spikeButton?.isHidden = false
        } else {
            spikeButton?.isHidden = true
        }
    }

    private func addSpikeButton() {
        // SF Symbol "testtube.2" instead of an emoji; uses UIButton.Configuration
        // which also drops the iOS-15-deprecated contentEdgeInsets API.
        var config = UIButton.Configuration.filled()
        var title = AttributedString("Spikes")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        config.attributedTitle = title
        config.image = UIImage(systemName: "testtube.2")
        config.imagePadding = 6
        config.imagePlacement = .leading
        config.baseBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(presentSpikeMenu), for: .touchUpInside)
        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        spikeButton = button
    }

    @objc private func presentSpikeMenu() {
        let menu = SpikeMenuViewController()
        menu.modalPresentationStyle = .fullScreen
        present(menu, animated: true, completion: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pauseARSession()
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Orientation Handling
    @objc private func orientationDidChange() {
        // Log orientation change but don't reset tracking
        // ARKit should handle orientation changes automatically with gravityAndHeading
        let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation ?? .portrait
        print("📱 Device orientation changed to: \(orientation.rawValue)")
        
        // Force layout update to ensure proper frame alignment
        sceneView.setNeedsLayout()
        sceneView.layoutIfNeeded()
    }
    
    // MARK: - Session Management
    
    /// Pauses the AR session and location updates
    func pauseARSession() {
        print("Pausing AR session")
        sceneView.session.pause()
        LocationManager.shared.stopUpdatingLocation()
    }
    
    /// Resumes the AR session and location updates
    func resumeARSession() {
        print("Resuming AR session")
        // Only resume if the start button is hidden (i.e., AR was previously started)
        if startARButton.isHidden {
            startGeoTrackingSession()
            LocationManager.shared.startUpdatingLocation()
        }
    }
    
    @objc private func didTapStartARButton() {
        print("▶️ User tapped 'Start AR'.")
        startARButton.isHidden = true
        startGeoTrackingSession()
    }

    /// Starts the AR Geo-Tracking session
    func startGeoTrackingSession() {
        print("🚀 Resuming AR session")
        
        // Log current device orientation
        let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation ?? .portrait
        print("📱 Starting AR session with device orientation: \(orientation.rawValue)")
        print("   - Portrait: \(orientation == .portrait)")
        print("   - Landscape: \(orientation.isLandscape)")
        
        guard ARGeoTrackingConfiguration.isSupported else {
            updateStatus("ARGeoTracking NOT SUPPORTED.")
            print("❌ ARGeoTracking is not supported on this device")
            return
        }
        
        // Check availability at current location
        ARGeoTrackingConfiguration.checkAvailability { availability, error in
            if let error = error {
                print("❌ ARGeoTracking availability error: \(error.localizedDescription)")
            } else {
                print("📍 ARGeoTracking availability: \(availability)")
            }
        }
        
        if isLidarDebugMode {
            print("🔬 LIDAR DEBUG MODE: Using ARWorldTrackingConfiguration with Scene Reconstruction.")
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                configuration.sceneReconstruction = .meshWithClassification
                print("✅ Scene reconstruction enabled for debug.")
            } else {
                print("⚠️ Scene reconstruction not supported on this device.")
            }
            
            sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            sceneView.session.delegate = self
            return // Skip the rest of the geo-tracking setup
        }

        let configuration = ARGeoTrackingConfiguration()
        
        // Set to highest resolution format
        let videoFormats = ARGeoTrackingConfiguration.supportedVideoFormats
        if !videoFormats.isEmpty {
            let sortedFormats = videoFormats.sorted {
                $0.imageResolution.width * $0.imageResolution.height > $1.imageResolution.width * $1.imageResolution.height
            }
            
            if let highestResFormat = sortedFormats.first {
                configuration.videoFormat = highestResFormat
            }
        }
        
        // Enable plane detection for better tracking
        configuration.planeDetection = [.horizontal, .vertical]
        // Scene reconstruction setup removed due to API unavailability errors.
        
        // --- THIS IS THE KEY LOGIC ---
        // Determine if we should reset tracking based on session history
        if shouldResetTracking() {
            print("▶️ Starting fresh AR session with tracking reset")
            sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        } else {
            print("▶️ Resuming AR session without tracking reset")
            // Don't reset tracking - this preserves the coordinate system
            sceneView.session.run(configuration, options: [.removeExistingAnchors])
        }
        // --- END KEY LOGIC ---
        
        // Reset our save flag for the new session
        hasSavedWorldMap = false
        
        // Set the session delegate to get geo-tracking updates
        sceneView.session.delegate = self
        
        // Use shared location manager for proper geospatial tracking
        setupSharedLocationManager()
        
        addLighting()
    }
    
    // MARK: - Setup Methods

    private func setupStartButton() {
        startARButton = UIButton(type: .system)
        startARButton.setTitle("Start AR Session", for: .normal)
        startARButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        startARButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        startARButton.setTitleColor(.white, for: .normal)
        startARButton.layer.cornerRadius = 10
        startARButton.translatesAutoresizingMaskIntoConstraints = false
        
        startARButton.addTarget(self, action: #selector(didTapStartARButton), for: .touchUpInside)
        
        view.addSubview(startARButton)
        
        NSLayoutConstraint.activate([
            startARButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startARButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            startARButton.widthAnchor.constraint(equalToConstant: 220),
            startARButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func setupARView() {
        // Create AR view programmatically
        sceneView = ARSCNView()
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.showsStatistics = true
        
        // Add the sceneView to the view hierarchy and constrain it to the edges using Auto Layout.
        // This is the correct way to avoid orientation mismatches.
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(sceneView, at: 0) // Insert behind UI elements like buttons
        
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // Set AR view options
        sceneView.automaticallyUpdatesLighting = true
        sceneView.autoenablesDefaultLighting = true

        // earthFrame hierarchy (M02.2). Idempotent: build once, guard against re-add
        // so a second setupARView() cannot orphan a second hierarchy.
        if earthFrame?.parent == nil {
            let hierarchy = EarthFrameHierarchy.make()
            earthFrame = hierarchy.earthFrame
            anchorsFrame = hierarchy.anchorsFrame
            occludersFrame = hierarchy.occludersFrame
            sceneView.scene.rootNode.addChildNode(hierarchy.earthFrame)
        }

        print("🎥 ARSCNView created and constrained with Auto Layout")
    }
    
    

    private func setupStatsOverlay() {
        // Stats container view
        statsContainerView = UIView()
        statsContainerView.translatesAutoresizingMaskIntoConstraints = false
        statsContainerView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        statsContainerView.layer.cornerRadius = 10
        view.addSubview(statsContainerView)
        
        // Status label in stats container
        statusLabel = UILabel()
        statusLabel.textAlignment = .center
        statusLabel.textColor = .white
        statusLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statsContainerView.addSubview(statusLabel)
        
        // Progress view in stats container
        statsProgressView = UIProgressView(progressViewStyle: .default)
        statsProgressView.translatesAutoresizingMaskIntoConstraints = false
        // Progress tracks loaded-nearby-models / total-nearby. Before
        // updateNearbyModels runs there are zero nearby loaded, so the
        // bar starts empty. (Was previously hardcoded to 0.5, which
        // looked stuck at half during the "Loaded N locations" status.)
        statsProgressView.progress = 0.0
        statsProgressView.progressTintColor = .white
        statsProgressView.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        statsContainerView.addSubview(statsProgressView)
        
        // Position the stats container at the bottom of the view, just above where the bottom border would be
        NSLayoutConstraint.activate([
            statsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statsContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -90),
            statsContainerView.heightAnchor.constraint(equalToConstant: 50),
            
            statusLabel.topAnchor.constraint(equalTo: statsContainerView.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: statsContainerView.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: statsContainerView.trailingAnchor, constant: -10),
            
            statsProgressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            statsProgressView.leadingAnchor.constraint(equalTo: statsContainerView.leadingAnchor, constant: 20),
            statsProgressView.trailingAnchor.constraint(equalTo: statsContainerView.trailingAnchor, constant: -20),
            statsProgressView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }
    
    // MARK: - Location Services
    private func setupSharedLocationManager() {
        print("🌍 Setting up shared location manager for ARKit")
        
        // Use the shared location manager and set up location updates
        LocationManager.shared.locationUpdateHandler = { [weak self] location in
            DispatchQueue.main.async {
                self?.updateNearbyModels(userLocation: location)
            }
        }
        LocationManager.shared.startUpdatingLocation()
    }
    
    // MARK: - Location Data
    private func loadLocationData() {
        // Canonical placement data is webgl-component/models_to_place.json,
        // copied into the bundle's Models/ folder by the "Copy shared data
        // from webgl-component" build phase (see SHARED_DATA.md).
        let jsonFileName = "models_to_place"
        guard let jsonURL = Bundle.main.url(forResource: jsonFileName, withExtension: "json", subdirectory: "Models") else {
            updateStatus("ERROR: Locations JSON file NOT FOUND.")
            return
        }
        
        do {
            let jsonData = try Data(contentsOf: jsonURL)
            let locationData = try JSONDecoder().decode([LocationPoint].self, from: jsonData)
            print("📋 Parsed JSON data - First location model_variant: \(locationData.first?.model_variant ?? "none")")
            allLocations = locationData.map { 
                // Collect column offsets
                var offsets: [Double] = []
                if let offset1 = $0.model_column1_place { offsets.append(offset1) }
                if let offset2 = $0.model_column2_place { offsets.append(offset2) }
                if let offset3 = $0.model_column3_place { offsets.append(offset3) }
                if let offset4 = $0.model_column4_place { offsets.append(offset4) }
                
                let location = ARModelLocation(
                    id: $0.id,
                    coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                    modelName: $0.model_variant,
                    rotation: $0.rotation,
                    tilt: $0.tilt,
                    description: $0.description,
                    distanceToNext: $0.distance_to_next,
                    modelVariant: $0.model_variant,
                    columnModel: $0.model_column,
                    columnOffsets: offsets
                )
                return location
            }
            updateStatus("Loaded \(allLocations.count) locations from JSON.")
            
            // Preload all models to prevent race conditions
            preloadModels()
            
            // Notify the parent controller about the loaded locations
            delegate?.didLoadAllLocations(allLocations)
        } catch {
            updateStatus("ERROR loading locations JSON: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Model Preloading
    private func preloadModels() {
        // Get unique main model names
        let modelNames = Set(allLocations.map { $0.modelName })
        
        // Get unique column model names
        let columnNames = Set(allLocations.compactMap { $0.columnModel })
        
        // Combine all model names
        let allModelNames = modelNames.union(columnNames)
        
        for name in allModelNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else {
                print("⚠️ Model file not found: \(name).usdz")
                continue
            }
            do {
                let scene = try SCNScene(url: url, options: nil)
                let node = SCNNode()
                for child in scene.rootNode.childNodes {
                    node.addChildNode(child.clone())
                }
                modelCache[name] = node
                print("✅ Cached model: \(name)")
            } catch {
                print("❌ Failed to cache model \(name): \(error)")
            }
        }
        print("🎯 Model caching complete: \(modelCache.count) models cached")
    }
    
    // MARK: - Session State Persistence
    // Since ARGeoTrackingConfiguration doesn't support world maps,
    // we'll save a flag to prevent resetting on subsequent launches
    private func saveSessionState() {
        UserDefaults.standard.set(true, forKey: "hasEstablishedGeoTracking")
        UserDefaults.standard.set(Date(), forKey: "lastGeoTrackingDate")
        print("✅ Saved session state")
        hasSavedWorldMap = true
    }
    
    private func shouldResetTracking() -> Bool {
        // Check if we have a previous session
        guard UserDefaults.standard.bool(forKey: "hasEstablishedGeoTracking") else {
            print("🗺️ No previous geo-tracking session found.")
            return true
        }
        
        // Check if the last session was recent (within 24 hours)
        if let lastDate = UserDefaults.standard.object(forKey: "lastGeoTrackingDate") as? Date {
            let hoursSinceLastSession = Date().timeIntervalSince(lastDate) / 3600
            if hoursSinceLastSession > 24 {
                print("⏰ Last session was \(Int(hoursSinceLastSession)) hours ago. Will reset tracking.")
                return true
            }
        }
        
        print("✅ Found recent geo-tracking session. Will not reset tracking.")
        return false
    }
    
    func clearSessionState() {
        UserDefaults.standard.removeObject(forKey: "hasEstablishedGeoTracking")
        UserDefaults.standard.removeObject(forKey: "lastGeoTrackingDate")
        print("🗑️ Cleared session state")
    }
    

    // MARK: - Proximity Management
    private func updateNearbyModels(userLocation: CLLocation) {
        // If we have already placed the high-accuracy model, stop checking for other nearby models.
        guard !highAccuracyModelPlaced else {
            return
        }
        let nearbyLocationsToLoad = allLocations.filter { modelLocation in
            if loadedLocations[modelLocation.id] != nil {
                return false
            }
            let locationCoordinate = modelLocation.coordinate
            let locationObj = CLLocation(latitude: locationCoordinate.latitude, longitude: locationCoordinate.longitude)
            let distance = userLocation.distance(from: locationObj)
            return distance <= proximityThreshold
        }

        for location in nearbyLocationsToLoad {
            if loadedLocations[location.id] == nil {
                loadModelAtLocation(location)
            }
        }
        
        var locationsToUnloadIDs: [String] = []
        for (id, loadedLoc) in loadedLocations {
            guard let anchor = loadedLoc.anchor else { continue }
            let modelCLLocation = CLLocation(latitude: anchor.coordinate.latitude, longitude: anchor.coordinate.longitude)
            let distance = userLocation.distance(from: modelCLLocation)
            if distance > proximityThreshold * 1.2 {
                locationsToUnloadIDs.append(id)
            }
        }
        
        for locationID in locationsToUnloadIDs {
            unloadModel(id: locationID)
        }
        
        // Update progress bar to show percentage of locations loaded vs total nearby
        let nearbyTotal = nearbyLocationsToLoad.count + loadedLocations.count
        if nearbyTotal > 0 {
            let loadedPercentage = Float(loadedLocations.count) / Float(nearbyTotal)
            statsProgressView.progress = loadedPercentage
        }
        
        updateStatus("Nearby models: \(loadedLocations.count)")
        
        // Notify the parent controller about updated nearby locations
        delegate?.didUpdateNearbyLocations(Array(loadedLocations.values))
    }
    
    // MARK: - Virtual Model Loading/Unloading
    private func loadModelAtLocation(_ location: ARModelLocation) {
        // Add a guard to ensure we are localized before adding an anchor
        guard isGeoTrackingLocalized else {
            print("⚠️ Waiting for geo tracking to be localized before adding anchor for: \(location.id)")
            return
        }
        
        guard loadedLocations[location.id] == nil else {
            return
        }
        
        // Create anchor with proper coordinate validation
        guard CLLocationCoordinate2DIsValid(location.coordinate) else {
            print("❌ Invalid coordinate for location: \(location.id)")
            return
        }
        
        let geoAnchor = ARGeoAnchor(name: location.id, coordinate: location.coordinate)
        
        var mutableLocation = location
        mutableLocation.anchor = geoAnchor
        loadedLocations[location.id] = mutableLocation
        
        sceneView.session.add(anchor: geoAnchor)
        print("📱 Added geo anchor for: \(location.id) at \(location.coordinate)")
    }
    
        // MARK: - ARSCNViewDelegate
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            // For horizontal planes (like the ground), create a massive occluding plane.
            if planeAnchor.alignment == .horizontal {
                print("✅ Adding large horizontal occlusion plane.")
                let plane = SCNPlane(width: 1000, height: 1000)
                plane.materials = [planeOcclusionMaterial]
                
                let planeNode = SCNNode(geometry: plane)
                planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
                // SCNPlane is vertical by default, so rotate it to be horizontal.
                planeNode.transform = SCNMatrix4MakeRotation(-Float.pi / 2, 1, 0, 0)
                
                node.addChildNode(planeNode)
                planeNodes[planeAnchor.identifier] = planeNode
            }
            return // We've handled the plane anchor, so we can exit.
        }
        if let meshAnchor = anchor as? ARMeshAnchor {
            print("📦 LIDAR MESH: Adding new mesh anchor: \(meshAnchor.identifier)")
            let meshGeometry = SCNGeometry(arMeshGeometry: meshAnchor.geometry, fillMaterial: occlusionMaterial)
            let meshNode = SCNNode(geometry: meshGeometry)
            meshNodes[meshAnchor.identifier] = meshNode
            node.addChildNode(meshNode)
            return
        }


        guard let geoAnchor = anchor as? ARGeoAnchor, let locationID = geoAnchor.name else {
            // If it's not a geo anchor or has no name, we can't process it here.
            // Other anchor types (like mesh anchors, if re-enabled) would be handled elsewhere or ignored.
            // print("ℹ️ Non-geo anchor or geo anchor without name added: \(anchor.identifier)")
            return
        }

        // Find the ARModelLocation data from our definitive list using the anchor's name as ID.
        guard let locationData = allLocations.first(where: { $0.id == locationID }) else {
            print("❌ Could not find ARModelLocation in 'allLocations' for anchor ID: \(locationID)")
            return
        }
        
        print("✅ Renderer adding node for ARGeoAnchor: \(locationData.id)")

        // Get the pre-loaded model from the cache.
        guard let cachedModel = modelCache[locationData.modelName] else {
            print("❌ Model '\(locationData.modelName)' not found in cache for \(locationData.id). Adding placeholder.")
            let placeholder = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.1))
            placeholder.geometry?.firstMaterial?.diffuse.contents = UIColor.red
            node.addChildNode(placeholder)
            // Still update loadedLocations so we know we tried to load this anchor.
            loadedLocations[locationID] = locationData
            return
        }
        
        // Create the visual content node.
        let contentNode = createContentNode(for: locationData, cachedModel: cachedModel)
        
        // Configure the node for occlusion (good practice).
        configureVirtualNodeForOcclusion(contentNode)
        
        // Add the content node to the ARKit-provided node for this anchor.
        node.addChildNode(contentNode)
        
        // Update our tracking dictionary with the ARModelLocation instance.
        // This ensures loadedLocations correctly stores the ARModelLocation object.
        loadedLocations[locationID] = locationData
        print("📦 Added and loaded model for \(locationData.id) into the scene and loadedLocations.")
        
        // Update the loaded location to reference the node
        if var location = loadedLocations[locationData.id] {
            location.node = node
            loadedLocations[locationData.id] = location
        }
        
        print("🎯 Model placed at geo anchor: \(locationData.id)")
    }
    

    private func createContentNode(for locationData: ARModelLocation, cachedModel: SCNNode) -> SCNNode {
        // Create a container node that will handle the rotation
        let rotationContainerNode = SCNNode()
        rotationContainerNode.name = "rotation_container_\(locationData.id)"
        
        // Clone the cached model and add it to the container
        let modelClone = cachedModel.clone()
        rotationContainerNode.addChildNode(modelClone)
        
        // Apply rotations
        let tiltDegrees = Float(locationData.tilt)
        let tiltRadians = tiltDegrees * .pi / 180.0
        let totalPitch = CGFloat(tiltRadians)
        
        let headingDegrees = Float(locationData.rotation)
        let headingRadians = headingDegrees * .pi / 180.0
        
        // The model needs a -270 degree offset to align properly with the street
        // This accounts for the model's intrinsic orientation and the geographic to ARKit conversion
        let modelCorrection = -3 * CGFloat.pi / 2 // -270 degrees
        let totalYaw = -CGFloat(headingRadians) + modelCorrection
        
        rotationContainerNode.eulerAngles = SCNVector3(totalPitch, totalYaw, 0)
        
        print("🔄 Rotation Debug:")
        print("   JSON rotation: \(headingDegrees)°")
        print("   Model correction: -270°")
        print("   Final Y rotation: \(totalYaw * 180 / .pi)°")
        print("   Tilt: \(tiltDegrees)°")
        
        // Add column models if specified
        if let columnModelName = locationData.columnModel,
           let cachedColumnModel = modelCache[columnModelName] {
            
            for (index, offset) in locationData.columnOffsets.enumerated() {
                let columnClone = cachedColumnModel.clone()
                columnClone.name = "column_\(index + 1)_\(locationData.id)"
                columnClone.position = SCNVector3(0, 0, Float(offset))
                rotationContainerNode.addChildNode(columnClone)
            }
            
            print("🏛️ Columns: Added \(locationData.columnOffsets.count) columns with Z offsets: \(locationData.columnOffsets)")
        }
        
        return rotationContainerNode
    }

    private func unloadModel(id: String) {
        guard let location = loadedLocations.removeValue(forKey: id) else {
            return
        }
        if let anchor = location.anchor {
            sceneView.session.remove(anchor: anchor)
        } else if let node = location.node {
            node.removeFromParentNode()
        }
    }
    
    // MARK: - Public Methods
    func focusOnLocation(id: String) {
        // Find the location in our allLocations array
        guard let location = allLocations.first(where: { $0.id == id }) else {
            print("⚠️ Location with ID \(id) not found")
            return
        }
        
        // If not already loaded, load it
        if loadedLocations[id] == nil {
            loadModelAtLocation(location)
        }
        
        // Update status to indicate focus
        updateStatus("Focusing on: \(location.description)")
        
        // Optionally add some visual indicator or animation to highlight the location
        if let node = loadedLocations[id]?.node {
            // Create a pulse animation or highlight
            let pulseAction = SCNAction.sequence([
                SCNAction.scale(to: 1.5, duration: 0.5),
                SCNAction.scale(to: 1.0, duration: 0.5)
            ])
            
            let repeatPulse = SCNAction.repeat(pulseAction, count: 3)
            node.runAction(repeatPulse)
        }
    }
    
    // MARK: - Utility Methods
    private func addLighting() {
        sceneView.autoenablesDefaultLighting = true
    }
    
    func updateStatus(_ message: String) {
        DispatchQueue.main.async {
            self.statusLabel.text = message
        }
    }
    
    private func configureVirtualNodeForOcclusion(_ node: SCNNode) {
        node.enumerateHierarchy { (childNode, _) in
            if let geometry = childNode.geometry {
                for material in geometry.materials {
                    material.writesToDepthBuffer = true
                    material.readsFromDepthBuffer = true
                }
            }
        }
    }


    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor, let planeNode = planeNodes[planeAnchor.identifier] {
            // Update the plane's position as ARKit refines it.
            planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
            // The size remains fixed and large, so no geometry update is needed.
        }
        if let meshAnchor = anchor as? ARMeshAnchor, let meshNode = meshNodes[meshAnchor.identifier] {
            print("🔄 LIDAR MESH: Updating mesh anchor: \(meshAnchor.identifier)")
            // Directly update the geometry of the existing mesh node.
            let updatedMeshGeometry = SCNGeometry(arMeshGeometry: meshAnchor.geometry, fillMaterial: occlusionMaterial)
            meshNode.geometry = updatedMeshGeometry

        } else if let geoAnchor = anchor as? ARGeoAnchor,
                  let locationID = geoAnchor.name,
                  allLocations.first(where: { $0.id == locationID }) != nil {
            
            // The node's visibility should reflect the anchor's tracking state.
            node.isHidden = !geoAnchor.isTracked

            if node.isHidden {
                print("⚠️ Geo anchor for \(geoAnchor.name ?? "unknown") lost tracking and is hidden.")
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        if let geoAnchor = anchor as? ARGeoAnchor {
            if let idToRemove = loadedLocations.first(where: { $0.value.anchor?.identifier == geoAnchor.identifier })?.key {
                loadedLocations.removeValue(forKey: idToRemove)
            }
        } else if let planeAnchor = anchor as? ARPlaneAnchor {
            print("🗑️ Removing occlusion plane: \(planeAnchor.identifier)")
            planeNodes.removeValue(forKey: planeAnchor.identifier)
        } else if let meshAnchor = anchor as? ARMeshAnchor {
            print("🗑️ LIDAR MESH: Removing mesh anchor: \(meshAnchor.identifier)")
            meshNodes.removeValue(forKey: meshAnchor.identifier)
        }
    }
    
    // MARK: - CLLocationManagerDelegate

    
    // MARK: - ARSession Delegate
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ AR Session error: \(error.localizedDescription)")
        updateStatus("AR Session error: \(error.localizedDescription)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("⚠️ AR Session interrupted")
        updateStatus("AR Session interrupted.")
    }

    // ARKit selector is session:didChangeGeoTrackingStatus: (iOS 14+).
    // Was previously named `didUpdate` here, which silently no-ops because
    // the selector never matches — localization status never reached this code.
    func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {
        var statusMessage = ""
        
        // Use a switch to handle all possible states and provide detailed feedback.
        switch geoTrackingStatus.state {
        case .notAvailable:
            statusMessage = "GeoTracking: Not Available"
            isGeoTrackingLocalized = false
            
        case .initializing:
            statusMessage = "GeoTracking: Initializing..."
            isGeoTrackingLocalized = false
            
        case .localizing:
            statusMessage = "GeoTracking: Localizing... (Accuracy: \(geoTrackingStatus.accuracy.rawValue))"
            isGeoTrackingLocalized = false
            
        case .localized:
            statusMessage = "GeoTracking: Localized (Accuracy: \(geoTrackingStatus.accuracy.rawValue))"
            isGeoTrackingLocalized = true
            // This is the state where anchors should be stable.
            // Once we are localized with high accuracy, we can be confident.
            if geoTrackingStatus.accuracy == .high {
                print("✅ --- GEO-TRACKING IS FULLY LOCALIZED WITH HIGH ACCURACY --- ✅")
                // You could trigger model loading here if it wasn't already happening.
            }
            
        @unknown default:
            statusMessage = "GeoTracking: Unknown State"
            isGeoTrackingLocalized = false
        }
        
        // Only print updates when the state actually changes to avoid spamming the console.
        if geoTrackingStatus.state != previousGeoTrackingState {
            print("--- GEO-TRACKING STATUS UPDATE ---")
            print("    STATE: \(statusMessage)")
            print("------------------------------------")
            previousGeoTrackingState = geoTrackingStatus.state
        }
        
        updateStatus(statusMessage)
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("✅ AR Session interruption ended")
        updateStatus("AR Session interruption ended.")
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // --- Geo-Tracking Status Update ---
        if let geoTrackingStatus = frame.geoTrackingStatus {
            var statusMessage = ""
            
            switch geoTrackingStatus.state {
            case .initializing:
                statusMessage = "AR GeoTracking: Initializing..."
                isGeoTrackingLocalized = false
                highAccuracyFrameCounter = 0
                if previousGeoTrackingState != .initializing {
                    print("🔄 GeoTracking: Initializing")
                    previousGeoTrackingState = .initializing
                }
                
            case .localizing:
                statusMessage = "AR GeoTracking: Localizing..."
                isGeoTrackingLocalized = false
                highAccuracyFrameCounter = 0
                if previousGeoTrackingState != .localizing {
                    print("🔍 GeoTracking: Localizing")
                    previousGeoTrackingState = .localizing
                }
                
            case .localized:
                let accuracy = geoTrackingStatus.accuracy
                statusMessage = "AR GeoTracking: Localized ✓"
                
                switch accuracy {
                case .high:
                    statusMessage += " (High Accuracy)"
                    highAccuracyFrameCounter += 1
                    
                    let confidenceThreshold = 90 // ~1.5 seconds at 60fps
                    if highAccuracyFrameCounter > confidenceThreshold && !highAccuracyModelPlaced, let userLocation = LocationManager.shared.currentLocation {
                        print("✅ Sustained high accuracy lock achieved! Placing definitive models.")
                        
                        let sortedLocations = allLocations.sorted { loc1, loc2 in
                            userLocation.distance(from: CLLocation(latitude: loc1.coordinate.latitude, longitude: loc1.coordinate.longitude)) <
                            userLocation.distance(from: CLLocation(latitude: loc2.coordinate.latitude, longitude: loc2.coordinate.longitude))
                        }
                        let twoClosestLocations = sortedLocations.prefix(2)
                        
                        if !twoClosestLocations.isEmpty {
                            print("🎯 Top \(twoClosestLocations.count) closest locations found.")
                            sceneView.session.currentFrame?.anchors.forEach { anchor in
                                if anchor is ARGeoAnchor { sceneView.session.remove(anchor: anchor) }
                            }
                            loadedLocations.removeAll()
                            print("🗑️ Removed all previous geo-anchors.")
                            
                            for location in twoClosestLocations {
                                print("📍 Placing high-accuracy model for: \(location.id)")
                                loadModelAtLocation(location)
                            }
                            highAccuracyModelPlaced = true
                        }
                    }
                    
                default: // medium, low, undetermined
                    statusMessage += " (Accuracy: \(String(describing: accuracy)))"
                    highAccuracyFrameCounter = 0 // Reset confidence if accuracy drops
                }
                
                if !isGeoTrackingLocalized {
                    isGeoTrackingLocalized = true
                    print("✅ GeoTracking: Localized - accuracy: \(accuracy)")
                    if let userLocation = LocationManager.shared.currentLocation {
                        updateNearbyModels(userLocation: userLocation)
                    }
                }
                if previousGeoTrackingState != .localized { previousGeoTrackingState = .localized }
                
            case .notAvailable:
                statusMessage = "AR GeoTracking: Not Available"
                isGeoTrackingLocalized = false
                highAccuracyFrameCounter = 0
                if previousGeoTrackingState != .notAvailable {
                    print("❌ GeoTracking: Not Available")
                    previousGeoTrackingState = .notAvailable
                }
                
            @unknown default:
                statusMessage = "AR GeoTracking: Unknown state"
                isGeoTrackingLocalized = false
                highAccuracyFrameCounter = 0
            }
            
            updateStatus(statusMessage)
        }
        
        // --- Camera Tracking State Update ---
        if frame.camera.trackingState != previousCameraState {
            switch frame.camera.trackingState {
            case .normal:
                if previousCameraState != .normal { print("✅ Camera tracking restored") }
            case .notAvailable:
                print("⚠️ Camera tracking not available")
            case .limited(let reason):
                print("⚠️ Camera tracking limited: \(reason)")
            }
            previousCameraState = frame.camera.trackingState
        }
    }
}

// MARK: - SCNNode Extensions
extension SCNNode {
    var worldPosition: SCNVector3 {
        // Get the world transform matrix
        let transform = self.presentation.worldTransform
        // Extract position from the transform matrix
        return SCNVector3(transform.m41, transform.m42, transform.m43)
    }
}
