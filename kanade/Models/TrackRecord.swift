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
    
    // duration in seconds
    var duration: Double
    
    // store the relative filename
    // iOS seems to randomly change the sandbox UUID during updates, so absolute URLs will break.
    var filename: String
    
    // true if artwork was successfully extracted and cached to disk.
    var hasArtwork: Bool
    
    // time tracking to sort "recently added"
    var addedAt: Double
    
    // table name for GRDB
    static let databaseTableName = "track"
}
