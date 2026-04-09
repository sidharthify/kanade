//
//  ArtistRecord.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import Foundation
import GRDB

// represents a single artist in the library.
struct ArtistRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    var id: String
    var name: String
    var sortName: String
    var createdAt: Double

    static let databaseTableName = "artist"
}
