//
//  DatabaseManager.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import Foundation
import GRDB

/// Manages the GRDB SQLite database for kanade
final class DatabaseManager {

    static let shared = DatabaseManager()

    // MARK: - Database
    let dbQueue: DatabaseQueue

    private init() {
        do {
            // Store the database in Application Support
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

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "track", ifNotExists: true) { t in
                t.primaryKey("id", .text)          // uuid string
                t.column("title", .text).notNull()
                t.column("artist", .text)
                t.column("album", .text)
                t.column("duration", .double)
                t.column("fileURL", .text).notNull()
                t.column("artworkData", .blob)
                t.column("addedAt", .double).notNull()
            }
        }

        try migrator.migrate(dbQueue)
    }
}
