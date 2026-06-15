import UIKit
import CoreLocation
import ARKit
import MapKit

class ViewController: UIViewController, ARViewControllerDelegate, LocationsViewControllerDelegate, MapViewControllerDelegate {
    
    // MARK: - Properties edit
    
    // Navigation tracking
    private enum ViewState {
        case arView, listView, mapView, infoView
    }
    private var currentViewState: ViewState = .arView
    
    // UI Elements
    private var topContainerView: UIView!
    private var bottomContainerView: UIView!
    private var leftContainerView: UIView!
    private var rightContainerView: UIView!
    private var overlayContainer: UIView!
    
    // Navigation buttons
    private var arButton: UIButton!
    private var mapButton: UIButton!
    private var listButton: UIButton!
    private var infoButton: UIButton!
    private var buttonsStackView: UIStackView!
    
    // Container views for each section
    private var arContainerView: UIView!
    private var locationsContainerView: UIView!
    private var mapContainerView: UIView!
    private var infoContainerView: UIView!
    
    // Child view controllers
    private var arViewController: ARViewController!
    private var locationsViewController: LocationsViewController!
    private var mapViewController: MapViewController!
    private var infoViewController: InfoViewController!
    
    // Constraints to update on orientation change
    private var topHeightConstraint: NSLayoutConstraint?
    private var bottomHeightConstraint: NSLayoutConstraint?
    
    // Shared data among view controllers
    private var allLocations: [ARModelLocation] = []
    private var nearbyLocations: [ARModelLocation] = []
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("📱 Device size: \(UIScreen.main.bounds)")
        print("📱 View size: \(view.bounds)")
        
        // Setup visual UI elements (frame and navigation)
        setupVisualUIElements()
        
        // Setup container views
        setupContainerViews()
        
        // Setup AR and Map view controllers immediately - they're most commonly used
        setupARViewController()
        setupMapViewController()  // Initialize Map controller at startup
        mapViewInitialized = true // Mark as initialized
        mapContainerView.isHidden = true // But keep it hidden initially
        
