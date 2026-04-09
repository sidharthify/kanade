//
//  DatabaseManager.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import Foundation
import GRDB

/// manage grdb sqlite database for kanade
final class DatabaseManager {

    static let shared = DatabaseManager()

    // MARK: - Database
    let dbQueue: DatabaseQueue

    private init() {
        do {
            // store the database in app support
            let supportDir = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = supportDir.appendingPathComponent("kanade.db")

            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }

            dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
            try migrate()
        } catch {
            fatalError("[DatabaseManager] Failed to open database: \(error)")
        }
    }

    // MARK: - Migrations
    private func migrate() throws {
        var migrator = DatabaseMigrator()

        // initial schema, might change
        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "track", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("artist", .text)
                t.column("album", .text)
                t.column("duration", .double)
                t.column("fileURL", .text).notNull()
                t.column("artworkData", .blob)
                t.column("addedAt", .double).notNull()
            }
        }

        // update schema to store relative filenames instead of absolute URLs, and drop artwork blobs.
        migrator.registerMigration("v2_sanitise_track") { db in
            try db.alter(table: "track") { t in
                t.add(column: "filename", .text)
                t.add(column: "hasArtwork", .boolean).defaults(to: false)
                t.drop(column: "fileURL")
                t.drop(column: "artworkData")
            }
        }

        try migrator.migrate(dbQueue)
    }
    
    // MARK: - CRUD
    
    func insert(_ track: TrackRecord) throws {
        try dbQueue.write { db in
            try track.insert(db)
        }
    }
    
    func fetchAllTracks() throws -> [TrackRecord] {
        try dbQueue.read { db in
            try TrackRecord.order(Column("addedAt").desc).fetchAll(db)
        }
    }
}
