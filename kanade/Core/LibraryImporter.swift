//
//  LibraryImporter.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import AVFoundation
import Foundation
import Observation

@Observable
final class LibraryImporter {
    var isImporting: Bool = false
    var importedCount: Int = 0
    var totalCount: Int = 0
    
    // supported file extensions for audio, maybe add more later
    private let supportedExtensions: Set<String> = ["mp3", "m4a", "flac", "wav", "aac"]
    
    // extract metadata and copy files into the app sandbox
    func importFiles(from urls: [URL]) async {
        await MainActor.run {
            self.isImporting = true
            self.importedCount = 0
            self.totalCount = 0
        }
        
        let fileManager = FileManager.default
        var filesToProcess: [URL] = []
        
        // ensure dirs exist
        guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let libraryDir = docsDir.appendingPathComponent("Library", isDirectory: true)
        let artworkDir = docsDir.appendingPathComponent("Artwork", isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: libraryDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: artworkDir, withIntermediateDirectories: true)
        } catch {
            print("[LibraryImporter] Failed to create directories: \(error)")
            await finishImport()
            return
        }
        
        // scan selected urls
        for url in urls {
            // safely access security-scoped resources
            let secured = url.startAccessingSecurityScopedResource()
            
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
                        for case let fileURL as URL in enumerator {
                            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                                filesToProcess.append(fileURL)
                            }
                        }
                    }
                } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    filesToProcess.append(url)
                }
            }
            
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        await MainActor.run { self.totalCount = filesToProcess.count }
        
        for file in filesToProcess {
            let secured = file.startAccessingSecurityScopedResource()
            await processFile(file, destinationURL: libraryDir, artworkURL: artworkDir)
            if secured { file.stopAccessingSecurityScopedResource() }
            
            await MainActor.run { self.importedCount += 1 }
        }
        
        await finishImport()
    }
    
    private func processFile(_ url: URL, destinationURL: URL, artworkURL: URL) async {
        let fileManager = FileManager.default
        let id = UUID().uuidString
        let ext = url.pathExtension
        let newURL = destinationURL.appendingPathComponent("\(id).\(ext)")
        let relativeFilename = "Library/\(id).\(ext)"
        
        do {
            try fileManager.copyItem(at: url, to: newURL)
            
            // extract metadata via AVAsset
            let asset = AVURLAsset(url: newURL)
            let metadata = try? await asset.load(.commonMetadata)
            let durationSeconds = try? await asset.load(.duration).seconds
            
            let title = cleaned(metadata?.title) ?? url.deletingPathExtension().lastPathComponent
            let artist = cleaned(metadata?.artist) ?? "Unknown Artist"
            let album = cleaned(metadata?.album) ?? "Unknown Album"
            
            var hasArtwork = false
            if let artworkData = metadata?.artworkData {
                let artworkDest = artworkURL.appendingPathComponent("\(id).jpg")
                try? artworkData.write(to: artworkDest)
                hasArtwork = true
            }
            
            let payload = TrackImportPayload(
                id: id,
                title: title,
                artist: artist,
                album: album,
                duration: durationSeconds ?? 0,
                filename: relativeFilename,
                hasArtwork: hasArtwork,
                addedAt: Date().timeIntervalSince1970
            )

            try DatabaseManager.shared.insertImportedTrack(payload)
            
        } catch {
            print("[LibraryImporter] Failed to process \(url.lastPathComponent): \(error)")
        }
    }
    
    private func finishImport() async {
        await MainActor.run {
            self.isImporting = false
        }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

// helper functions for parsing common metadata out of AVAsset, might change
private extension Array where Element == AVMetadataItem {
    var title: String? { stringValue(for: .commonKeyTitle) }
    var artist: String? { stringValue(for: .commonKeyArtist) }
    var album: String? { stringValue(for: .commonKeyAlbumName) }
    var artworkData: Data? {
        first(where: { $0.commonKey == .commonKeyArtwork })?.dataValue
    }
    
    private func stringValue(for key: AVMetadataKey) -> String? {
        first(where: { $0.commonKey == key })?.stringValue
    }
}