        // Add orientation change observer
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(orientationChanged),
                                              name: UIDevice.orientationDidChangeNotification,
                                              object: nil)
        
        // Initial layout adjustment based on current orientation
        adjustLayoutForOrientation()
        
        // Start with the AR view selected
        arContainerView.isHidden = false
        currentViewState = .arView
        updateButtonAppearance(activeButton: arButton)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup Methods
    private func setupVisualUIElements() {
        // Create a transparent overlay for UI
        let overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = .clear
        view.addSubview(overlay)
        overlayContainer = overlay
        
        // Create a frame that wraps around the content
        let frameWidth: CGFloat = 5.0
        
        // Top frame
        let topFrame = UIView()
        topFrame.translatesAutoresizingMaskIntoConstraints = false
        topFrame.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        overlay.addSubview(topFrame)
        topContainerView = topFrame
        
        // Bottom frame
        let bottomFrame = UIView()
        bottomFrame.translatesAutoresizingMaskIntoConstraints = false
        bottomFrame.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        overlay.addSubview(bottomFrame)
        bottomContainerView = bottomFrame
        
        // Left frame
        let leftFrame = UIView()
        leftFrame.translatesAutoresizingMaskIntoConstraints = false
        leftFrame.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        overlay.addSubview(leftFrame)
        leftContainerView = leftFrame
        
        // Right frame
        let rightFrame = UIView()
        rightFrame.translatesAutoresizingMaskIntoConstraints = false
        rightFrame.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        overlay.addSubview(rightFrame)
        rightContainerView = rightFrame
        
        // Create constraints with stored references for later adjustment
        topHeightConstraint = topFrame.heightAnchor.constraint(equalToConstant: 60)
        bottomHeightConstraint = bottomFrame.heightAnchor.constraint(equalToConstant: 80)
        
        // Set up constraints to create a complete frame around the content
        NSLayoutConstraint.activate([
            // Top frame
            topFrame.topAnchor.constraint(equalTo: overlay.topAnchor),
            topFrame.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            topFrame.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            topHeightConstraint!,
            
            // Bottom frame
            bottomFrame.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
            bottomFrame.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            bottomFrame.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            bottomHeightConstraint!,
            
            // Left frame
            leftFrame.topAnchor.constraint(equalTo: topFrame.bottomAnchor),
            leftFrame.bottomAnchor.constraint(equalTo: bottomFrame.topAnchor),
            leftFrame.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            leftFrame.widthAnchor.constraint(equalToConstant: frameWidth),
            
            // Right frame
            rightFrame.topAnchor.constraint(equalTo: topFrame.bottomAnchor),
            rightFrame.bottomAnchor.constraint(equalTo: bottomFrame.topAnchor),
            rightFrame.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            rightFrame.widthAnchor.constraint(equalToConstant: frameWidth)
        ])
        
        // Setup navigation buttons
        setupNavigationButtons(in: bottomFrame)
    }
    
    private func setupContainerViews() {
        // Create container views for each section
        arContainerView = UIView()
        locationsContainerView = UIView()
        mapContainerView = UIView()
        infoContainerView = UIView()
        
        // Add containers to main view
        for container in [arContainerView!, locationsContainerView!, mapContainerView!, infoContainerView!] {
            container.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(container)
            
            // Set up constraints for containers
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: topContainerView.bottomAnchor),
                container.leadingAnchor.constraint(equalTo: leftContainerView.trailingAnchor),
                container.trailingAnchor.constraint(equalTo: rightContainerView.leadingAnchor),
                container.bottomAnchor.constraint(equalTo: bottomContainerView.topAnchor)
            ])
            
            // Hide all containers initially
            container.isHidden = true
        }
    }
    
    // Split setup into individual methods for lazy loading
    private func setupARViewController() {
        // Initialize AR View Controller
        arViewController = ARViewController()
        arViewController.delegate = self
        addChild(arViewController)
        arContainerView.addSubview(arViewController.view)

        // Use Auto Layout to constrain the child view controller's view to the container's bounds.
        // This is the correct way to handle view controller containment and avoid orientation bugs.
        arViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            arViewController.view.topAnchor.constraint(equalTo: arContainerView.topAnchor),
            arViewController.view.bottomAnchor.constraint(equalTo: arContainerView.bottomAnchor),
            arViewController.view.leadingAnchor.constraint(equalTo: arContainerView.leadingAnchor),
            arViewController.view.trailingAnchor.constraint(equalTo: arContainerView.trailingAnchor)
        ])
        
        // Use a local variable of the correct type to ensure type safety
        let arDelegate: ARViewControllerDelegate = self
        arViewController.delegate = arDelegate
        
        arViewController.didMove(toParent: self)
        print("AR View Controller initialized")
    }
    
    private func setupLocationsViewController() {
        // Initialize Locations View Controller
        locationsViewController = LocationsViewController()
        addChild(locationsViewController)
        locationsContainerView.addSubview(locationsViewController.view)
        locationsViewController.view.frame = locationsContainerView.bounds
        locationsViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Use a local variable of the correct type to ensure type safety
        let locationsDelegate: LocationsViewControllerDelegate = self
        locationsViewController.delegate = locationsDelegate
        
        locationsViewController.didMove(toParent: self)
        print("Locations View Controller initialized")
    }
    
    private func setupMapViewController() {
        // Since we're creating the ViewController programmatically, we need to also create
        // and add the MapViewController programmatically
        
        // Check if MapViewController is already added as a child
        if let existingController = children.first(where: { $0 is MapViewController }) as? MapViewController {
            self.mapViewController = existingController
        } else {
            // Create MapViewController programmatically
            let controller = MapViewController()
            
            // Add as child view controller
            addChild(controller)
            mapContainerView.addSubview(controller.view)
            controller.didMove(toParent: self)
            
            // Set up constraints to make it fill the container
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: mapContainerView.topAnchor),
                controller.view.leadingAnchor.constraint(equalTo: mapContainerView.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: mapContainerView.bottomAnchor)
            ])
            
            self.mapViewController = controller
        }
        
        // Set the delegate so we can pass location data to it.
        let mapDelegate: MapViewControllerDelegate = self
        self.mapViewController.delegate = mapDelegate
        
        // If we already have locations, pass them to the map controller
        if !allLocations.isEmpty {
            mapViewController.updateAllLocations(allLocations)
        }
        
        print("Map View Controller has been configured programmatically.")
    }
    
    private func setupInfoViewController() {
        // Initialize Info View Controller
        infoViewController = InfoViewController()
        addChild(infoViewController)
        infoContainerView.addSubview(infoViewController.view)
        infoViewController.view.frame = infoContainerView.bounds
        infoViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        infoViewController.didMove(toParent: self)
        print("Info View Controller initialized")
    }
    
    private func setupNavigationButtons(in containerView: UIView) {
        // Create button stack view
        buttonsStackView = UIStackView()
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonsStackView.axis = .horizontal
        buttonsStackView.alignment = .center
        buttonsStackView.distribution = .equalSpacing
        buttonsStackView.spacing = 60  // Adjusted spacing for 4 buttons
        containerView.addSubview(buttonsStackView)
        
        // Create buttons with increased size for padding
        arButton = createNavButton(symbolName: "camera.viewfinder", action: #selector(arButtonTapped))
        mapButton = createNavButton(symbolName: "map", action: #selector(mapButtonTapped))
        listButton = createNavButton(symbolName: "list.bullet", action: #selector(listButtonTapped))
        infoButton = createNavButton(symbolName: "info.circle", action: #selector(infoButtonTapped))
        
        // Add buttons to stack view in the order
        buttonsStackView.addArrangedSubview(arButton)
        buttonsStackView.addArrangedSubview(mapButton)
        buttonsStackView.addArrangedSubview(listButton)
        buttonsStackView.addArrangedSubview(infoButton)
        
        // Position stack view in bottom container
        NSLayoutConstraint.activate([
            buttonsStackView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            buttonsStackView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            buttonsStackView.heightAnchor.constraint(equalToConstant: 54) // Increased height for larger buttons
        ])
    }
    
    private func createNavButton(symbolName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Use SF Symbols for icons
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            let image = UIImage(systemName: symbolName, withConfiguration: config)
            button.setImage(image, for: .normal)
        } else {
            // Fallback for earlier iOS versions
            button.setTitle(symbolName, for: .normal)
        }
        
        button.tintColor = .white
        button.backgroundColor = .clear
        button.layer.cornerRadius = 27  // Circular button (54/2)
        button.layer.borderColor = UIColor.clear.cgColor
        button.layer.borderWidth = 0
        button.addTarget(self, action: action, for: .touchUpInside)
        
        // Add padding around the icon by making the button larger
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 54),
            button.heightAnchor.constraint(equalToConstant: 54)
        ])
        
        return button
    }
    
    // MARK: - Layout Adjustment
    @objc private func orientationChanged() {
        adjustLayoutForOrientation()
    }
    
    private func adjustLayoutForOrientation() {
        // Get current orientation
        let isLandscape = UIDevice.current.orientation.isLandscape
        
        // Update based on orientation
        if isLandscape {
            // Landscape mode - thin top border, smaller bottom
            topHeightConstraint?.constant = 15
            bottomHeightConstraint?.constant = 50
        } else {
            // Portrait mode - normal top height
            topHeightConstraint?.constant = 60
            bottomHeightConstraint?.constant = 80
        }
        
        // Force layout update
        view.layoutIfNeeded()
    }
    
    // MARK: - Orientation Support
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    // MARK: - Navigation
    // Tracking for lazy initialization
    private var mapViewInitialized = false
    private var locationsViewInitialized = false
    private var infoViewInitialized = false

    private func switchToView(_ viewState: ViewState) {
        // Skip if already in this view state
        if currentViewState == viewState {
            print("Already in \(viewState) state, skipping")
            return
        }
        
        print("Switching from \(currentViewState) to \(viewState)")
        
        // Handle AR session management when leaving AR view
        if currentViewState == .arView && viewState != .arView {
            print("Leaving AR View - pausing session")
            arViewController.pauseARSession()
        }
        
        // Handle AR session resumption when returning to AR view
        if currentViewState != .arView && viewState == .arView {
            print("Returning to AR View - resuming session")
            arViewController.resumeARSession()
        }
        
        // First, hide all container views
        arContainerView.isHidden = true
        locationsContainerView.isHidden = true
        mapContainerView.isHidden = true
        infoContainerView.isHidden = true
        
        // Then show the selected view and handle true lazy loading if needed
        switch viewState {
        case .arView:
            arContainerView.isHidden = false

            updateButtonAppearance(activeButton: arButton)
            
        case .mapView:
            // Map is already initialized at startup - just show it
            mapContainerView.isHidden = false
            updateButtonAppearance(activeButton: mapButton)
            
        case .listView:
            // True lazy initialization for locations (Cesium) view
            if locationsViewController == nil {
                print("True lazy initializing Locations (Cesium) View - creating controller")
                setupLocationsViewController()
                locationsViewInitialized = true
            } else if !locationsViewInitialized {
                print("Locations View created but not fully initialized")
                locationsViewInitialized = true
            }
            
            locationsContainerView.isHidden = false
            updateButtonAppearance(activeButton: listButton)
            
        case .infoView:
            // True lazy initialization for info view
            if infoViewController == nil {
                print("True lazy initializing Info View - creating controller")
                setupInfoViewController()
                infoViewInitialized = true
            } else if !infoViewInitialized {
                print("Info View created but not fully initialized")
                infoViewInitialized = true
            }
            
            infoContainerView.isHidden = false
            updateButtonAppearance(activeButton: infoButton)
        }
        
        // DEV: WebGL resource management is dev-only scaffolding. When the
        // Info-tab toggle is off, the web view runs without explicit
        // pause/resume calls (its WKWebView continues running in the
        // background — production-shaped behavior). See DevTools.swift.
        if DevTools.isEnabled {
            if currentViewState == .listView && viewState != .listView {
                // Leaving web view - pause web content
                print("Leaving Cesium web view - pausing content")
                if locationsViewController != nil {
                    locationsViewController.pauseWebContent()
                }
            } else if viewState == .listView && currentViewState != .listView {
                // Entering web view - resume web content
                print("Entering Cesium web view - resuming content")
                if locationsViewController != nil {
                    locationsViewController.resumeWebContent()
                }
            }
        }
        
        currentViewState = viewState
    }
    
    private func updateButtonAppearance(activeButton: UIButton?) {
        // Reset all buttons
        for button in [arButton, mapButton, listButton, infoButton] {
            button?.backgroundColor = .clear
            button?.tintColor = .white
            button?.layer.borderColor = UIColor.clear.cgColor
            button?.layer.borderWidth = 0
        }
        
        // Highlight active button with white border
        if let button = activeButton {
            button.layer.borderColor = UIColor.white.cgColor
            button.layer.borderWidth = 3
            button.tintColor = .white  // Keep the icon white
        }
    }
    
    // MARK: - Button Actions
    @objc private func arButtonTapped() {
        switchToView(.arView)
    }
    
    @objc private func mapButtonTapped() {
        switchToView(.mapView)
    }
    
    @objc private func listButtonTapped() {
        switchToView(.listView)
    }
    
    @objc private func infoButtonTapped() {
        switchToView(.infoView)
    }
    
    // MARK: - Layout Updates
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update overlay frame to match view
        overlayContainer.frame = view.bounds
        
        // Don't manually set frames for views that use Auto Layout
        // The ARViewController now uses Auto Layout constraints
    }

    // MARK: - ARViewControllerDelegate Implementation
    func didUpdateNearbyLocations(_ locations: [ARModelLocation]) {
        nearbyLocations = locations
        
        // If we've already received all locations, use them as reference for ordering
        if !allLocations.isEmpty {
            // Filter allLocations to only include those that are in the nearbyLocations set
            let nearbyIDs = Set(locations.map { $0.id })
            let orderedNearbyLocations = allLocations.filter { nearbyIDs.contains($0.id) }
            
            // Pass ordered locations to other controllers only if they exist
            if mapViewController != nil {

            }
            
            if locationsViewController != nil {
                locationsViewController.updateLocations(orderedNearbyLocations)
            }
        } else {
            // If we don't have allLocations yet, just pass as is if controllers exist
            if mapViewController != nil {

            }
            
            if locationsViewController != nil {
                locationsViewController.updateLocations(locations)
            }
        }
    }
    
    func didLoadAllLocations(_ locations: [ARModelLocation]) {
        // Store all locations
        allLocations = locations
        
        // Debug log
        print("ViewController received \(locations.count) total locations")
        
        // Pass to map controller for full display only if it exists (due to lazy loading)
        if mapViewController != nil {
            mapViewController.updateAllLocations(locations)
        }
    }
    
    // MARK: - LocationsViewControllerDelegate & MapViewControllerDelegate Implementation
    func didSelectLocation(_ location: ARModelLocation) {
        // Switch to AR view and focus on selected location
        switchToView(.arView)
        
        // Make sure AR controller exists before focusing
        if arViewController != nil {
            arViewController.focusOnLocation(id: location.id)
        }
    }
}
extension ARModelLocation {
    // Get sequence from original JSON using the ID
    static func getSequenceFor(id: String) -> Int {
        // Try to load the JSON file
        guard let jsonURL = Bundle.main.url(forResource: "models_to_place", withExtension: "json", subdirectory: "Models"),
              let jsonData = try? Data(contentsOf: jsonURL),
              let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return Int.max
        }
        
        // Find the matching location by ID
        for (index, location) in jsonArray.enumerated() {
            if let locationId = location["id"] as? String, locationId == id {
                // If there's a sequence field, use it
                if let sequence = location["sequence"] as? Int {
                    return sequence
                }
                // Otherwise use the array index
                return index + 1
            }
        }
        
        return Int.max
    }
}

// Caching dictionary to avoid repeatedly parsing the JSON
var sequenceCache: [String: Int] = [:]

// Helper function that uses caching
func getSequenceNumber(for id: String) -> Int {
    if let cachedValue = sequenceCache[id] {
        return cachedValue
    }
    
    let sequence = ARModelLocation.getSequenceFor(id: id)
    sequenceCache[id] = sequence
    return sequence
}
