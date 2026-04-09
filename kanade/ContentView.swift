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
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.audio, .mp3, UTType("public.aiff-audio"), UTType("com.apple.m4a-audio")]
            .compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - Content view (Stage 1 proof-of-concept)
struct ContentView: View {
    @Environment(MusicPlayer.self) private var player
    @State private var showPicker = false
    @State private var isSeeking = false
    @State private var seekValue: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {

                // Title
                Text("kanade")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

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

                // Load track
                Button {
                    showPicker = true
                } label: {
                    Label("Load track", systemImage: "folder")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.white, in: Capsule())
                }
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showPicker) {
            AudioFilePicker { url in
                player.load(url: url)
                player.play()
            }
        }
    }

    private func formatted(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let total = Int(time)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    ContentView()
        .environment(MusicPlayer())
}
