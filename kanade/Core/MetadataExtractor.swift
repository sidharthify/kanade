//
//  MetadataExtractor.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import AVFoundation
import Foundation

struct AssetMetadata {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let trackNumber: Int?
    let discNumber: Int?
}

enum MetadataExtractor {
    static func extract(from asset: AVURLAsset, fileURL: URL? = nil) async -> AssetMetadata {
        let common = (try? await asset.load(.commonMetadata)) ?? []
        let metadata = (try? await asset.load(.metadata)) ?? []
        let items = common + metadata

        let title = await items.firstString(
            commonKey: .commonKeyTitle,
            keyStrings: ["title"]
        )
        let artist = await items.firstString(
            commonKey: .commonKeyArtist,
            keyStrings: ["artist", "albumartist", "album artist", "album_artist", "performer"]
        )
        let album = await items.firstString(
            commonKey: .commonKeyAlbumName,
            keyStrings: ["album"]
        )
        // prefer AVFoundation metadata, then fall back to raw FLAC parsing.
        var artwork = await items.firstData(
            commonKey: .commonKeyArtwork,
            keyStrings: ["metadata_block_picture", "coverart", "cover", "picture", "artwork"]
        )

        var trackNumber = await items.firstInt(
            identifiers: [.id3MetadataTrackNumber, .iTunesMetadataTrackNumber],
            keyStrings: ["track", "tracknumber", "tracknum", "trkn"]
        )
        var discNumber = await items.firstInt(
            identifiers: [.id3MetadataPartOfASet, .iTunesMetadataDiscNumber],
            keyStrings: ["disc", "discnumber", "disknumber", "disk", "disknum"]
        )

        // AVFoundation doesn't surface Vorbis comments (track/disc numbers) for FLAC,
        // so parse the FLAC VORBIS_COMMENT block directly as a fallback.
        if let url = fileURL, url.pathExtension.lowercased() == "flac" {
            if artwork == nil {
                artwork = ArtworkExtractor.flacArtwork(from: url)
            }
            if trackNumber == nil || discNumber == nil {
                let comments = ArtworkExtractor.flacVorbisComments(from: url)
                if trackNumber == nil { trackNumber = parseLeadingInt(comments["TRACKNUMBER"]) }
                if discNumber == nil { discNumber = parseLeadingInt(comments["DISCNUMBER"]) }
            }
        }

        return AssetMetadata(
            title: title,
            artist: artist,
            album: album,
            artworkData: artwork,
            trackNumber: trackNumber,
            discNumber: discNumber
        )
    }
}

// parses the leading integer from a tag value like "3", "3/12", or " 04 ".
func parseLeadingInt(_ value: String?) -> Int? {
    guard let value else { return nil }
    let head = value.split(separator: "/").first.map(String.init) ?? value
    let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let n = Int(trimmed), n > 0 else { return nil }
    return n
}

private extension Array where Element == AVMetadataItem {
    func firstString(commonKey: AVMetadataKey, keyStrings: [String]) async -> String? {
        if let item = first(where: { $0.commonKey == commonKey }) {
            return try? await item.load(.stringValue)
        }

        let lowered = Set(keyStrings.map { $0.lowercased() })
        if let item = first(where: { matches($0, in: lowered) }) {
            return try? await item.load(.stringValue)
        }

        return nil
    }

    func firstData(commonKey: AVMetadataKey, keyStrings: [String]) async -> Data? {
        if let item = first(where: { $0.commonKey == commonKey }) {
            if let data = try? await item.load(.dataValue) {
                return ArtworkExtractor.normalize(data)
            }
        }

        let lowered = Set(keyStrings.map { $0.lowercased() })
        let candidates = filter { matches($0, in: lowered) }
        for item in candidates {
            if let data = try? await item.load(.dataValue), let normalized = ArtworkExtractor.normalize(data) {
                return normalized
            }
            if let stringValue = try? await item.load(.stringValue),
               let decoded = Data(base64Encoded: stringValue),
               let normalized = ArtworkExtractor.normalize(decoded) {
                return normalized
            }
        }

        return nil
    }

    func firstInt(identifiers: [AVMetadataIdentifier], keyStrings: [String]) async -> Int? {
        // try known identifiers first (ID3 TRCK/TPOS, iTunes trkn/disk)
        for identifier in identifiers {
            guard let item = first(where: { $0.identifier == identifier }) else { continue }
            if let number = try? await item.load(.numberValue) { return number.intValue }
            if let string = try? await item.load(.stringValue), let value = parseLeadingInt(string) { return value }
            if let data = try? await item.load(.dataValue), let value = Self.parseTrackNumberData(data) { return value }
        }

        // fall back to matching raw key strings
        let lowered = Set(keyStrings.map { $0.lowercased() })
        if let item = first(where: { matches($0, in: lowered) }) {
            if let string = try? await item.load(.stringValue), let value = parseLeadingInt(string) { return value }
            if let number = try? await item.load(.numberValue) { return number.intValue }
            if let data = try? await item.load(.dataValue), let value = Self.parseTrackNumberData(data) { return value }
        }

        return nil
    }

    // iTunes trkn/disk atoms are binary, laid out as [00 00, trackHi trackLo, totalHi totalLo, ...].
    private static func parseTrackNumberData(_ data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        let value = (Int(bytes[2]) << 8) | Int(bytes[3])
        return value > 0 ? value : nil
    }

    private func matches(_ item: AVMetadataItem, in keys: Set<String>) -> Bool {
        guard let key = keyString(for: item)?.lowercased() else { return false }
        return keys.contains(key)
    }

