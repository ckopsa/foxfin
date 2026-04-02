import AVFoundation
import Combine

/// Playback state published to UI via @Published properties.
enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
}

/// A track ready for playback.
struct Track: Equatable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let streamURL: URL
    let durationSeconds: TimeInterval
    let mediaSourceId: String

    static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
}

/// Core audio playback engine with gapless support via dual-player crossover.
///
/// Uses two AVAudioPlayer instances: one for the current track and one prefetched
/// for the next. When the current track nears completion, the next player is already
/// prepared and starts immediately for gapless transition.
class AudioEngine: ObservableObject {
    @Published var state: PlaybackState = .idle
    @Published var currentTrack: Track?
    @Published var elapsed: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0 {
        didSet { currentPlayer?.volume = volume }
    }

    var isPlaying: Bool { state == .playing }

    var currentTrackName: String { currentTrack?.name ?? "Not Playing" }
    var currentArtistName: String { currentTrack?.artist ?? "" }

    private var currentPlayer: AVAudioPlayer?
    private var nextPlayer: AVAudioPlayer?
    private var nextPrefetchedTrack: Track?
    private var progressTimer: Timer?
    private var prefetchTask: Task<Void, Never>?
    private var playbackDelegate: PlaybackDelegate?

    let queue = PlaybackQueue()
    private let downloadSession: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        self.downloadSession = URLSession(configuration: config)
    }

    deinit {
        progressTimer?.invalidate()
        prefetchTask?.cancel()
    }

    // MARK: - Playback Controls

    func play(track: Track) {
        prefetchTask?.cancel()
        state = .loading
        currentTrack = track
        duration = track.durationSeconds
        elapsed = 0

        // Check if this track was already prefetched
        if let nextPlayer, let nextPrefetchedTrack, nextPrefetchedTrack == track {
            startPlayback(with: nextPlayer)
            self.nextPlayer = nil
            self.nextPrefetchedTrack = nil
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let tempURL = try await self.downloadTrack(track)
                let player = try AVAudioPlayer(contentsOf: tempURL)
                player.volume = self.volume
                player.prepareToPlay()
                await MainActor.run {
                    self.startPlayback(with: player)
                }
            } catch {
                await MainActor.run {
                    self.state = .idle
                }
            }
        }
    }

    func togglePlayPause() {
        switch state {
        case .playing:
            currentPlayer?.pause()
            state = .paused
        case .paused:
            currentPlayer?.play()
            state = .playing
        default:
            break
        }
    }

    func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        prefetchTask?.cancel()
        currentPlayer?.stop()
        currentPlayer = nil
        nextPlayer = nil
        nextPrefetchedTrack = nil
        currentTrack = nil
        state = .idle
        elapsed = 0
        duration = 0
    }

    func seek(to time: TimeInterval) {
        currentPlayer?.currentTime = time
        elapsed = time
    }

    func nextTrack() {
        queue.advance()
        if let track = queue.currentTrack {
            play(track: track)
        } else {
            stop()
        }
    }

    func previousTrack() {
        if elapsed > 3 {
            seek(to: 0)
            return
        }
        queue.goBack()
        if let track = queue.currentTrack {
            play(track: track)
        }
    }

    func playQueue(tracks: [Track], startAt index: Int = 0) {
        queue.setTracks(tracks, startAt: index)
        if let track = queue.currentTrack {
            play(track: track)
        }
    }

    // MARK: - Queue Manipulation

    func addToQueue(_ track: Track) {
        queue.append(track)
    }

    func removeFromQueue(at index: Int) {
        queue.remove(at: index)
    }

    func moveInQueue(from: Int, to: Int) {
        queue.move(from: from, to: to)
    }

    func clearQueue() {
        stop()
        queue.clear()
    }

    // MARK: - Internal

    private func startPlayback(with player: AVAudioPlayer) {
        currentPlayer?.stop()
        currentPlayer = player

        let delegate = PlaybackDelegate { [weak self] in
            self?.onTrackFinished()
        }
        player.delegate = delegate
        self.playbackDelegate = delegate

        player.play()
        state = .playing
        startProgressTimer()
    }

    private func onTrackFinished() {
        nextTrack()
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let player = self.currentPlayer else { return }
            self.elapsed = player.currentTime

            // Trigger prefetch at 80% progress
            let progress = self.duration > 0 ? self.elapsed / self.duration : 0
            if progress > 0.8 {
                self.prefetchNextIfNeeded()
            }
        }
    }

    private func prefetchNextIfNeeded() {
        guard prefetchTask == nil, let next = queue.peekNext, nextPrefetchedTrack != next else { return }

        prefetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let tempURL = try await self.downloadTrack(next)
                let player = try AVAudioPlayer(contentsOf: tempURL)
                player.volume = self.volume
                player.prepareToPlay()
                await MainActor.run {
                    self.nextPlayer = player
                    self.nextPrefetchedTrack = next
                    self.prefetchTask = nil
                }
            } catch {
                await MainActor.run {
                    self.prefetchTask = nil
                }
            }
        }
    }

    private func downloadTrack(_ track: Track) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("foxtunes-\(track.id).audio")

        // Use cached file if already downloaded
        if FileManager.default.fileExists(atPath: tempURL.path) {
            return tempURL
        }

        let (data, _) = try await downloadSession.data(from: track.streamURL)
        try data.write(to: tempURL)
        return tempURL
    }
}

/// AVAudioPlayerDelegate that calls a closure on finish for gapless chaining.
private class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            onFinish()
        }
    }
}
