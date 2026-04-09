//
//  LibrarySummaries.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import Foundation
import GRDB

// compact album row for UI lists.
struct AlbumSummary: Codable, FetchableRecord, Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var artistName: String?
    var trackCount: Int
    var artworkTrackId: String?
}

// compact artist row for UI lists.
struct ArtistSummary: Codable, FetchableRecord, Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var trackCount: Int
    var albumCount: Int
    var artworkTrackId: String?
}

enum TrackSort: String, CaseIterable, Identifiable {
    case recent
    case title
    case artist
    case album

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "Recently Added"
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        }
    }

    var orderSQL: String {
        switch self {
        case .recent:
            return "track.addedAt DESC"
        case .title:
            return "LOWER(track.title) ASC"
        case .artist:
            return "LOWER(COALESCE(track.artist, '')) ASC, LOWER(track.title) ASC"
        case .album:
            return "LOWER(COALESCE(track.album, '')) ASC, LOWER(track.title) ASC"
        }
    }
}

enum AlbumSort: String, CaseIterable, Identifiable {
    case name
    case artist
    case trackCount
    case recent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Name"
        case .artist: return "Artist"
        case .trackCount: return "Track Count"
        case .recent: return "Recently Added"
        }
    }

    var orderSQL: String {
        switch self {
        case .name:
            return "LOWER(album.name) ASC"
        case .artist:
            return "LOWER(COALESCE(artistName, '')) ASC, LOWER(album.name) ASC"
        case .trackCount:
            return "trackCount DESC, LOWER(album.name) ASC"
        case .recent:
            return "album.createdAt DESC"
        }
    }
}

enum ArtistSort: String, CaseIterable, Identifiable {
    case name
    case trackCount
    case albumCount
    case recent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Name"
        case .trackCount: return "Track Count"
        case .albumCount: return "Album Count"
        case .recent: return "Recently Added"
        }
    }

    var orderSQL: String {
        switch self {
        case .name:
            return "LOWER(artist.name) ASC"
        case .trackCount:
            return "trackCount DESC, LOWER(artist.name) ASC"
        case .albumCount:
            return "albumCount DESC, LOWER(artist.name) ASC"
        case .recent:
            return "artist.createdAt DESC"
        }
    }
}
