//
//  LibraryImporter.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import AVFoundation
import CryptoKit
import Foundation
import Observation

@Observable
final class LibraryImporter {
    var isImporting: Bool = false
    var isClearing: Bool = false
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
        
        let filesToProcess = collectFiles(from: urls, fileManager: fileManager)
        let total = filesToProcess.count
        await MainActor.run { self.totalCount = total }
        
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
        let sourceHash = fileHash(for: url)
        if let hash = sourceHash, (try? DatabaseManager.shared.containsTrack(withSourceHash: hash)) == true {
            print("[LibraryImporter] Skipped duplicate \(url.lastPathComponent)")
            return
        }

        let id = UUID().uuidString
        let ext = url.pathExtension
        let newURL = destinationURL.appendingPathComponent("\(id).\(ext)")
        let relativeFilename = "Library/\(id).\(ext)"
        
        do {
            try fileManager.copyItem(at: url, to: newURL)
            
            // extract metadata via AVAsset
            let asset = AVURLAsset(url: newURL)
            let metadata = await MetadataExtractor.extract(from: asset, fileURL: newURL)
            let durationSeconds = try? await asset.load(.duration).seconds

            let title = cleaned(metadata.title) ?? url.deletingPathExtension().lastPathComponent
            let artist = cleaned(metadata.artist) ?? "Unknown Artist"
            let album = cleaned(metadata.album) ?? "Unknown Album"
            
            var hasArtwork = false
            if let artworkData = metadata.artworkData {
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
                sourceHash: sourceHash,
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

    func clearLibrary() async {
        await MainActor.run {
            self.isClearing = true
        }

        let fileManager = FileManager.default
        guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            await finishClear()
            return
        }

        let libraryDir = docsDir.appendingPathComponent("Library", isDirectory: true)
        let artworkDir = docsDir.appendingPathComponent("Artwork", isDirectory: true)

        do {
            if fileManager.fileExists(atPath: libraryDir.path) {
                try fileManager.removeItem(at: libraryDir)
            }
            if fileManager.fileExists(atPath: artworkDir.path) {
                try fileManager.removeItem(at: artworkDir)
            }
            try fileManager.createDirectory(at: libraryDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: artworkDir, withIntermediateDirectories: true)
        } catch {
            print("[LibraryImporter] Failed to clear library files: \(error)")
        }

        do {
            try DatabaseManager.shared.clearLibrary()
        } catch {
            print("[LibraryImporter] Failed to clear database: \(error)")
        }

        await finishClear()
    }

    private func collectFiles(from urls: [URL], fileManager: FileManager) -> [URL] {
        var files: [URL] = []

        for url in urls {
            let secured = url.startAccessingSecurityScopedResource()

            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
                        for case let fileURL as URL in enumerator {
                            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                                files.append(fileURL)
                            }
                        }
                    }
                } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    files.append(url)
                }
            }

            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return files
    }

    private func fileHash(for url: URL) -> String? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var hasher = SHA256()
            while true {
                let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data)
            }

            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        } catch {
            print("[LibraryImporter] Failed to hash \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func finishClear() async {
        await MainActor.run {
            self.isClearing = false
            self.importedCount = 0
            self.totalCount = 0
        }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

