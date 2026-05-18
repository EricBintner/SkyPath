import UIKit
import CoreLocation
import WebKit

class LocationsViewController: UIViewController, WKNavigationDelegate {
    
    // Delegate
    weak var delegate: LocationsViewControllerDelegate?
    
    // UI Components
    private var webView: WKWebView!
    
    // Data
    private var locations: [ARModelLocation] = []
    
    // Default URL to load
    private let defaultURL = URL(string: "https://cesium-google-3d-2.vercel.app/")!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup UI
        setupUI()
        
        // Setup JavaScript communication
        setupJavaScriptCommunication()
        
        // Load the default website
        loadWebsite(url: defaultURL)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Make sure webView's frame fills the available space
        webView.frame = view.bounds
    }
    
    private func setupUI() {
        // Create a configuration for the web view
        let webConfiguration = WKWebViewConfiguration()
        
        // Enable JavaScript
        webConfiguration.preferences.javaScriptEnabled = true
        
        // Allow JavaScript to open windows without user interaction (for popups)
        webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        // Initialize the web view with the configuration
        webView = WKWebView(frame: view.bounds, configuration: webConfiguration)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Add the web view to the view hierarchy
        view.addSubview(webView)
    }
    
    // Method to load a specific website
    private func loadWebsite(url: URL) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    // MARK: - Public Methods
    func updateLocations(_ locations: [ARModelLocation]) {
        self.locations = locations
        
        // If needed, could load a different URL based on location data
        // For now, we're just storing the locations for potential future use
    }
    
    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Web page finished loading
        print("Website loaded successfully")
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Web page failed to load
        print("Error loading website: \(error.localizedDescription)")
    }
    
    // MARK: - Web Content Management
    
    /// Called when leaving the web view tab
    func pauseWebContent() {
        print("Pausing web content resources")
        
        // Simplified and more defensive JavaScript to avoid errors
        let pauseScript = """
            try {
                console.log('Executing pause operations for web content');
                
                // Basic media handling - this is safe for any webpage
                // Pause all video elements
                document.querySelectorAll('video').forEach(function(video) { 
                    if(!video.paused) { 
                        console.log('Pausing video element');
                        video.pause(); 
                    }
                });
                
                // Pause all audio elements
                document.querySelectorAll('audio').forEach(function(audio) { 
                    if(!audio.paused) {
                        console.log('Pausing audio element');
                        audio.pause(); 
                    }
                });
                
                // Safely check if Cesium exists and is initialized
                var cesiumReady = false;
                var cesiumPaused = false;
                
                // Check Cesium in a safe way that won't throw exceptions
                if (window.Cesium && window.Cesium.viewer) {
                    try {
                        cesiumReady = true;
                        console.log('Pausing Cesium viewer animation');
                        
                        // Save current state
                        window.cesiumPreviousState = {
                            shouldAnimate: window.Cesium.viewer.clock.shouldAnimate,
                            requestRenderMode: window.Cesium.viewer.scene.requestRenderMode
                        };
                        
                        // Pause animation and reduce rendering
                        window.Cesium.viewer.clock.shouldAnimate = false;
                        window.Cesium.viewer.scene.requestRenderMode = true;
                        
                        cesiumPaused = true;
                        console.log('Successfully paused Cesium');
                    } catch(e) { 
                        console.log('Error while pausing Cesium: ' + e.message);
                    }
                } else {
                    console.log('Cesium viewer not initialized yet, nothing to pause');
                }
                
                return { 
                    status: 'success', 
                    cesiumReady: cesiumReady,
                    cesiumPaused: cesiumPaused,
                    message: 'Web content pause attempted'
                };
            } catch(e) {
                console.error('Error in pauseWebContent: ' + e.message);
                return { 
                    status: 'error', 
                    message: e.message 
                };
            }
        """;
        
        webView.evaluateJavaScript(pauseScript) { [weak self] result, error in
            if let error = error {
                print("Error pausing web content: \(error.localizedDescription)")
            } else if let status = result as? [String: Any] {
                print("Web content pause result: \(status)")
            }
        }
    }
    
    /// Called when returning to the web view tab
    func resumeWebContent() {
        print("Resuming web content resources")
        
        // Make sure the view is visible
        webView.isHidden = false
        
        // Simplified and more defensive JavaScript to avoid errors
        let resumeScript = """
            try {
                console.log('Executing resume operations for web content');
                
                // Basic media handling - optionally resume videos
                // We leave audio paused as users usually don't want auto-playing audio
                // document.querySelectorAll('video').forEach(function(video) { video.play(); });
                
                // Safely check if Cesium exists and is initialized
                var cesiumReady = false;
                var cesiumResumed = false;
                
                // Check Cesium in a safe way that won't throw exceptions
                if (window.Cesium && window.Cesium.viewer) {
                    try {
                        cesiumReady = true;
                        console.log('Resuming Cesium viewer animation');
                        
                        // Restore animation state
                        window.Cesium.viewer.clock.shouldAnimate = true;
                        window.Cesium.viewer.scene.requestRenderMode = false; // Render continuously
                        
                        // Force a render to refresh the scene
                        if (window.Cesium.viewer.scene.requestRender) {
                            window.Cesium.viewer.scene.requestRender();
                        }
                        
                        cesiumResumed = true;
                        console.log('Successfully resumed Cesium');
                    } catch(e) { 
                        console.log('Error while resuming Cesium: ' + e.message);
                    }
                } else {
                    console.log('Cesium viewer not initialized yet, nothing to resume');
                }
                
                return { 
                    status: 'success', 
                    cesiumReady: cesiumReady,
                    cesiumResumed: cesiumResumed,
                    message: 'Web content resume attempted'
                };
            } catch(e) {
                console.error('Error in resumeWebContent: ' + e.message);
                return { 
                    status: 'error', 
                    message: e.message 
                };
            }
        """;
        
        webView.evaluateJavaScript(resumeScript) { [weak self] result, error in
            if let error = error {
                print("Error resuming web content: \(error.localizedDescription)")
            } else if let status = result as? [String: Any] {
                print("Web content resume result: \(status)")
            }
        }
    }
    
    /// Check the status of Cesium - can be used for testing
    func checkCesiumStatus(_ context: String = "") {
        let statusScript = """
            if (typeof Cesium !== 'undefined' && Cesium.viewer) {
                return {
                    loaded: true,
                    shouldAnimate: Cesium.viewer.clock.shouldAnimate,
                    requestRenderMode: Cesium.viewer.scene.requestRenderMode,
                    maximumRenderTimeChange: Cesium.viewer.scene.maximumRenderTimeChange,
                    fps: Cesium.viewer.scene.debugShowFramesPerSecond
                };
            } else {
                return { loaded: false };
            }
        """;
        
        webView.evaluateJavaScript(statusScript) { result, error in
            if let error = error {
                print("Error checking Cesium status: \(error.localizedDescription)")
            } else if let status = result as? [String: Any] {
                print("Cesium status [\(context)]: \(status)")
            } else {
                print("No Cesium status available [\(context)]")
            }
        }
    }
}

// MARK: - Helper Methods
extension LocationsViewController {
    // Method to load a custom URL
    func loadURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            return
        }
        loadWebsite(url: url)
    }
    
    // Method to handle JavaScript communication from the website
    func setupJavaScriptCommunication() {
        // Create a script message handler for communication from web page to app
        webView.configuration.userContentController.add(self, name: "locationHandler")
    }
    
    // Method to notify delegate when a location is selected
    // This maintains compatibility with the existing delegate pattern
    private func notifyLocationSelected(_ location: ARModelLocation) {
        delegate?.didSelectLocation(location)
    }
}

// MARK: - WKScriptMessageHandler for JavaScript communication
extension LocationsViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Handle messages from JavaScript
        if message.name == "locationHandler" {
            // Example: Receive a location ID from the web page
            if let locationData = message.body as? [String: Any],
               let locationId = locationData["id"] as? String {
                
                // Find the corresponding location in our data
                if let selectedLocation = locations.first(where: { $0.id == locationId }) {
                    // Notify delegate of selection
                    notifyLocationSelected(selectedLocation)
                }
            }
        }
    }
}

