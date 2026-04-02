import Foundation

/// Playback queue with shuffle and repeat modes.
enum RepeatMode {
    case off
    case all
    case one
}

class PlaybackQueue: ObservableObject {
    @Published var tracks: [AudioEngine.Track] = []
    @Published var currentIndex: Int = -1
    @Published var shuffleEnabled = false
    @Published var repeatMode: RepeatMode = .off

    private var shuffledIndices: [Int] = []

    var currentTrack: AudioEngine.Track? {
        let idx = effectiveIndex
        guard idx >= 0, idx < tracks.count else { return nil }
        return tracks[idx]
    }

    var nextTrack: AudioEngine.Track? {
        let next = nextIndex
        guard next >= 0, next < tracks.count else { return nil }
        return tracks[next]
    }

    private var effectiveIndex: Int {
        if shuffleEnabled, currentIndex >= 0, currentIndex < shuffledIndices.count {
            return shuffledIndices[currentIndex]
        }
        return currentIndex
    }

    private var nextIndex: Int {
        switch repeatMode {
        case .one:
            return effectiveIndex
        case .all:
            if shuffleEnabled {
                let next = currentIndex + 1
                return next >= shuffledIndices.count ? shuffledIndices[0] : shuffledIndices[next]
            }
            return (effectiveIndex + 1) % tracks.count
        case .off:
            if shuffleEnabled {
                let next = currentIndex + 1
                return next >= shuffledIndices.count ? -1 : shuffledIndices[next]
            }
            let next = effectiveIndex + 1
            return next >= tracks.count ? -1 : next
        }
    }

    func setTracks(_ newTracks: [AudioEngine.Track], startAt: Int = 0) {
        tracks = newTracks
        currentIndex = startAt
        if shuffleEnabled {
            reshuffle()
        }
    }

    func advance() {
        let next = nextIndex
        if next >= 0 {
            currentIndex = shuffleEnabled
                ? (shuffledIndices.firstIndex(of: next) ?? currentIndex + 1)
                : next
        }
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        if shuffleEnabled {
            reshuffle()
        }
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    private func reshuffle() {
        shuffledIndices = Array(tracks.indices).shuffled()
        if let current = shuffledIndices.firstIndex(of: effectiveIndex) {
            shuffledIndices.swapAt(0, current)
            currentIndex = 0
        }
    }
}
