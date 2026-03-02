//
//  Music2App.swift
//  Music2
//
//  Created by grace keywork on 2/16/26.
//

import SwiftUI

@main
struct Music2App: App {
    
    // @StateObject here means:
    // "Create ONE BLEManager for the entire app lifecycle"
    // This prevents SwiftUI view refreshes from accidentally creating multiple BLEManagers.
    @StateObject private var bleManager = BLEManager()
    
    var body: some Scene {
        WindowGroup {
            // .environmentObject passes the ONE shared BLEManager into the view hierarchy.
            // Any view can access it using @EnvironmentObject.
            ContentView()
                .environmentObject(bleManager)
        }
    }
}
