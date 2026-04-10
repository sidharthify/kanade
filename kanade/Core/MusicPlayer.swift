//
//  MusicPlayer.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import AVFoundation
import Observation
import MediaPlayer

enum RepeatMode: Int {
    case off, one, all
}

@Observable
final class MusicPlayer {

    // MARK: - Public state
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentURL: URL? = nil
    var currentTitle: String = "No track loaded"
    var currentArtist: String? = nil
    var currentAlbum: String? = nil
    var currentTrackId: String? = nil
    var currentHasArtwork: Bool = false

    // Queue
    var queue: [TrackRecord] = []
    var currentQueueIndex: Int = 0

    // Playback modes
    var shuffleEnabled: Bool = false
    var repeatMode: RepeatMode = .off

    var hasTrackLoaded: Bool { currentURL != nil }

    var currentArtworkURL: URL? {
        guard currentHasArtwork, let trackId = currentTrackId else { return nil }
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docsDir.appendingPathComponent("Artwork").appendingPathComponent("\(trackId).jpg")
    }

    // MARK: - Private audio graph
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let mixerNode = AVAudioMixerNode()
    private let eq = EQManager.shared

    // audio format info for display (e.g. "FLAC · 1011 kbps · 48000")
    var audioFormatLabel: String = ""

    private var audioFile: AVAudioFile?
    private var sampleRate: Double = 44100
    private var frameCount: AVAudioFrameCount = 0

    private var progressTimer: Timer?
    private var currentSeekOffset: TimeInterval = 0
    private var scheduleToken: Int = 0

    // Tracks which indices have been played when shuffling
    private var shuffledHistory: [Int] = []

    // MARK: - Init
    init() {
        setupAudioSession()
        setupEngine()
        setupRemoteTransportControls()
        observeInterruptions()
        observeRouteChanges()
        becomeFirstResponder()
    }

