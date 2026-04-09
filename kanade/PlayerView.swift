//
//  PlayerView.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import SwiftUI
import MediaPlayer

// MARK: - Player sheet

struct PlayerView: View {
    @Environment(MusicPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var isSeeking = false
    @State private var seekValue: Double = 0
    @State private var showEQ = false
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showOptions = false
    @State private var lyrics = LyricsManager.shared
    var body: some View {
        ZStack {
            // background ignores all safe areas
            artworkBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // top bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Button { showOptions = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 16)

                Spacer(minLength: 16)

                // fixed square artwork
                ArtworkImage(
                    trackId: player.currentTrackId,
                    hasArtwork: player.currentHasArtwork,
                    size: artworkDiameter,
                    cornerRadius: 12
                )
                .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)

                Spacer(minLength: 16)

                VStack(spacing: 16) {
                    trackInfo
                    seekBar
                    mainControls
                    toolbar
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showEQ) {
            EQView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLyrics) {
            LyricsSheetView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "\(player.currentTitle) · \(formatted(player.duration)) · \(player.currentArtist ?? "") · \(player.currentAlbum ?? "")",
            isPresented: $showOptions,
            titleVisibility: .visible
        ) {
            Button("Delete from Library", role: .destructive) {
                if let id = player.currentTrackId {
                    try? DatabaseManager.shared.deleteTrack(id: id)
                    player.stop()
                }
            }
            Button("Delete from Queue", role: .destructive) {
                if let idx = player.queue.firstIndex(where: { $0.id == player.currentTrackId }) {
                    player.queue.remove(at: idx)
                }
            }
            Button("Open in") {
                guard let url = player.currentURL else { return }
                let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let vc = scene.windows.first?.rootViewController {
                    vc.present(av, animated: true)
                }
            }
            Button("Edit Audio Tags") {}
            Button("Add to Playlist") {}
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            syncSeekFromPlayer()
        }
        .onChange(of: player.currentTrackId) { _, _ in
            isSeeking = false
            syncSeekFromPlayer()
        }
        .onChange(of: player.currentTime) { _, _ in
            guard !isSeeking else { return }
            syncSeekFromPlayer()
        }
        .onChange(of: player.duration) { _, _ in
            if isSeeking {
                seekValue = clampedSeekValue(seekValue)
            } else {
                syncSeekFromPlayer()
            }
        }
    }


    // MARK: - Artwork size

    // compute once: as wide as the screen minus a little breathing room,
    // but never taller than ~42 % of the screen height so controls don't overflow
    private var artworkDiameter: CGFloat {
        let w = UIScreen.main.bounds.width - 32
        let h = UIScreen.main.bounds.height * 0.42
        return min(w, h)
    }

    @ViewBuilder
    private var artworkBackground: some View {
        if let img = loadArtwork() {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .blur(radius: 80, opaque: true) // opaque makes edges cleaner
                .overlay(Color.black.opacity(0.4))
        } else {
            Color.black
        }
    }

    private func loadArtwork() -> UIImage? {
        guard let id = player.currentTrackId, player.currentHasArtwork,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        return UIImage(contentsOfFile: docs.appendingPathComponent("Artwork/\(id).jpg").path)
    }

    // MARK: - Controls

    private var trackInfo: some View {
        ZStack {
            // text centered over the full available width
            VStack(spacing: 2) {
                Text(player.currentTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let artist = player.currentArtist { Text(artist) }
                    if let album = player.currentAlbum, !album.isEmpty {
                        Text("·")
                        Text(album)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // options button pinned to the right without affecting centering
            HStack {
                Spacer()
                Button { showOptions = true } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var seekBar: some View {
        VStack(spacing: 4) {
            Slider(
                value: nativeSeekValue,
                in: seekRange
            ) { editing in
                if editing {
                    isSeeking = true
                } else {
                    seekValue = clampedSeekValue(seekValue)
                    player.seek(to: seekValue)
                    isSeeking = false
                }
            }
            .tint(.white)
            .allowsHitTesting(player.hasTrackLoaded)
            .opacity(player.hasTrackLoaded ? 1 : 0.45)
            .frame(width: seekerWidth)
            .scaleEffect(x: 0.94, y: 1, anchor: .center)

            HStack {
                Text(formatted(isSeeking ? seekValue : player.currentTime))
                Spacer()
                Text(formatted(safeDuration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
            .frame(width: seekerWidth)
        }
        .frame(maxWidth: .infinity)
    }

    private var mainControls: some View {
        HStack(spacing: 32) {
            Button {
                switch player.repeatMode {
                case .off: player.repeatMode = .all
                case .all: player.repeatMode = .one
                case .one: player.repeatMode = .off
                }
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.title3)
                    .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.35) : .white)
            }

            Button { player.skipPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }

            Button { player.isPlaying ? player.pause() : player.play() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color.white))
                    .foregroundStyle(.black)
            }

            Button { player.skipNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }

            Button { player.shuffleEnabled.toggle() } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(player.shuffleEnabled ? .white : .white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity)
    }


    private var toolbar: some View {
        HStack {
            Image(systemName: "speaker.wave.2")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
            Button { showEQ = true } label: {
                Image(systemName: "slider.vertical.3")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button { showLyrics = true } label: {
                Image(systemName: "text.quote")
                    .font(.title3)
                    .foregroundStyle(lyrics.hasLyrics || lyrics.isLoading ? .white : .white.opacity(0.35))
            }
            .accessibilityLabel("Lyrics")
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Helpers

    private var remainingFormatted: String {
        let rem = max(0, player.duration - player.currentTime)
        guard rem.isFinite else { return "-0:00" }
        let t = Int(rem)
        return String(format: "-%d:%02d", t / 60, t % 60)
    }

    private func formatted(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let t = Int(time)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private var safeDuration: Double {
        guard player.duration.isFinite, !player.duration.isNaN else { return 0 }
        return max(0, player.duration)
    }

    private var seekRange: ClosedRange<Double> {
        0...max(safeDuration, 1)
    }

    private var seekerWidth: CGFloat {
        max(180, UIScreen.main.bounds.width - 72)
    }

    private var nativeSeekValue: Binding<Double> {
        Binding(
            get: { clampedSeekValue(seekValue) },
            set: { seekValue = clampedSeekValue($0) }
        )
    }

    private func clampedSeekValue(_ value: Double) -> Double {
        min(max(value, seekRange.lowerBound), seekRange.upperBound)
    }

    private func syncSeekFromPlayer() {
        let current = player.currentTime.isFinite ? player.currentTime : 0
        seekValue = clampedSeekValue(current)
    }
}

// MARK: - Synced lyrics scroll

struct LyricsScrollView: View {
    @Environment(MusicPlayer.self) private var player
    @State private var lyrics = LyricsManager.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { i, line in
                        Text(line.text)
                            .font(i == activeIndex ? .title3.weight(.semibold) : .body)
                            .foregroundStyle(i == activeIndex ? .white : .white.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                            .animation(.easeInOut(duration: 0.2), value: activeIndex)
                    }
                }
                .padding(.vertical, 16)
            }
            .frame(minHeight: 200)
            .onChange(of: activeIndex) { _, idx in
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(max(0, idx - 2), anchor: .top)
                }
            }
        }
    }

    private var activeIndex: Int { lyrics.activeIndex(at: player.currentTime) }
}

// MARK: - Lyrics sheet

struct LyricsSheetView: View {
    @Environment(MusicPlayer.self) private var player
    @State private var lyrics = LyricsManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if lyrics.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Fetching lyrics...")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else if lyrics.lines.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.quote")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
                Text("No lyrics found")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(player.currentTitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        } else {
            LyricsScrollView()
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }
}

// MARK: - Queue sheet

struct QueueView: View {
    @Environment(MusicPlayer.self) private var player

    var body: some View {
        NavigationStack {
            List(Array(player.queue.enumerated()), id: \.element.id) { i, track in
                Button { player.loadQueue(tracks: player.queue, startingAt: i) } label: {
                    HStack {
                        TrackRow(track: track)
                        if track.id == player.currentTrackId {
                            Spacer()
                            Image(systemName: "waveform")
                                .foregroundStyle(.white)
                                .symbolEffect(.variableColor.iterative)
                        }
                    }
                }
                .listRowBackground(Color.black)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - EQ sheet

struct EQView: View {
    @State private var eq = EQManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.07).ignoresSafeArea()

                VStack(spacing: 24) {
                    // preset chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(EQPreset.allCases.filter { $0 != .custom }) { preset in
                                Button { eq.applyPreset(preset) } label: {
                                    Text(preset.rawValue)
                                        .font(.subheadline)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(eq.selectedPreset == preset ? Color.white : Color.white.opacity(0.1))
                                        .foregroundStyle(eq.selectedPreset == preset ? Color.black : Color.white)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // 10 vertical band sliders
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<10, id: \.self) { i in
                            VStack(spacing: 4) {
                                Text(gainLabel(eq.gains[i]))
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.6))

                                VerticalSlider(value: Binding(
                                    get: { eq.gains[i] },
                                    set: { v in var g = eq.gains; g[i] = v; eq.gains = g }
                                ), range: -12...12)
                                .frame(height: 180)

                                Text(eqBandLabels[i])
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal)

                    // preamplifier
                    VStack(spacing: 8) {
                        Text("Preamplifier: \(gainLabel(eq.preamplifierGain)) dB")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))

                        HStack(spacing: 16) {
                            Button { eq.nudgePreamplifier(by: -1) } label: {
                                Image(systemName: "minus.circle").font(.title2).foregroundStyle(.white)
                            }
                            Slider(value: $eq.preamplifierGain, in: -12...12).tint(.white)
                            Button { eq.nudgePreamplifier(by: 1) } label: {
                                Image(systemName: "plus.circle").font(.title2).foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.top, 16)
            }
            .navigationTitle("Audio Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("", isOn: $eq.isEnabled).labelsHidden()
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {} label: {
                        Image(systemName: "ellipsis").foregroundStyle(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func gainLabel(_ val: Float) -> String {
        String(format: val >= 0 ? "+%.1f" : "%.1f", val)
    }
}

// MARK: - Vertical EQ slider

struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    @State private var lastValue: Float = 0

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbY = h - fraction * h

            ZStack(alignment: .top) {
                Capsule().fill(Color.white.opacity(0.15)).frame(width: 3).frame(maxWidth: .infinity)
                Capsule()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 3, height: max(0, h - thumbY))
                    .frame(maxWidth: .infinity)
                    .offset(y: thumbY)
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .offset(y: thumbY - 10)
                    .frame(maxWidth: .infinity)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let delta = Float(-drag.translation.height / h) * (range.upperBound - range.lowerBound)
                                value = min(range.upperBound, max(range.lowerBound, lastValue + delta))
                            }
                            .onEnded { _ in lastValue = value }
                    )
            }
        }
        .onAppear { lastValue = value }
    }
}
