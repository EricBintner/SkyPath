import CoreLocation

class LocationManager: NSObject, CLLocationManagerDelegate {
    
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    var currentLocation: CLLocation?
    var currentHeading: CLHeading?
    
    var locationUpdateHandler: ((CLLocation) -> Void)?
    var headingUpdateHandler: ((CLHeading) -> Void)?
    
    var authorizationStatus: CLAuthorizationStatus {
        return locationManager.authorizationStatus
    }
    
    private override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1.0 // Update every meter
        locationManager.headingFilter = 5.0 // Update every 5 degrees
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        locationUpdateHandler?(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        currentHeading = newHeading
        headingUpdateHandler?(newHeading)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location manager failed with error: \(error.localizedDescription)")
        if let clError = error as? CLError {
            print("   CLError code: \(clError.code.rawValue)")
            switch clError.code {
            case .denied:
                print("   Location services denied by user")
            case .locationUnknown:
                print("   Location currently unknown")
            case .network:
                print("   Network error")
            default:
                print("   Other error: \(clError.code)")
            }
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("📍 Location authorization changed to: \(manager.authorizationStatus)")
        switch manager.authorizationStatus {
        case .notDetermined:
            print("   Requesting authorization...")
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("   ⚠️ Location services restricted or denied")
        case .authorizedWhenInUse, .authorizedAlways:
            print("   ✅ Location services authorized")
        @unknown default:
            break
        }
    }
}
