//
//  kanadeApp.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import SwiftUI

@Observable
final class AppUIState {
    var isMiniPlayerCompact = false
}

@main
struct kanadeApp: App {
    @State private var player = MusicPlayer()
    @State private var uiState = AppUIState()

    init() {
        _ = DatabaseManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
                .environment(uiState)
        }
    }
}