    private func keyString(for item: AVMetadataItem) -> String? {
        if let key = item.key as? String {
            return key
        }
        if let key = item.key as? NSString {
            return key as String
        }
        return nil
    }
}

private enum ArtworkExtractor {
    static func normalize(_ data: Data) -> Data? {
        if isJPEG(data) || isPNG(data) {
            return data
        }
        if let extracted = extractFromFlacPictureBlock(data) {
            if isJPEG(extracted) || isPNG(extracted) {
                return extracted
            }
            return extracted
        }
        return nil
    }

    // decode a FLAC PICTURE block payload (not the full FLAC file).
    static func extractFromFlacPictureBlock(_ data: Data) -> Data? {
        var cursor = 0

        func readUInt32() -> UInt32? {
            guard data.count >= cursor + 4 else { return nil }
            let value = data[cursor..<(cursor + 4)].reduce(UInt32(0)) { result, byte in
                (result << 8) | UInt32(byte)
            }
            cursor += 4
            return value
        }

        func readData(length: Int) -> Data? {
            guard length >= 0, data.count >= cursor + length else { return nil }
            let chunk = data[cursor..<(cursor + length)]
            cursor += length
            return Data(chunk)
        }

        _ = readUInt32()
        guard let mimeLength = readUInt32(),
              let _ = readData(length: Int(mimeLength)),
              let descriptionLength = readUInt32(),
              let _ = readData(length: Int(descriptionLength)),
              readUInt32() != nil,
              readUInt32() != nil,
              readUInt32() != nil,
              readUInt32() != nil,
              let dataLength = readUInt32(),
              let imageData = readData(length: Int(dataLength)) else {
            return nil
        }

        return imageData
    }

    // parse FLAC metadata blocks to find and extract a PICTURE block.
    static func flacArtwork(from url: URL) -> Data? {
        guard url.pathExtension.lowercased() == "flac" else { return nil }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            guard let signature = try readExactly(from: handle, count: 4),
                  signature == Data([0x66, 0x4C, 0x61, 0x43]) else {
                return nil
            }

            while true {
                guard let header = try readExactly(from: handle, count: 4) else { return nil }
                let first = header[0]
                let isLast = (first & 0x80) != 0
                let type = Int(first & 0x7F)
                let length = (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])

                guard let blockData = try readExactly(from: handle, count: length) else { return nil }
                // type 6 = PICTURE metadata block.
                if type == 6, let imageData = extractFromFlacPictureBlock(blockData) {
                    return imageData
                }

                if isLast { break }
            }
        } catch {
            print("[MetadataExtractor] Failed to read FLAC artwork: \(error)")
        }

        return nil
    }

    // parse FLAC metadata blocks to find and decode the VORBIS_COMMENT block,
    // returning tag key/value pairs with upper-cased keys like "TRACKNUMBER".
    static func flacVorbisComments(from url: URL) -> [String: String] {
        guard url.pathExtension.lowercased() == "flac" else { return [:] }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            guard let signature = try readExactly(from: handle, count: 4),
                  signature == Data([0x66, 0x4C, 0x61, 0x43]) else {
                return [:]
            }

            while true {
                guard let header = try readExactly(from: handle, count: 4) else { return [:] }
                let first = header[0]
                let isLast = (first & 0x80) != 0
                let type = Int(first & 0x7F)
                let length = (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])

                guard let blockData = try readExactly(from: handle, count: length) else { return [:] }
                // type 4 = VORBIS_COMMENT metadata block.
                if type == 4 {
                    return parseVorbisComments([UInt8](blockData))
                }

                if isLast { break }
            }
        } catch {
            print("[MetadataExtractor] Failed to read FLAC vorbis comments: \(error)")
        }

        return [:]
    }

    // Vorbis comment payload has a vendor length and vendor string, then a list
    // of "KEY=value" entries. All lengths are little-endian uint32.
    private static func parseVorbisComments(_ bytes: [UInt8]) -> [String: String] {
        var cursor = 0

        func readUInt32LE() -> Int? {
            guard cursor + 4 <= bytes.count else { return nil }
            let value = Int(bytes[cursor])
                | (Int(bytes[cursor + 1]) << 8)
                | (Int(bytes[cursor + 2]) << 16)
                | (Int(bytes[cursor + 3]) << 24)
            cursor += 4
            return value
        }

        guard let vendorLength = readUInt32LE(), vendorLength >= 0 else { return [:] }
        cursor += vendorLength
        guard let count = readUInt32LE(), count >= 0 else { return [:] }

        var result: [String: String] = [:]
        for _ in 0..<count {
            guard let length = readUInt32LE(), length >= 0, cursor + length <= bytes.count else { break }
            let slice = bytes[cursor..<(cursor + length)]
            cursor += length

            guard let comment = String(bytes: slice, encoding: .utf8),
                  let separator = comment.firstIndex(of: "=") else { continue }
            let key = comment[..<separator].uppercased()
            let value = String(comment[comment.index(after: separator)...])
            if result[key] == nil {
                result[key] = value
            }
        }

        return result
    }

    // read a fixed number of bytes from the file handle.
    private static func readExactly(from handle: FileHandle, count: Int) throws -> Data? {
        var data = Data()
        var remaining = count

        while remaining > 0 {
            let chunk = try handle.read(upToCount: remaining) ?? Data()
            if chunk.isEmpty { return nil }
            data.append(chunk)
            remaining -= chunk.count
        }

        return data
    }

    private static func isJPEG(_ data: Data) -> Bool {
        data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
    }

    private static func isPNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= signature.count else { return false }
        return data.prefix(signature.count).elementsEqual(signature)
    }
}
