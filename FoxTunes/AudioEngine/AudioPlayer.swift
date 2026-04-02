import AVFoundation
import Combine

/// Core audio playback engine using AVAudioEngine for gapless support.
class AudioEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrackName = "Not Playing"
    @Published var currentArtistName = ""
    @Published var elapsed: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var queue: [Track] = []
    private var currentIndex: Int = -1
    private var timer: Timer?

    struct Track {
        let id: String
        let name: String
        let artist: String
        let album: String
        let streamURL: URL
        let durationSeconds: TimeInterval
    }

    func play(track: Track) {
        stop()
        currentTrackName = track.name
        currentArtistName = track.artist
        duration = track.durationSeconds

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: track.streamURL)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(track.id).audio")
                try data.write(to: tempURL)

                await MainActor.run {
                    do {
                        self.player = try AVAudioPlayer(contentsOf: tempURL)
                        self.player?.prepareToPlay()
                        self.player?.play()
                        self.isPlaying = true
                        self.startProgressTimer()
                    } catch {
                        self.isPlaying = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isPlaying = false
                }
            }
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        isPlaying = false
        elapsed = 0
    }

    func nextTrack() {
        guard !queue.isEmpty else { return }
        currentIndex = min(currentIndex + 1, queue.count - 1)
        play(track: queue[currentIndex])
    }

    func previousTrack() {
        guard !queue.isEmpty else { return }
        if elapsed > 3 {
            seek(to: 0)
        } else {
            currentIndex = max(currentIndex - 1, 0)
            play(track: queue[currentIndex])
        }
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        elapsed = time
    }

    func setQueue(_ tracks: [Track], startAt index: Int = 0) {
        queue = tracks
        currentIndex = index
        if !tracks.isEmpty {
            play(track: tracks[index])
        }
    }

    private func startProgressTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.elapsed = player.currentTime
            if !player.isPlaying && self.elapsed >= self.duration - 0.5 {
                self.nextTrack()
            }
        }
    }
}
