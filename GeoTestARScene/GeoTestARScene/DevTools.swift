//
//  DevTools.swift
//
//  DEV-ONLY: Phase 02 instrumentation + debugging scaffolding.
//
//  -------------------------------------------------------------------
//  REMOVAL CONTRACT
//  -------------------------------------------------------------------
//  All dev-only code is reachable by grepping two markers from the
//  repo root:
//
//      grep -rn "// DEV:"   GeoTestARScene
//      grep -rn "// SPIKE:" GeoTestARScene
//
//  To rip the scaffolding out for a production release:
//
//    1. Delete this file (DevTools.swift).
//    2. Delete the Spike/ directory.
//    3. For each `// DEV:` site: remove the guard but keep whichever
//       branch you want as production behavior (usually: keep the
//       body, drop the guard).
//    4. Search "DevTools" — any remaining references are stale.
//
//  Spike-related cleanup is additionally documented in
//  docs/phases/Phase02_Spike_Playbook.md ("After the spike").
//

import Foundation

enum DevTools {
    private static let key = "DevTools.isEnabled"

    /// Posted whenever isEnabled changes. Observers update their UI in
    /// reaction (e.g. ARViewController shows/hides the floating Spikes
    /// button). Object is nil; userInfo is empty.
    static let didChangeNotification = Notification.Name("DevTools.didChange")

    /// Runtime master switch for Phase 02 instrumentation: the spike
    /// menu entry point and the WebGL resource-management calls.
    /// Toggled from the Info tab. Persists across launches via
    /// UserDefaults. Defaults to off (production-shaped behavior).
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
