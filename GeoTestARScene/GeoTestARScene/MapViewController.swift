import UIKit
import MapKit
import CoreLocation

class MapViewController: UIViewController, MKMapViewDelegate {
    
    // Delegate
    weak var delegate: MapViewControllerDelegate?
    
    // UI Components
    private var mapView: MKMapView!
    
    // Data
    private var allLocations: [ARModelLocation] = []
    private var userLocation: CLLocation?
    private var initialMapSetupComplete = false

    
    // Constants
    private let proximityThreshold: CLLocationDistance = 500.0 // 500m - more precise proximity threshold as requested
    
    // Styling
    private let lineColor = UIColor(red: 0.635, green: 0.369, blue: 1.0, alpha: 0.8) // Purple #a25eff with transparency
    private let pointColor = UIColor(red: 0.635, green: 0.369, blue: 1.0, alpha: 1.0) // Purple #a25eff, fully opaque
    private let lineWidth: CGFloat = 7.0
    private let pointRadius: CGFloat = 10.0
    
    // Debugging flags
    private var hasLoggedReceivedLocations = false
    private var forceCenterOnBrooklyn = true // Force-center on Brooklyn if we don't get user location
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("Map View Controller initialized")
        
        // Set up map view with optimized loading
        setupMapView()
        
        // If we have data, draw the map immediately
        if !allLocations.isEmpty {
            print("View did load with data, redrawing map immediately.")
            redrawMapAnnotationsAndOverlays()
            trySetupInitialMapRegion()
        }
    }
    

    
    private func setupMapView() {
        // Create map view
        mapView = MKMapView()
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.showsUserLocation = true
        view.addSubview(mapView)
        
        // Add constraints
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Start with a zoomed-out view - we'll update this once we have location data
        let worldRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 180)
        )
        mapView.setRegion(worldRegion, animated: false)
    }
    
    private func centerOnDefaultLocation() {
        // Center on Fort Greene coordinates - this only happens if user is too far from locations or timeout occurs
        let brooklynCoords = CLLocationCoordinate2D(latitude: 40.6892, longitude: -73.9657) // Fort Greene, Brooklyn
        let region = MKCoordinateRegion(
            center: brooklynCoords,
            latitudinalMeters: 2000, // 2km view
            longitudinalMeters: 2000
        )
        mapView.setRegion(region, animated: false) // No animation for faster appearance
        
        // If we have AR locations, draw them
        if !allLocations.isEmpty {
            redrawMapAnnotationsAndOverlays()
        }
        
        // Mark as complete
        initialMapSetupComplete = true
    }
    
    private func attemptFallbackCentering() {
        // Only perform fallback if we haven't completed initial setup yet
        guard !initialMapSetupComplete else { return }
        
        print("Attempting fallback centering...")
        
        // If we have no user location yet, use default center point
        if userLocation == nil {
            print("User location not available, using default Fort Greene location")
            centerOnDefaultLocation()
            return
        }
        
        // If we have user location but no AR locations yet, still initialize with user location
        if allLocations.isEmpty && userLocation != nil {
            let userRegion = MKCoordinateRegion(
                center: userLocation!.coordinate,
                latitudinalMeters: 2000, // 2km view
                longitudinalMeters: 2000
            )
            print("No AR locations yet, centering on user location")
            mapView.setRegion(userRegion, animated: false)
            initialMapSetupComplete = true
            return
        }
        
        // If we reach here, both user location and AR locations are available
        // This is just a final safety check - the main logic should be in trySetupInitialMapRegion
        trySetupInitialMapRegion()
    }
    
    // MARK: - Map Initialization - only happens once
    private func trySetupInitialMapRegion() {
        // Only set up the initial region once
        guard !initialMapSetupComplete else { return }
        
        // Try to get user location from MapView if we don't have it yet
        if userLocation == nil, let userCoordinate = mapView.userLocation.location?.coordinate {
            userLocation = CLLocation(
                latitude: userCoordinate.latitude,
                longitude: userCoordinate.longitude
            )
        }
        
        // Debug logging of locations array without blocking setup
        if !hasLoggedReceivedLocations && !allLocations.isEmpty {
            print("MAP DEBUG: allLocations count: \(allLocations.count)")
            if !allLocations.isEmpty {
                print("First location coordinates: \(allLocations[0].coordinate.latitude), \(allLocations[0].coordinate.longitude)")
            }
            hasLoggedReceivedLocations = true
        }
        
        // Center on user if we have it, regardless of AR locations
        if let userLocation = self.userLocation {
            print("User location available, proceeding with region setup")
            
            // If we have AR locations, check proximity
            if !allLocations.isEmpty {
                var nearestLocationDistance = CLLocationDistance.greatestFiniteMagnitude
                
                for location in allLocations {
                    let locationObj = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    let distance = userLocation.distance(from: locationObj)
                    
                    if distance < nearestLocationDistance {
                        nearestLocationDistance = distance
                    }
                }
                
                print("Nearest location distance: \(nearestLocationDistance)m, threshold: \(proximityThreshold)m")
                
                if nearestLocationDistance <= proximityThreshold {
                    // User is close to at least one location, center the map on the user
                    print("User is within \(proximityThreshold)m, centering map on user location")
                    let region = MKCoordinateRegion(
                        center: userLocation.coordinate,
                        latitudinalMeters: 1000, // 1km view
                        longitudinalMeters: 1000
                    )
                    mapView.setRegion(region, animated: true)
                } else {
                    // User is far from all locations, show all locations
                    print("User is far from all locations, showing all locations")
                    setRegionToShowAllLocations(allLocations)
                }
                
                // Draw all the locations
                redrawMapAnnotationsAndOverlays()
            } else {
                // No AR locations yet, but we have user location, center on user
                print("No AR locations yet, centering on user location")
                let region = MKCoordinateRegion(
                    center: userLocation.coordinate,
                    latitudinalMeters: 1000, // 1km view
                    longitudinalMeters: 1000
                )
                mapView.setRegion(region, animated: true)
            }
            
            initialMapSetupComplete = true
        } else {
            print("Cannot set up initial map region yet. User location: \(userLocation != nil), AR locations: \(allLocations.count)")
        }
    }
    
    // MARK: - Public Methods


    func updateAllLocations(_ locations: [ARModelLocation]) {
        print("MapViewController received \(locations.count) total locations.")
        self.allLocations = locations.sorted { getSequenceNumber(for: $0.id) < getSequenceNumber(for: $1.id) }

        // If the view is already loaded, we can update the UI right away.
        // Otherwise, viewDidLoad will see the data and handle the drawing.
        if isViewLoaded {
            print("View is already loaded, redrawing map immediately.")
            redrawMapAnnotationsAndOverlays()
            trySetupInitialMapRegion()
        }
    }
    
    func updateUserLocation(_ location: CLLocation) {
        print("MapViewController received user location update: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        self.userLocation = location
        
        // Try to set initial region if not done yet
        trySetupInitialMapRegion()
        
        // We don't recenter the map after initial placement
    }
    
    // MARK: - Map Drawing
    private func redrawMapAnnotationsAndOverlays() {
        // Remove existing annotations and overlays
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        mapView.removeOverlays(mapView.overlays)
        
        // Always show all locations
        let locationsToShow = allLocations


        
        if locationsToShow.isEmpty {
            print("No locations to show on map")
            return
        }
        
        print("Drawing \(locationsToShow.count) locations on map")
        
        // Group locations by route, but combine Manhattan routes
        var routeGroups: [String: [ARModelLocation]] = [:]
        
        for location in locationsToShow {
            // Get route name from ID (e.g., "6thAve" from "6thAve_W57th")
            let components = location.id.components(separatedBy: "_")
            var routeKey = components.first ?? "unknown"
            
            // Combine 6thAve and Canal into a single "Manhattan" route
            if routeKey == "6thAve" || routeKey == "Canal" {
                routeKey = "Manhattan"
            }
            
            if routeGroups[routeKey] == nil {
                routeGroups[routeKey] = []
            }
            routeGroups[routeKey]?.append(location)
        }
        
        // Process each route
        for (_, routeLocations) in routeGroups {
            // Sort locations in this route by sequence number
            let sortedRouteLocations = routeLocations.sorted {
                getSequenceNumber(for: $0.id) < getSequenceNumber(for: $1.id)
            }
            
            // Add annotations for all locations in this route
            for location in sortedRouteLocations {
                let annotation = LocationAnnotation(location: location)
                mapView.addAnnotation(annotation)
            }
            
            // Only add polyline if we have at least 2 points
            if sortedRouteLocations.count >= 2 {
                var coordinates = sortedRouteLocations.map { $0.coordinate }
                let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
                mapView.addOverlay(polyline)
            }
        }
    }
        
        private func addPolylineBetweenLocations(_ locations: [ARModelLocation]) {
            // Create array of coordinates
            var coordinates: [CLLocationCoordinate2D] = []
            for location in locations {
                coordinates.append(location.coordinate)
            }
            
            // Create polyline only if we have at least 2 points
            if coordinates.count >= 2 {
                let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                mapView.addOverlay(polyline)
            }
        }
    
    private func setRegionToShowAllLocations(_ locations: [ARModelLocation]) {
        guard !locations.isEmpty else { return }
        
        // Create a map rect that includes all points
        var mapRect = MKMapRect.null
        
        for location in locations {
            let point = MKMapPoint(location.coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
            mapRect = mapRect.union(pointRect)
        }
        
        // Add padding (20% padding)
        let padding = 1.2
        mapRect = MKMapRect(
            x: mapRect.origin.x - mapRect.width * (padding - 1) / 2,
            y: mapRect.origin.y - mapRect.height * (padding - 1) / 2,
            width: mapRect.width * padding,
            height: mapRect.height * padding
        )
        
        // Set region
        mapView.setVisibleMapRect(mapRect, animated: true)
    }
    
    // MARK: - MKMapViewDelegate
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Skip user location annotation
        if annotation is MKUserLocation {
            return nil
        }
        
        // Cast to our custom annotation type
        guard let locationAnnotation = annotation as? LocationAnnotation else {
            return nil
        }
        
        // Create a custom annotation view for a circle point
        let identifier = "LocationCircle"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? CircleAnnotationView
        
        if annotationView == nil {
            annotationView = CircleAnnotationView(annotation: locationAnnotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
            
            // Add a button to the callout
            let infoButton = UIButton(type: .detailDisclosure)
            annotationView?.rightCalloutAccessoryView = infoButton
            
            // Configure size and center the view
            annotationView?.frame = CGRect(x: 0, y: 0, width: pointRadius * 2, height: pointRadius * 2)
            
            // Make sure the center of the view matches the coordinate
            annotationView?.centerOffset = CGPoint.zero
        } else {
            annotationView?.annotation = locationAnnotation
        }
        
        // Configure circle appearance
        annotationView?.circleColor = pointColor
        annotationView?.circleRadius = pointRadius
        
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKPolyline {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = lineColor
            renderer.lineWidth = lineWidth
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        if view.annotation is LocationAnnotation {
            view.layer.zPosition = 100 // Bring selected annotation to front
        }
    }
    
    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        view.layer.zPosition = 0 // Reset z-index
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let annotation = view.annotation as? LocationAnnotation else { return }
        
        // Notify delegate of selection
        delegate?.didSelectLocation(annotation.location)
    }
    
    // This delegate method will be called whenever the user location updates on the map
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        if let location = userLocation.location {
            print("Map delegate caught user location update: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            self.userLocation = location
            
            // Try to set initial region if not done yet
            trySetupInitialMapRegion()
        }
    }
}

// No changes to these classes
class LocationAnnotation: NSObject, MKAnnotation {
    let location: ARModelLocation
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    
    init(location: ARModelLocation) {
        self.location = location
        self.coordinate = location.coordinate
        self.title = location.description
        self.subtitle = "Distance: \(location.distanceToNext ?? 0)m"
        super.init()
    }
}

class CircleAnnotationView: MKAnnotationView {
    var circleColor: UIColor = UIColor(red: 0.635, green: 0.369, blue: 1.0, alpha: 1.0) // Purple #a25eff
    var circleRadius: CGFloat = 10.0
    
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        
        // Set up sizing to match desired circle size
        self.frame = CGRect(x: 0, y: 0, width: circleRadius * 2, height: circleRadius * 2)
        
        // Important: Set centerOffset to zero to center the dot on the coordinate
        self.centerOffset = .zero
        
        // Ensure the background is transparent
        self.backgroundColor = .clear
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func draw(_ rect: CGRect) {
        // Get current graphics context
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Clear the rect to transparent
        context.clear(rect)
        
        // Calculate the circle rect to ensure it's centered
        let circleRect = CGRect(
            x: (rect.width - circleRadius * 2) / 2,
            y: (rect.height - circleRadius * 2) / 2,
            width: circleRadius * 2,
            height: circleRadius * 2
        )
        
        // Fill with solid color (fully opaque)
        context.setFillColor(circleColor.cgColor)
        context.fillEllipse(in: circleRect)
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        // Add a subtle pulse animation when selected
        if selected {
            UIView.animate(withDuration: 0.3, animations: {
                self.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            }, completion: { _ in
                UIView.animate(withDuration: 0.3) {
                    self.transform = CGAffineTransform.identity
                }
            })
        }
    }
}
