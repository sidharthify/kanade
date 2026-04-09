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
            keyStrings: ["metadata_block_picture", "coverart", "coverartmime", "cover"]
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
            return try? await item.load(.dataValue)
        }

        let lowered = Set(keyStrings.map { $0.lowercased() })
        if let item = first(where: { matches($0, in: lowered) }) {
            if let data = try? await item.load(.dataValue) {
                return data
            }
            if let stringValue = try? await item.load(.stringValue) {
                return Data(base64Encoded: stringValue)
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
