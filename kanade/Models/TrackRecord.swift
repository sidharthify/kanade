//
//  TrackRecord.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import Foundation
import GRDB

// represents a single imported song.
struct TrackRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    
    // uses a standard UUID string
    var id: String
    
    var title: String
    var artist: String?
    var album: String?

    // foreign keys
    var artistId: String?
    var albumId: String?
    
    // duration in seconds
    var duration: Double

    // store the relative filename
    // iOS seems to randomly change the sandbox UUID during updates, so absolute URLs will break.
    var filename: String

    // used to prevent duplicate imports
    var sourceHash: String?

    // true if artwork was successfully extracted and cached to disk.
    var hasArtwork: Bool

    // track/disc numbers from tags, used to keep album songs in order.
    var trackNumber: Int?
    var discNumber: Int?

    // true once track/disc numbers have been scanned (guards one-time backfill).
    var numbersScanned: Bool

    // time tracking to sort "recently added"
    var addedAt: Double
    
    // table name for GRDB
    static let databaseTableName = "track"
}
