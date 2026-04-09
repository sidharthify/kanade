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

        // artist + album tables and foreign keys on track.
        migrator.registerMigration("v3_library_entities") { db in
            try db.create(table: "artist", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("sortName", .text).notNull()
                t.column("createdAt", .double).notNull()
            }

            try db.create(table: "album", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("sortName", .text).notNull()
                t.column("artistId", .text)
                t.column("createdAt", .double).notNull()
            }

            try db.alter(table: "track") { t in
                t.add(column: "artistId", .text)
                t.add(column: "albumId", .text)
            }

            let now = Date().timeIntervalSince1970

            // backfill artists
            let artistRows = try Row.fetchAll(
                db,
                sql: "SELECT DISTINCT artist FROM track WHERE artist IS NOT NULL AND artist != ''"
            )
            var artistIdByKey: [String: String] = [:]
            for row in artistRows {
                let name: String = row["artist"]
                let key = Self.normalizeKey(name)
                if artistIdByKey[key] != nil { continue }

                let id = UUID().uuidString
                try db.execute(
                    sql: "INSERT INTO artist (id, name, sortName, createdAt) VALUES (?, ?, ?, ?)",
                    arguments: [id, name, key, now]
                )
                artistIdByKey[key] = id
            }

            for (key, id) in artistIdByKey {
                try db.execute(
                    sql: "UPDATE track SET artistId = ? WHERE artist IS NOT NULL AND LOWER(artist) = ?",
                    arguments: [id, key]
                )
            }

            // backfill albums
            struct AlbumKey: Hashable {
                let key: String
                let artistId: String?
            }

            let albumRows = try Row.fetchAll(
                db,
                sql: "SELECT DISTINCT album, artistId FROM track WHERE album IS NOT NULL AND album != ''"
            )
            var albumIdByKey: [AlbumKey: String] = [:]
            for row in albumRows {
                let name: String = row["album"]
                let artistId: String? = row["artistId"]
                let key = Self.normalizeKey(name)
                let albumKey = AlbumKey(key: key, artistId: artistId)

                if albumIdByKey[albumKey] == nil {
                    let id = UUID().uuidString
                    try db.execute(
                        sql: "INSERT INTO album (id, name, sortName, artistId, createdAt) VALUES (?, ?, ?, ?, ?)",
                        arguments: [id, name, key, artistId, now]
                    )
                    albumIdByKey[albumKey] = id
                }

                guard let albumId = albumIdByKey[albumKey] else { continue }
                if let artistId {
                    try db.execute(
                        sql: "UPDATE track SET albumId = ? WHERE album IS NOT NULL AND LOWER(album) = ? AND artistId = ?",
                        arguments: [albumId, key, artistId]
                    )
                } else {
                    try db.execute(
                        sql: "UPDATE track SET albumId = ? WHERE album IS NOT NULL AND LOWER(album) = ? AND artistId IS NULL",
                        arguments: [albumId, key]
                    )
                }
            }
        }

        migrator.registerMigration("v4_source_hash") { db in
            try db.alter(table: "track") { t in
                t.add(column: "sourceHash", .text)
            }
            try db.create(index: "track_sourceHash_idx", on: "track", columns: ["sourceHash"])
        }

        try migrator.migrate(dbQueue)
    }
    
    // MARK: - CRUD

    func insert(_ track: TrackRecord) throws {
        try dbQueue.write { db in
            try track.insert(db)
        }
    }

    func insertImportedTrack(_ payload: TrackImportPayload) throws {
        try dbQueue.write { db in
            let artist = try upsertArtist(in: db, name: payload.artist)
            let album = try upsertAlbum(in: db, name: payload.album, artistId: artist.id)

            let track = TrackRecord(
                id: payload.id,
                title: payload.title,
                artist: payload.artist,
                album: payload.album,
                artistId: artist.id,
                albumId: album.id,
                duration: payload.duration,
                filename: payload.filename,
                sourceHash: payload.sourceHash,
                hasArtwork: payload.hasArtwork,
                addedAt: payload.addedAt
            )
            try track.insert(db)
        }
    }

    func containsTrack(withSourceHash hash: String) throws -> Bool {
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT 1 FROM track WHERE sourceHash = ? LIMIT 1",
                arguments: [hash]
            )
            return row != nil
        }
    }

    func clearLibrary() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM track")
            try db.execute(sql: "DELETE FROM album")
            try db.execute(sql: "DELETE FROM artist")
        }
    }

    func fetchAllTracks() throws -> [TrackRecord] {
        try fetchTracks(search: nil, sort: .recent)
    }

    func fetchTracks(search: String?, sort: TrackSort) throws -> [TrackRecord] {
        try dbQueue.read { db in
            var sql = "SELECT * FROM track"
            var args: [DatabaseValueConvertible] = []

            if let search = search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
                let like = "%\(search)%"
                sql += " WHERE (title LIKE ? COLLATE NOCASE OR artist LIKE ? COLLATE NOCASE OR album LIKE ? COLLATE NOCASE)"
                args = [like, like, like]
            }

            sql += " ORDER BY \(sort.orderSQL)"
            return try TrackRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    func fetchTracks(forAlbumId albumId: String) throws -> [TrackRecord] {
        try dbQueue.read { db in
            try TrackRecord.fetchAll(
                db,
                sql: "SELECT * FROM track WHERE albumId = ? ORDER BY LOWER(title) ASC",
                arguments: [albumId]
            )
        }
    }

    func fetchTracks(forArtistId artistId: String) throws -> [TrackRecord] {
        try dbQueue.read { db in
            try TrackRecord.fetchAll(
                db,
                sql: "SELECT * FROM track WHERE artistId = ? ORDER BY LOWER(album) ASC, LOWER(title) ASC",
                arguments: [artistId]
            )
        }
    }

    func fetchAlbumSummaries(search: String?, sort: AlbumSort) throws -> [AlbumSummary] {
        try dbQueue.read { db in
            var sql = """
                SELECT album.id,
                       album.name,
                       artist.name AS artistName,
                       COUNT(track.id) AS trackCount,
                       MAX(CASE WHEN track.hasArtwork = 1 THEN track.id END) AS artworkTrackId
                FROM album
                LEFT JOIN artist ON artist.id = album.artistId
                LEFT JOIN track ON track.albumId = album.id
            """

            var args: [DatabaseValueConvertible] = []
            if let search = search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
                let like = "%\(search)%"
                sql += " WHERE (album.name LIKE ? COLLATE NOCASE OR COALESCE(artist.name, '') LIKE ? COLLATE NOCASE)"
                args = [like, like]
            }

            sql += " GROUP BY album.id"
            sql += " ORDER BY \(sort.orderSQL)"
            return try AlbumSummary.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    func fetchArtistSummaries(search: String?, sort: ArtistSort) throws -> [ArtistSummary] {
        try dbQueue.read { db in
            var sql = """
                SELECT artist.id,
                       artist.name,
                       COUNT(DISTINCT track.id) AS trackCount,
                       COUNT(DISTINCT album.id) AS albumCount,
                       MAX(CASE WHEN track.hasArtwork = 1 THEN track.id END) AS artworkTrackId
                FROM artist
                LEFT JOIN track ON track.artistId = artist.id
                LEFT JOIN album ON album.artistId = artist.id
            """

            var args: [DatabaseValueConvertible] = []
            if let search = search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
                let like = "%\(search)%"
                sql += " WHERE artist.name LIKE ? COLLATE NOCASE"
                args = [like]
            }

            sql += " GROUP BY artist.id"
            sql += " ORDER BY \(sort.orderSQL)"
            return try ArtistSummary.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    // MARK: - Helpers

    private func upsertArtist(in db: Database, name: String) throws -> ArtistRecord {
        let key = Self.normalizeKey(name)
        if let existing = try ArtistRecord.filter(Column("sortName") == key).fetchOne(db) {
            return existing
        }

        let artist = ArtistRecord(
            id: UUID().uuidString,
            name: name,
            sortName: key,
            createdAt: Date().timeIntervalSince1970
        )
        try artist.insert(db)
        return artist
    }

    private func upsertAlbum(in db: Database, name: String, artistId: String?) throws -> AlbumRecord {
        let key = Self.normalizeKey(name)
        var request = AlbumRecord.filter(Column("sortName") == key)
        if let artistId {
            request = request.filter(Column("artistId") == artistId)
        } else {
            request = request.filter(Column("artistId") == nil)
        }

        if let existing = try request.fetchOne(db) {
            return existing
        }

        let album = AlbumRecord(
            id: UUID().uuidString,
            name: name,
            sortName: key,
            artistId: artistId,
            createdAt: Date().timeIntervalSince1970
        )
        try album.insert(db)
        return album
    }

    private static func normalizeKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// payload for importer-to-db inserts.
struct TrackImportPayload {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let filename: String
    let sourceHash: String?
    let hasArtwork: Bool
    let addedAt: Double
}
