import AVFoundation
import Combine
import Foundation

/// Playback state published to UI via @Published properties.
public enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
}

/// A track ready for playback.
public struct Track: Equatable {
    public let id: String
    public let name: String
    public let artist: String
    public let album: String
    public let streamURL: URL
    public let durationSeconds: TimeInterval
    public let mediaSourceId: String

    public init(
        id: String,
        name: String,
        artist: String,
        album: String,
        streamURL: URL,
        durationSeconds: TimeInterval,
        mediaSourceId: String
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.streamURL = streamURL
        self.durationSeconds = durationSeconds
        self.mediaSourceId = mediaSourceId
    }

    public static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
}

/// Core audio playback engine with streaming and gapless prefetch.
///
/// Uses AVPlayer for HTTP streaming — playback starts immediately without
/// downloading the full file. The next track's AVPlayerItem is created early
/// so it pre-buffers for gapless transition.
public class AudioEngine: ObservableObject {
    @Published public var state: PlaybackState = .idle
    @Published public var currentTrack: Track?
    @Published public var elapsed: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var volume: Float = 1.0 {
        didSet { player.volume = volume }
    }

    public var isPlaying: Bool { state == .playing }
    public let seeked = PassthroughSubject<TimeInterval, Never>()

    public var currentTrackName: String { currentTrack?.name ?? "Not Playing" }
    public var currentArtistName: String { currentTrack?.artist ?? "" }

    private let player = AVPlayer()
    private var nextItem: AVPlayerItem?
    private var nextPrefetchedTrack: Track?
    private var timeObserver: Any?
    private var statusObserver: AnyCancellable?
    private var itemEndObserver: AnyCancellable?

    public let queue = PlaybackQueue()

    public init() {
        player.volume = volume
        setupTimeObserver()
        setupStatusObserver()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    // MARK: - Observers

    private func setupStatusObserver() {
        statusObserver = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.currentTrack != nil else { return }
                switch status {
                case .playing:
                    self.state = .playing
                case .paused:
                    // Don't overwrite idle/loading — paused fires during item swap
                    if self.state == .playing || self.state == .buffering {
                        self.state = .paused
                    }
                case .waitingToPlayAtSpecifiedRate:
                    self.state = .buffering
                @unknown default:
                    break
                }
            }
    }

    private func setupTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, self.currentTrack != nil else { return }
            let secs = time.seconds
            guard secs.isFinite else { return }
            self.elapsed = secs

            // Prefetch next track at 80% progress
            if self.duration > 0, secs / self.duration > 0.8 {
                self.prefetchNextIfNeeded()
            }
        }
    }

    private func observeItemEnd(_ item: AVPlayerItem) {
        itemEndObserver?.cancel()
        itemEndObserver = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.nextTrack()
            }
    }

    // MARK: - Playback Controls

    public func play(track: Track) {
        state = .loading
        currentTrack = track
        duration = track.durationSeconds
        elapsed = 0

        // Use prefetched item if it matches
        if let nextItem, let nextPrefetchedTrack, nextPrefetchedTrack == track {
            startPlayback(with: nextItem)
            self.nextItem = nil
            self.nextPrefetchedTrack = nil
            return
        }

        let item = AVPlayerItem(url: track.streamURL)
        startPlayback(with: item)
    }

    public func togglePlayPause() {
        switch state {
        case .playing, .buffering:
            player.pause()
            state = .paused
        case .paused:
            player.play()
        default:
            break
        }
    }

    public func stop() {
        itemEndObserver?.cancel()
        itemEndObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        nextItem = nil
        nextPrefetchedTrack = nil
        currentTrack = nil
        state = .idle
        elapsed = 0
        duration = 0
    }

    public func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        elapsed = time
        seeked.send(time)
    }

    public func nextTrack() {
        queue.advance()
        if let track = queue.currentTrack {
            play(track: track)
        } else {
            stop()
        }
    }

    public func previousTrack() {
        if elapsed > 3 {
            seek(to: 0)
            return
        }
        queue.goBack()
        if let track = queue.currentTrack {
            play(track: track)
        }
    }

    public func playQueue(tracks: [Track], startAt index: Int = 0) {
        queue.setTracks(tracks, startAt: index)
        if let track = queue.currentTrack {
            play(track: track)
        }
    }

    // MARK: - Queue Manipulation

    public func addToQueue(_ track: Track) {
        queue.append(track)
    }

    public func removeFromQueue(at index: Int) {
        queue.remove(at: index)
    }

    public func moveInQueue(from: Int, to: Int) {
        queue.move(from: from, to: to)
    }

    public func clearQueue() {
        stop()
        queue.clear()
    }

    // MARK: - Internal

    private func startPlayback(with item: AVPlayerItem) {
        observeItemEnd(item)
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func prefetchNextIfNeeded() {
        guard nextItem == nil, let next = queue.peekNext, nextPrefetchedTrack != next else { return }
        // Creating the AVPlayerItem starts buffering from the URL
        nextItem = AVPlayerItem(url: next.streamURL)
        nextPrefetchedTrack = next
    }
}
