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

// MARK: - Mini Player Modifier
struct MiniPlayerModifier: ViewModifier {
    @Environment(MusicPlayer.self) private var player
    @Binding var showPlayer: Bool

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if player.hasTrackLoaded {
                MiniPlayerView(showPlayer: $showPlayer)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.clear)
            }
        }
    }
}

extension View {
    func withMiniPlayer(showPlayer: Binding<Bool>) -> some View {
        self.modifier(MiniPlayerModifier(showPlayer: showPlayer))
    }
}

// MARK: - Root View
struct ContentView: View {
    @Environment(MusicPlayer.self) private var player
    @State private var importer = LibraryImporter()
    @State private var showPlayer = false

    var body: some View {
        TabView {
            LibraryView(
                importer: importer,
                title: "Library",
                sections: [.songs, .albums],
                searchPrompt: "Search Library",
                initialSection: .songs
            )
            .withMiniPlayer(showPlayer: $showPlayer)
            .tabItem {
                Label("Library", systemImage: "music.note.list")
            }

            LibraryView(
                importer: importer,
                title: "Artists",
                sections: [.artists],
                searchPrompt: "Search Artists",
                initialSection: .artists
            )
            .withMiniPlayer(showPlayer: $showPlayer)
            .tabItem {
                Label("Artists", systemImage: "person.2.fill")
            }

            SettingsView()
                .withMiniPlayer(showPlayer: $showPlayer)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
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

// MARK: - Settings
struct SettingsView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                }

                Section("Support") {
                    Text("Thanks for listening with Kanade.")
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Library
struct LibraryView: View {
    @Environment(MusicPlayer.self) private var player
    @Bindable var importer: LibraryImporter
    let title: String
    let sections: [LibrarySection]
    let searchPrompt: String
    let showsSectionPicker: Bool

    @State private var tracks: [TrackRecord] = []
    @State private var albums: [AlbumSummary] = []
    @State private var artists: [ArtistSummary] = []

    @State private var showPicker = false
    @State private var showClearDialog = false
    @State private var searchText = ""
    @State private var section: LibrarySection = .songs
    @State private var highlightedTrackId: String? = nil
    @State private var trackSort: TrackSort = .recent
    @State private var albumSort: AlbumSort = .name
    @State private var artistSort: ArtistSort = .name

    init(
        importer: LibraryImporter,
        title: String = "Library",
        sections: [LibrarySection] = LibrarySection.allCases,
        searchPrompt: String = "Search Library",
        showsSectionPicker: Bool = true,
        initialSection: LibrarySection? = nil
    ) {
        self.importer = importer
        self.title = title
        self.sections = sections
        self.searchPrompt = searchPrompt
        self.showsSectionPicker = showsSectionPicker
        let fallback = sections.first ?? .songs
        let selected = initialSection ?? fallback
        _section = State(initialValue: sections.contains(selected) ? selected : fallback)
    }

    var body: some View {
        let showSectionPicker = showsSectionPicker && sections.count > 1

        NavigationStack {
            VStack(spacing: 0) {
                if showSectionPicker {
                    Picker("Library Section", selection: $section) {
                        ForEach(sections) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }

                listContent
            }
            .padding(.top, showSectionPicker ? 0 : 0)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
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
                prompt: searchPrompt
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
        ScrollView {
            switch section {
            case .songs:
                LazyVStack(spacing: 8) {
                    ForEach(tracks) { track in
                        Button {
                            flashTrackSelection(track.id)
                            play(track: track)
                        } label: {
                            TrackRow(track: track)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        .opacity(highlightedTrackId == track.id ? 0.6 : 1.0)
                        .contextMenu {
                            Button(role: .destructive) { removeTrack(track) } label: {
                                Label("Remove from Library", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.top, 8)

            case .albums:
                let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            AlbumCard(album: album)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { removeAlbum(album) } label: {
                                Label("Remove from Library", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

            case .artists:
                let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(artists) { artist in
                        NavigationLink {
                            ArtistDetailView(artist: artist)
                        } label: {
                            ArtistCard(artist: artist)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { removeArtist(artist) } label: {
                                Label("Remove from Library", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
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

    private func flashTrackSelection(_ trackId: String) {
        withAnimation(.snappy(duration: 0.15)) {
            highlightedTrackId = trackId
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard highlightedTrackId == trackId else { return }
            withAnimation(.snappy(duration: 0.2)) {
                highlightedTrackId = nil
            }
        }
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
    @State private var highlightedTrackId: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(tracks) { track in
                    Button {
                        flashTrackSelection(track.id)
                        play(track: track)
                    } label: {
                        TrackRow(track: track)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .opacity(highlightedTrackId == track.id ? 0.6 : 1.0)
                    .contextMenu {
                        Button(role: .destructive) {
                            remove(track)
                        } label: {
                            Label("Remove from Library", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear { load() }
    }

    private func load() {
        tracks = (try? DatabaseManager.shared.fetchTracks(forAlbumId: album.id)) ?? []
    }

    private func play(track: TrackRecord) {
        player.loadQueue(tracks: tracks, startingAt: tracks.firstIndex(of: track) ?? 0)
    }

    private func flashTrackSelection(_ trackId: String) {
        withAnimation(.snappy(duration: 0.15)) {
            highlightedTrackId = trackId
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard highlightedTrackId == trackId else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                highlightedTrackId = nil
            }
        }
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
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(tracks) { track in
                    Button {
                        play(track: track)
                    } label: {
                        TrackRow(track: track)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .contextMenu {
                        Button(role: .destructive) {
                            remove(track)
                        } label: {
                            Label("Remove from Library", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.large)
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

    @State private var dragOffset: CGSize = .zero
    @State private var isAnimatingSkip = false

    private let skipThreshold: CGFloat  = 64
    private let expandThreshold: CGFloat = -50

    private var leftProgress:  CGFloat { max(0, min(1, -dragOffset.width / skipThreshold)) }
    private var rightProgress: CGFloat { max(0, min(1,  dragOffset.width / skipThreshold)) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let progress = player.duration > 0 ? player.currentTime / player.duration : 0

        ZStack {
            HStack {
                Image(systemName: "backward.fill")
                    .foregroundStyle(.secondary)
                    .opacity(rightProgress)
                    .padding(.leading, 20)
                Spacer()
                Image(systemName: "forward.fill")
                    .foregroundStyle(.secondary)
                    .opacity(leftProgress)
                    .padding(.trailing, 20)
            }
            .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ArtworkImage(
                        trackId: player.currentTrackId,
                        hasArtwork: player.currentHasArtwork,
                        size: 44,
                        cornerRadius: 10
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.currentTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(player.currentArtist ?? "Unknown Artist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Button {
                            player.isPlaying ? player.pause() : player.play()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .contentTransition(.symbolEffect(.replace))
                                .animation(.snappy, value: player.isPlaying)
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                        Button { triggerSkip(next: true) } label: {
                            Image(systemName: "forward.fill")
                                .font(.title3)
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Skip Next")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.quaternary)
                        Rectangle()
                            .fill(.primary.opacity(0.55))
                            .frame(width: geo.size.width * CGFloat(min(1, max(0, progress))))
                    }
                }
                .frame(height: 2)
                .clipShape(Capsule())
            }
            .background(.regularMaterial, in: shape)
            .overlay(shape.stroke(.separator.opacity(0.5), lineWidth: 0.5))
            .contentShape(shape)
            .offset(x: dragOffset.width * 0.38,
                    y: dragOffset.height < 0 ? dragOffset.height * 0.25 : dragOffset.height * 0.08)
            .opacity(isAnimatingSkip ? 0 : 1)
            .onTapGesture { showPlayer = true }
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard !isAnimatingSkip else { return }
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.86)) {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    guard !isAnimatingSkip else { return }
                    let h = value.translation.width
                    let v = value.translation.height
                    if abs(v) > abs(h) && v < expandThreshold {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragOffset = .zero }
                        showPlayer = true
                    } else if h < -skipThreshold {
                        animateSkip(toRight: false) { player.skipNext() }
                    } else if h > skipThreshold {
                        animateSkip(toRight: true) { player.skipPrevious() }
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { dragOffset = .zero }
                    }
                }
        )
    }

    private func animateSkip(toRight: Bool, action: @escaping () -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let exitX: CGFloat = toRight ? 300 : -300
        let enterX: CGFloat = toRight ? -300 : 300
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            dragOffset = CGSize(width: exitX, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            action()
            isAnimatingSkip = true
            dragOffset = CGSize(width: enterX, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            isAnimatingSkip = false
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { dragOffset = .zero }
        }
    }

    private func triggerSkip(next: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        animateSkip(toRight: !next) { next ? player.skipNext() : player.skipPrevious() }
    }
}

struct MiniPlayerSquishStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.interpolatingSpring(stiffness: 320, damping: 22), value: configuration.isPressed)
    }
}

// MARK: - Volume slider
struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView()
        v.tintColor = .white
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Row & Card
struct TrackRow: View {
    let track: TrackRecord

    var body: some View {
        HStack(spacing: 14) {
            ArtworkImage(
                trackId: track.id,
                hasArtwork: track.hasArtwork,
                size: 48,
                cornerRadius: 6
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(track.artist ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: "ellipsis")
                .foregroundStyle(.tertiary)
                .font(.system(size: 14, weight: .bold))
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }
}

struct AlbumCard: View {
    let album: AlbumSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkImage(
                trackId: album.artworkTrackId,
                hasArtwork: album.artworkTrackId != nil,
                size: UIScreen.main.bounds.width / 2 - 24,
                cornerRadius: 8
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.2), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(album.artistName ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }
}

struct ArtistCard: View {
    let artist: ArtistSummary

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            ArtworkImage(
                trackId: artist.artworkTrackId,
                hasArtwork: artist.artworkTrackId != nil,
                size: UIScreen.main.bounds.width / 2 - 40,
                cornerRadius: (UIScreen.main.bounds.width / 2 - 40) / 2
            )
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )

            VStack(alignment: .center, spacing: 2) {
                Text(artist.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(artist.trackCount) songs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        ZStack {
            if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.systemGray5)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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