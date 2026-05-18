import Foundation
import CoreLocation
import ARKit

// Add : AnyObject to make each protocol a class-only protocol
// This is required for weak delegates

// MARK: - Protocol for LocationsViewController
protocol LocationsViewControllerDelegate: AnyObject {
    func didSelectLocation(_ location: ARModelLocation)
}

// MARK: - Protocol for MapViewController
protocol MapViewControllerDelegate: AnyObject {
    func didSelectLocation(_ location: ARModelLocation)
}

// MARK: - Protocol for ARViewController
protocol ARViewControllerDelegate: AnyObject {
    func didUpdateNearbyLocations(_ locations: [ARModelLocation])
    func didLoadAllLocations(_ locations: [ARModelLocation])
}