    // MARK: - Session
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("[MusicPlayer] AudioSession error: \(error)")
        }
    }

    private func becomeFirstResponder() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    // MARK: - Engine graph
    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(mixerNode)
        engine.attach(eq.eqNode)

        // signal path: playerNode -> eq -> mixer -> output
        engine.connect(playerNode, to: eq.eqNode, format: nil)
        engine.connect(eq.eqNode, to: mixerNode, format: nil)
        engine.connect(mixerNode, to: engine.mainMixerNode, format: nil)

        do {
            try engine.start()
        } catch {
            print("[MusicPlayer] Engine start error: \(error)")
        }
    }

    // MARK: - Queue loading

    // Load a list of tracks and start at a given index. This is the main entry point for the library.
    func loadQueue(tracks: [TrackRecord], startingAt index: Int) {
        queue = tracks
        currentQueueIndex = max(0, min(index, tracks.count - 1))
        shuffledHistory = [currentQueueIndex]
        playCurrentQueueItem()
    }

    private func playCurrentQueueItem() {
        guard currentQueueIndex < queue.count else { return }
        let track = queue[currentQueueIndex]
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docsDir.appendingPathComponent(track.filename)
        load(
            url: url,
            trackId: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            hasArtwork: track.hasArtwork
        )
        play()
    }

    // MARK: - Skip
    func skipNext() {
        guard !queue.isEmpty else { return }

        if repeatMode == .one {
            seek(to: 0)
            play()
            return
        }

        if shuffleEnabled {
            let remaining = (0..<queue.count).filter { !shuffledHistory.contains($0) }
            if let next = remaining.randomElement() {
                currentQueueIndex = next
                shuffledHistory.append(next)
            } else {
                // played everything — reset and continue if repeat all
                shuffledHistory = []
                if repeatMode == .all, let first = (0..<queue.count).randomElement() {
                    currentQueueIndex = first
                    shuffledHistory = [first]
                } else {
                    return
                }
            }
        } else {
            let next = currentQueueIndex + 1
            if next < queue.count {
                currentQueueIndex = next
            } else if repeatMode == .all {
                currentQueueIndex = 0
            } else {
                return
            }
        }
        playCurrentQueueItem()
    }

    func skipPrevious() {
        guard !queue.isEmpty else { return }

        // go back to start of current track if we're more than 3s in
        if currentTime > 3 {
            seek(to: 0)
            return
        }

        if shuffleEnabled, let prev = shuffledHistory.dropLast().last {
            shuffledHistory.removeLast()
            currentQueueIndex = prev
        } else {
            let prev = currentQueueIndex - 1
            if prev >= 0 {
                currentQueueIndex = prev
            } else if repeatMode == .all {
                currentQueueIndex = queue.count - 1
            } else {
                seek(to: 0)
                return
            }
        }
        playCurrentQueueItem()
    }

    // MARK: - Load (single file, internal or direct use)
    func load(
        url: URL,
        trackId: String? = nil,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        hasArtwork: Bool = false
    ) {
        stop()
        currentURL = url
        currentSeekOffset = 0
        currentTrackId = trackId
        currentHasArtwork = hasArtwork
        currentAlbum = album

        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            frameCount = AVAudioFrameCount(file.length)
            let computedDuration = sampleRate > 0 ? Double(frameCount) / sampleRate : 0
            duration = computedDuration.isFinite ? max(0, computedDuration) : 0

            if let title = title, !title.isEmpty {
                self.currentTitle = title
                self.currentArtist = artist
            } else {
                let asset = AVURLAsset(url: url)
                Task {
                    let metadata = await MetadataExtractor.extract(from: asset, fileURL: url)
                    await MainActor.run {
                        self.currentTitle = metadata.title ?? url.deletingPathExtension().lastPathComponent
                        self.currentArtist = metadata.artist
                        if self.currentAlbum == nil { self.currentAlbum = metadata.album }
                    }
                }
            }

            // build format label for display in the seek bar
            audioFormatLabel = buildFormatLabel(for: file)

            scheduleFile()
            updateNowPlayingInfo()

            // fetch lyrics asynchronously
            if let trackId {
                LyricsManager.shared.fetchLyrics(
                    for: trackId,
                    title: title ?? url.deletingPathExtension().lastPathComponent,
                    artist: artist,
                    album: album,
                    duration: duration
                )
            }
        } catch {
            print("[MusicPlayer] Load error: \(error)")
        }
    }

    private func scheduleFile() {
        guard let file = audioFile else { return }
        let token = nextScheduleToken()
        playerNode.scheduleFile(file, at: nil) { [weak self] in
            guard let self, self.scheduleToken == token else { return }
            DispatchQueue.main.async { self.handlePlaybackFinished() }
        }
    }

    private func scheduleSegment(startingFrame: AVAudioFramePosition, frameCount: AVAudioFrameCount) {
        guard let file = audioFile else { return }
        let token = nextScheduleToken()
        playerNode.scheduleSegment(file, startingFrame: startingFrame, frameCount: frameCount, at: nil) { [weak self] in
            guard let self, self.scheduleToken == token else { return }
            DispatchQueue.main.async { self.handlePlaybackFinished() }
        }
    }

    private func nextScheduleToken() -> Int { scheduleToken += 1; return scheduleToken }
    private func invalidateSchedule() { scheduleToken += 1 }

    // MARK: - Playback controls
    func play() {
        guard audioFile != nil else { return }
        if !engine.isRunning { try? engine.start() }
        playerNode.play()
        isPlaying = true
        startProgressTimer()
        updateNowPlayingInfo()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopProgressTimer()
        updateNowPlayingInfo()
    }

    func stop() {
        invalidateSchedule()
        playerNode.stop()
        isPlaying = false
        currentTime = 0
        currentSeekOffset = 0
        stopProgressTimer()
    }

    func seek(to time: TimeInterval) {
        guard audioFile != nil else { return }
        let wasPlaying = isPlaying
        let safeDuration = duration.isFinite ? max(0, duration) : 0
        let clampedTime = min(max(0, time), safeDuration)
        invalidateSchedule()
        playerNode.stop()

        let seekFrame = AVAudioFramePosition(clampedTime * sampleRate)
        let safeFrame = max(0, min(seekFrame, AVAudioFramePosition(frameCount)))
        let remainingFrames = AVAudioFrameCount(AVAudioFramePosition(frameCount) - safeFrame)

        guard remainingFrames > 0 else {
            currentSeekOffset = safeDuration
            currentTime = safeDuration
            isPlaying = false
            stopProgressTimer()
            updateNowPlayingInfo()
            return
        }

        scheduleSegment(startingFrame: safeFrame, frameCount: remainingFrames)
        currentSeekOffset = Double(safeFrame) / sampleRate
        currentTime = currentSeekOffset

        if wasPlaying { playerNode.play() }
        updateNowPlayingInfo()
    }

    // MARK: - Progress timer
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateCurrentTime() {
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
          guard playerTime.sampleRate.isFinite, playerTime.sampleRate > 0 else { return }
          let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
          guard elapsed.isFinite else { return }
          let safeDuration = duration.isFinite ? max(0, duration) : 0
          currentTime = min(max(0, currentSeekOffset + elapsed), safeDuration)
    }

    private func handlePlaybackFinished() {
        isPlaying = false
        currentTime = duration
        stopProgressTimer()
        // auto-advance queue if there's more to play
        if repeatMode == .one {
            seek(to: 0)
            play()
        } else {
            skipNext()
        }
    }

    // MARK: - Now Playing
    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentTitle
        info[MPMediaItemPropertyArtist] = currentArtist ?? ""
        info[MPMediaItemPropertyAlbumTitle] = currentAlbum ?? ""
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        if let artworkURL = currentArtworkURL, let image = UIImage(contentsOfFile: artworkURL.path) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote controls
    private func setupRemoteTransportControls() {
        let cmd = MPRemoteCommandCenter.shared()

        cmd.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        cmd.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        cmd.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            isPlaying ? pause() : play()
            return .success
        }
        cmd.nextTrackCommand.addTarget { [weak self] _ in self?.skipNext(); return .success }
        cmd.previousTrackCommand.addTarget { [weak self] _ in self?.skipPrevious(); return .success }
        cmd.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }

    // MARK: - Interruptions
    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            switch type {
            case .began: self?.pause()
            case .ended:
                if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                   AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                    self?.play()
                }
            @unknown default: break
            }
        }
    }

    // MARK: - Format label

    private func buildFormatLabel(for file: AVAudioFile) -> String {
        let format = file.processingFormat
        let rate = Int(format.sampleRate)

        // guess the codec name from the file extension since AVAudioFile doesn't expose it directly
        let ext = file.url.pathExtension.uppercased()
        let codec: String
        switch ext {
        case "FLAC": codec = "FLAC"
        case "M4A", "AAC": codec = "AAC"
        case "MP3": codec = "MP3"
        case "WAV", "AIFF": codec = ext
        default: codec = ext.isEmpty ? "PCM" : ext
        }

        // approximate bitrate from file size / duration
        var bitrateStr = ""
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.url.path),
           let size = attrs[.size] as? Int64,
           duration > 0 {
            let kbps = Int((Double(size) * 8) / (duration * 1000))
            bitrateStr = " · \(kbps) kbps"
        }

        return "\(codec)\(bitrateStr) · \(rate)"
    }

    // MARK: - Route changes
    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
            if reason == .oldDeviceUnavailable { self?.pause() }
        }
    }
}
