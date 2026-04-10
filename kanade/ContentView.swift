//
//  ContentView.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import MediaPlayer

// MARK: - Document picker wrapper
struct AudioFilePicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // allow folders and audio files
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

enum LibrarySection: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"

    var id: String { rawValue }
}

// MARK: - Root View
struct ContentView: View {
    @Environment(MusicPlayer.self) private var player
    @State private var importer = LibraryImporter()
    @State private var showPlayer = false

    private var miniPlayerBottomPadding: CGFloat { 52 }

    var body: some View {
        LibraryView(importer: importer)
            .safeAreaInset(edge: .bottom) {
                if player.hasTrackLoaded {
                    MiniPlayerView(showPlayer: $showPlayer)
                        .padding(.horizontal)
                        .padding(.bottom, miniPlayerBottomPadding)
                }
            }
            .sheet(isPresented: $showPlayer) {
                PlayerView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .tint(.white)
            .preferredColorScheme(.dark)
    }
}

// MARK: - Library
struct LibraryView: View {
    @Environment(MusicPlayer.self) private var player
    @Bindable var importer: LibraryImporter

    @State private var tracks: [TrackRecord] = []
    @State private var albums: [AlbumSummary] = []
    @State private var artists: [ArtistSummary] = []

    @State private var showPicker = false
    @State private var showClearDialog = false
    @State private var searchText = ""
    @State private var section: LibrarySection = .songs
    @State private var trackSort: TrackSort = .recent
    @State private var albumSort: AlbumSort = .name
    @State private var artistSort: ArtistSort = .name

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Library Section", selection: $section) {
                    ForEach(LibrarySection.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                listContent
            }
            .padding(.top, 8)
            .background(Color.black)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    sortMenu
                    Menu {
                        Button(role: .destructive) {
                            showClearDialog = true
                        } label: {
                            Text("Remove Imported Files")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.white)
                    }
                    Button {
                        showPicker = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Library"
            )
        }
        .onAppear { reload() }
        .onChange(of: searchText) { reload() }
        .onChange(of: section) { reload() }
        .onChange(of: trackSort) { reload() }
        .onChange(of: albumSort) { reload() }
        .onChange(of: artistSort) { reload() }
        .sheet(isPresented: $showPicker) {
            AudioFilePicker { urls in
                Task {
                    await importer.importFiles(from: urls)
                    reload()
                }
            }
        }
        .alert("Remove Imported Files?", isPresented: $showClearDialog) {
            Button("Remove Imported Files", role: .destructive) {
                Task {
                    await importer.clearLibrary()
                    player.stop()
                    reload()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes imported audio and artwork from the app and clears the library.")
        }
        .overlay {
            if importer.isImporting || importer.isClearing {
                VStack {
                    if importer.isClearing {
                        ProgressView("Clearing library...")
                            .padding()
                            .background(.thickMaterial)
                            .cornerRadius(12)
                    } else {
                        ProgressView("Importing... \(importer.importedCount) / \(importer.totalCount)")
                            .padding()
                            .background(.thickMaterial)
                            .cornerRadius(12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.4))
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        switch section {
        case .songs:
            List(tracks) { track in
                Button {
                    play(track: track)
                } label: {
                    TrackRow(track: track)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        removeTrack(track)
                    } label: {
                        Text("Remove from Library")
                    }
                }
                .listRowBackground(Color.black)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

        case .albums:
            List(albums) { album in
                NavigationLink {
                    AlbumDetailView(album: album)
                } label: {
                    AlbumRow(album: album)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        removeAlbum(album)
                    } label: {
                        Text("Remove from Library")
                    }
                }
                .listRowBackground(Color.black)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

        case .artists:
            List(artists) { artist in
                NavigationLink {
                    ArtistDetailView(artist: artist)
                } label: {
                    ArtistRow(artist: artist)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        removeArtist(artist)
                    } label: {
                        Text("Remove from Library")
                    }
                }
                .listRowBackground(Color.black)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var sortMenu: some View {
        Menu {
            switch section {
            case .songs:
                Picker("Sort", selection: $trackSort) {
                    ForEach(TrackSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            case .albums:
                Picker("Sort", selection: $albumSort) {
                    ForEach(AlbumSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            case .artists:
                Picker("Sort", selection: $artistSort) {
                    ForEach(ArtistSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(.white)
        }
    }

    private func reload() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch section {
        case .songs:
            tracks = (try? DatabaseManager.shared.fetchTracks(search: query, sort: trackSort)) ?? []
        case .albums:
            albums = (try? DatabaseManager.shared.fetchAlbumSummaries(search: query, sort: albumSort)) ?? []
        case .artists:
            artists = (try? DatabaseManager.shared.fetchArtistSummaries(search: query, sort: artistSort)) ?? []
        }
    }

    private func play(track: TrackRecord) {
        player.loadQueue(tracks: tracks, startingAt: tracks.firstIndex(of: track) ?? 0)
    }

    private func removeTrack(_ track: TrackRecord) {
        do {
            try DatabaseManager.shared.deleteTrack(id: track.id)
            if player.currentTrackId == track.id {
                player.stop()
            }
            reload()
        } catch {
            print("[LibraryView] Failed to remove track: \(error)")
        }
    }

    private func removeAlbum(_ album: AlbumSummary) {
        do {
            try DatabaseManager.shared.deleteAlbum(id: album.id)
            reload()
        } catch {
            print("[LibraryView] Failed to remove album: \(error)")
        }
    }

    private func removeArtist(_ artist: ArtistSummary) {
        do {
            try DatabaseManager.shared.deleteArtist(id: artist.id)
            reload()
        } catch {
            print("[LibraryView] Failed to remove artist: \(error)")
        }
    }
}

// MARK: - Album detail
struct AlbumDetailView: View {
    @Environment(MusicPlayer.self) private var player
    let album: AlbumSummary
    @State private var tracks: [TrackRecord] = []

    var body: some View {
        List(tracks) { track in
            Button {
                play(track: track)
            } label: {
                TrackRow(track: track)
            }
            .contextMenu {
                Button(role: .destructive) {
                    remove(track)
                } label: {
                    Text("Remove from Library")
                }
            }
            .listRowBackground(Color.black)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private func load() {
        tracks = (try? DatabaseManager.shared.fetchTracks(forAlbumId: album.id)) ?? []
    }

    private func play(track: TrackRecord) {
        player.loadQueue(tracks: tracks, startingAt: tracks.firstIndex(of: track) ?? 0)
    }

    private func remove(_ track: TrackRecord) {
        do {
            try DatabaseManager.shared.deleteTrack(id: track.id)
            if player.currentTrackId == track.id {
                player.stop()
            }
            load()
        } catch {
            print("[AlbumDetailView] Failed to remove track: \(error)")
        }
    }
}

// MARK: - Artist detail
struct ArtistDetailView: View {
    @Environment(MusicPlayer.self) private var player
    let artist: ArtistSummary
    @State private var tracks: [TrackRecord] = []

    var body: some View {
        List(tracks) { track in
            Button {
                play(track: track)
            } label: {
                TrackRow(track: track)
            }
            .contextMenu {
                Button(role: .destructive) {
                    remove(track)
                } label: {
                    Text("Remove from Library")
                }
            }
            .listRowBackground(Color.black)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private func load() {
        tracks = (try? DatabaseManager.shared.fetchTracks(forArtistId: artist.id)) ?? []
    }

    private func play(track: TrackRecord) {
        player.loadQueue(tracks: tracks, startingAt: tracks.firstIndex(of: track) ?? 0)
    }

    private func remove(_ track: TrackRecord) {
        do {
            try DatabaseManager.shared.deleteTrack(id: track.id)
            if player.currentTrackId == track.id {
                player.stop()
            }
            load()
        } catch {
            print("[ArtistDetailView] Failed to remove track: \(error)")
        }
    }
}

// MARK: - Mini Player
struct MiniPlayerView: View {
    @Environment(MusicPlayer.self) private var player
    @Binding var showPlayer: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    showPlayer = true
                } label: {
                    HStack(spacing: 12) {
                        ArtworkImage(
                            trackId: player.currentTrackId,
                            hasArtwork: player.currentHasArtwork,
                            size: 44,
                            cornerRadius: 10
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.currentTitle)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary) 
                                .lineLimit(1)

                            Text(player.currentArtist ?? "Unknown Artist")
                                .font(.caption)
                                .foregroundStyle(.secondary) 
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 12)

                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            ProgressView(value: player.currentTime, total: max(player.duration, 1))
                .tint(.primary) 
        }
        .padding(12)
        .background(
            .ultraThinMaterial, 
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

// MARK: - Volume slider (wraps MPVolumeView since AVAudioSession.outputVolume is read-only)
struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView()
        v.showsRouteButton = false
        v.tintColor = .white
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Rows
struct TrackRow: View {
    let track: TrackRecord

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(
                trackId: track.id,
                hasArtwork: track.hasArtwork,
                size: 48,
                cornerRadius: 8
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(track.artist ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .lineLimit(1)

                if let album = track.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
        }
    }
}

struct AlbumRow: View {
    let album: AlbumSummary

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(
                trackId: album.artworkTrackId,
                hasArtwork: album.artworkTrackId != nil,
                size: 54,
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(album.artistName ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                Text("\(album.trackCount) tracks")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

struct ArtistRow: View {
    let artist: ArtistSummary

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(
                trackId: artist.artworkTrackId,
                hasArtwork: artist.artworkTrackId != nil,
                size: 54,
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(artist.albumCount) albums · \(artist.trackCount) tracks")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Artwork
struct ArtworkImage: View {
    let trackId: String?
    let hasArtwork: Bool
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))

                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func loadImage() -> UIImage? {
        guard hasArtwork, let trackId else { return nil }
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = docsDir.appendingPathComponent("Artwork").appendingPathComponent("\(trackId).jpg")
        return UIImage(contentsOfFile: url.path)
    }
}
