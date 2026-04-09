//
//  LyricsManager.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import Foundation
import Observation

struct LyricLine: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String
}

/// fetches and parses synced lyrics from lrclib.net
@Observable
final class LyricsManager {

    static let shared = LyricsManager()

    var lines: [LyricLine] = []
    var isLoading: Bool = false
    var hasLyrics: Bool { !lines.isEmpty }

    private var currentTrackId: String? = nil

    private init() {}

    func fetchLyrics(for trackId: String, title: String, artist: String?, album: String?, duration: TimeInterval) {
        // skip refetch if already loaded for this track
        guard trackId != currentTrackId else { return }
        currentTrackId = trackId
        lines = []
        isLoading = true

        Task {
            let result = await Self.fetch(title: title, artist: artist, album: album, duration: duration)
            await MainActor.run {
                self.lines = result
                self.isLoading = false
            }
        }
    }

    func clear() {
        lines = []
        currentTrackId = nil
    }

    // index of the active lyric line for a given playback time
    func activeIndex(at time: TimeInterval) -> Int {
        guard !lines.isEmpty else { return 0 }
        var idx = 0
        for (i, line) in lines.enumerated() {
            if line.timestamp <= time { idx = i } else { break }
        }
        return idx
    }

    // MARK: - Network

    private static func fetch(title: String, artist: String?, album: String?, duration: TimeInterval) async -> [LyricLine] {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "duration", value: String(Int(duration)))
        ]
        if let artist { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        if let album  { items.append(URLQueryItem(name: "album_name", value: album)) }
        components.queryItems = items

        guard let url = components.url else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let json = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            guard let lrc = json.syncedLyrics, !lrc.isEmpty else { return [] }
            return parseLRC(lrc)
        } catch {
            print("[LyricsManager] Fetch failed: \(error)")
            return []
        }
    }

    // parses lrc format: [MM:SS.xx] lyric text
    private static func parseLRC(_ lrc: String) -> [LyricLine] {
        let pattern = /\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)/
        var result: [LyricLine] = []

        for rawLine in lrc.components(separatedBy: "\n") {
            guard let match = rawLine.firstMatch(of: pattern) else { continue }
            let minutes    = TimeInterval(match.1) ?? 0
            let seconds    = TimeInterval(match.2) ?? 0
            let hundredths = TimeInterval(match.3) ?? 0
            let centis     = match.3.count == 2 ? hundredths / 100 : hundredths / 1000
            let timestamp  = minutes * 60 + seconds + centis
            let text       = match.4.trimmingCharacters(in: .whitespaces)

            if !text.isEmpty {
                result.append(LyricLine(timestamp: timestamp, text: text))
            }
        }

        return result.sorted { $0.timestamp < $1.timestamp }
    }
}

// minimal struct for decoding lrclib's json response
private struct LRCLibResponse: Decodable {
    let syncedLyrics: String?
}
