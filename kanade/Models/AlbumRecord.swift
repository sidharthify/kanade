//
//  AlbumRecord.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import Foundation
import GRDB

// represents a single album in the library.
struct AlbumRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    var id: String
    var name: String
    var sortName: String
    var artistId: String?
    var createdAt: Double

    static let databaseTableName = "album"
}
