//
//  ContentView.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import SwiftUI
import AVFoundation

// MARK: - Document picker wrapper
struct AudioFilePicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Allow folders and audio files
        let types: [UTType] = [.folder, .audio]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

// MARK: - Root View
struct ContentView: View {
    @Environment(MusicPlayer.self) private var player
    @State private var importer = LibraryImporter()
    
    var body: some View {
        TabView {
            LibraryView(importer: importer)
                .tabItem {
                    Label("Library", systemImage: "music.note.list")
                }
            
            PlayerView()
                .tabItem {
                    Label("Now Playing", systemImage: "play.circle.fill")
                }
        }
        .tint(.white)
        // force dark mode because light mode hurts
        .preferredColorScheme(.dark)
    }
}

// MARK: - Library Tab
struct LibraryView: View {
    @Environment(MusicPlayer.self) private var player
    @Bindable var importer: LibraryImporter
    
    @State private var tracks: [TrackRecord] = []
    @State private var showPicker = false
    
    var body: some View {
        NavigationStack {
            List(tracks) { track in
                Button {
                    play(track: track)
                } label: {
                    HStack {
                        // Artwork placeholder
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 48, height: 48)
                            .cornerRadius(8)
                            .overlay {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            
                        VStack(alignment: .leading) {
                            Text(track.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                            if let artist = track.artist {
                                Text(artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)
                            }
                        }
                    }
                }
                .listRowBackground(Color.black)
            }
            .listStyle(.plain)
            .background(Color.black)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPicker = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .onAppear { loadTracks() }
        .sheet(isPresented: $showPicker) {
            AudioFilePicker { urls in
                Task {
                    await importer.importFiles(from: urls)
                    loadTracks()
                }
            }
        }
        .overlay {
            if importer.isImporting {
                VStack {
                    ProgressView("Importing... \(importer.importedCount) / \(importer.totalCount)")
                        .padding()
                        .background(.thickMaterial)
                        .cornerRadius(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.4))
            }
        }
    }
    
    private func loadTracks() {
        tracks = (try? DatabaseManager.shared.fetchAllTracks()) ?? []
    }
    
    private func play(track: TrackRecord) {
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let absoluteURL = docsDir.appendingPathComponent(track.filename)
        player.load(url: absoluteURL)
        player.play()
    }
}

// MARK: - Player Tab
struct PlayerView: View {
    @Environment(MusicPlayer.self) private var player
    @State private var isSeeking = false
    @State private var seekValue: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Track info
                VStack(spacing: 6) {
                    Text(player.currentTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let artist = player.currentArtist {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal)

                // Seek bar
                VStack(spacing: 6) {
                    Slider(
                        value: isSeeking ? $seekValue : .init(
                            get: { player.currentTime },
                            set: { _ in }
                        ),
                        in: 0...max(player.duration, 1)
                    ) { editing in
                        if editing {
                            isSeeking = true
                            seekValue = player.currentTime
                        } else {
                            player.seek(to: seekValue)
                            isSeeking = false
                        }
                    }
                    .tint(.white)
                    .padding(.horizontal)

                    HStack {
                        Text(formatted(player.currentTime))
                        Spacer()
                        Text(formatted(player.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal)
                }

                // Controls
                HStack(spacing: 48) {
                    Button {
                        player.seek(to: max(0, player.currentTime - 10))
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                    
                    Button {
                        player.isPlaying ? player.pause() : player.play()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white)
                    }

                    Button {
                        player.seek(to: min(player.duration, player.currentTime + 10))
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }

                Spacer()
            }
        }
    }

    private func formatted(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let total = Int(time)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    } // format time
}
