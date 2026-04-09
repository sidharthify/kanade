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
}

enum MetadataExtractor {
    static func extract(from asset: AVURLAsset) async -> AssetMetadata {
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
        let artwork = await items.firstData(
            commonKey: .commonKeyArtwork,
            keyStrings: ["metadata_block_picture", "coverart", "cover", "picture", "artwork"]
        )

        return AssetMetadata(
            title: title,
            artist: artist,
            album: album,
            artworkData: artwork
        )
    }
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
        if let extracted = parseFlacPictureBlock(data) {
            if isJPEG(extracted) || isPNG(extracted) {
                return extracted
            }
            return extracted
        }
        return nil
    }

    private static func parseFlacPictureBlock(_ data: Data) -> Data? {
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

    private static func isJPEG(_ data: Data) -> Bool {
        data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
    }

    private static func isPNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= signature.count else { return false }
        return data.prefix(signature.count).elementsEqual(signature)
    }
}
