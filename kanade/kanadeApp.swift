//
//  kanadeApp.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import SwiftUI

@main
struct kanadeApp: App {
    @State private var player = MusicPlayer()

    init() {
        // Touch DatabaseManager so the DB is created/migrated at launch
        _ = DatabaseManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
        }
    }
}
