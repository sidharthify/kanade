//
//  kanadeApp.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import SwiftUI

@Observable
final class AppUIState {
    /// how far the mini player is tucked away, where 0 is fully shown and 1 is
    /// fully hidden. driven by how close the active scroll view is to its bottom.
    var miniPlayerHideProgress: Double = 0
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