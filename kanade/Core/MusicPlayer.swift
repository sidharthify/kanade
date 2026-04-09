//
//  MusicPlayer.swift
//  kanade
//
//  Copyright © 2026 sidharthify.
//

import AVFoundation
import Observation
import MediaPlayer

@Observable
final class MusicPlayer {

    // MARK: - Values
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentURL: URL? = nil
    var currentTitle: String = "No track loaded"
    var currentArtist: String? = nil
    var currentAlbum: String? = nil
    var currentTrackId: String? = nil
    var currentHasArtwork: Bool = false

    var hasTrackLoaded: Bool { currentURL != nil }
    var currentArtworkURL: URL? {
        guard currentHasArtwork, let trackId = currentTrackId else { return nil }
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docsDir.appendingPathComponent("Artwork").appendingPathComponent("\(trackId).jpg")
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let mixerNode = AVAudioMixerNode()

    // file scheduling
    private var audioFile: AVAudioFile?
    private var sampleRate: Double = 44100
    private var frameCount: AVAudioFrameCount = 0

    // currentTime updates
    private var progressTimer: Timer?
    private var currentSeekOffset: TimeInterval = 0
    private var scheduleToken: Int = 0

    // MARK: - Init
    init() {
        setupAudioSession()
        setupEngine()
        setupRemoteTransportControls()
        observeInterruptions()
        observeRouteChanges()
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

    // MARK: - Engine graph
    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(mixerNode)

        engine.connect(playerNode, to: mixerNode, format: nil)
        engine.connect(mixerNode, to: engine.mainMixerNode, format: nil)

        do {
            try engine.start()
        } catch {
            print("[MusicPlayer] Engine start error: \(error)")
        }
    }

    // MARK: - Load
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
            duration = Double(frameCount) / sampleRate

            // Prefer database override, fallback to parsing, fallback to filename
            if let title = title, !title.isEmpty {
                self.currentTitle = title
                self.currentArtist = artist
            } else {
                let asset = AVURLAsset(url: url)
                Task {
                    let metadata = await MetadataExtractor.extract(from: asset)
                    await MainActor.run {
                        self.currentTitle = metadata.title ?? url.deletingPathExtension().lastPathComponent
                        self.currentArtist = metadata.artist
                        if self.currentAlbum == nil {
                            self.currentAlbum = metadata.album
                        }
                    }
                }
            }

            scheduleFile()
            updateNowPlayingInfo()
        } catch {
            print("[MusicPlayer] Load error: \(error)")
        }
    }

    private func scheduleFile() {
        guard let file = audioFile else { return }
        let token = nextScheduleToken()
        playerNode.scheduleFile(file, at: nil) { [weak self] in
            guard let self, self.scheduleToken == token else { return }
            DispatchQueue.main.async {
                self.handlePlaybackFinished()
            }
        }
    }

    private func scheduleSegment(startingFrame: AVAudioFramePosition, frameCount: AVAudioFrameCount) {
        guard let file = audioFile else { return }
        let token = nextScheduleToken()
        playerNode.scheduleSegment(file, startingFrame: startingFrame, frameCount: frameCount, at: nil) { [weak self] in
            guard let self, self.scheduleToken == token else { return }
            DispatchQueue.main.async {
                self.handlePlaybackFinished()
            }
        }
    }

    private func nextScheduleToken() -> Int {
        scheduleToken += 1
        return scheduleToken
    }

    private func invalidateSchedule() {
        scheduleToken += 1
    }

    // MARK: - Playback controls
    func play() {
        guard audioFile != nil else { return }
        if !engine.isRunning {
            try? engine.start()
        }
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
        let clampedTime = min(max(0, time), duration)
        invalidateSchedule()
        playerNode.stop()

        let seekFrame = AVAudioFramePosition(clampedTime * sampleRate)
        let safeFrame = max(0, min(seekFrame, AVAudioFramePosition(frameCount)))
        let remainingFrames = AVAudioFrameCount(AVAudioFramePosition(frameCount) - safeFrame)

        guard remainingFrames > 0 else {
            currentTime = duration
            isPlaying = false
            currentSeekOffset = duration
            stopProgressTimer()
            updateNowPlayingInfo()
            return
        }

        scheduleSegment(startingFrame: safeFrame, frameCount: remainingFrames)

        currentSeekOffset = Double(safeFrame) / sampleRate
        currentTime = currentSeekOffset

        if wasPlaying {
            playerNode.play()
        }
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
        
        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        currentTime = min(currentSeekOffset + elapsed, duration)
    }

    // MARK: - Finished
    private func handlePlaybackFinished() {
        isPlaying = false
        currentTime = duration
        stopProgressTimer()
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote controls
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.isPlaying ? self.pause() : self.play()
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }

    // MARK: - Interruptions
    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            switch type {
            case .began:
                self?.pause()
            case .ended:
                if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                   AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                    self?.play()
                }
            @unknown default: break
            }
        }
    }

    // MARK: - Route changes
    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

            // pause when headphones are removed
            if reason == .oldDeviceUnavailable {
                self?.pause()
            }
        }
    }
}

// MARK: - AVMetadata helpers
