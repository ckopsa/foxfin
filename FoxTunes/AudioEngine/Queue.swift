import Foundation

/// Playback queue with shuffle and repeat modes.
enum RepeatMode: Equatable {
    case off
    case all
    case one
}

class PlaybackQueue: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var currentIndex: Int = -1
    @Published var shuffleEnabled = false
    @Published var repeatMode: RepeatMode = .off

    private var shuffledIndices: [Int] = []

    var currentTrack: Track? {
        let idx = effectiveIndex
        guard idx >= 0, idx < tracks.count else { return nil }
        return tracks[idx]
    }

    /// Peek at the next track without advancing.
    var peekNext: Track? {
        let next = nextIndex
        guard next >= 0, next < tracks.count else { return nil }
        return tracks[next]
    }

    var isEmpty: Bool { tracks.isEmpty }
    var count: Int { tracks.count }

    private var effectiveIndex: Int {
        if shuffleEnabled, currentIndex >= 0, currentIndex < shuffledIndices.count {
            return shuffledIndices[currentIndex]
        }
        return currentIndex
    }

    private var nextIndex: Int {
        guard !tracks.isEmpty else { return -1 }
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

    func setTracks(_ newTracks: [Track], startAt: Int = 0) {
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
        } else {
            currentIndex = -1
        }
    }

    func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    func append(_ track: Track) {
        tracks.append(track)
        if shuffleEnabled {
            shuffledIndices.append(tracks.count - 1)
        }
    }

    func remove(at index: Int) {
        guard index >= 0, index < tracks.count else { return }
        tracks.remove(at: index)
        if shuffleEnabled {
            shuffledIndices.removeAll { $0 == index }
            shuffledIndices = shuffledIndices.map { $0 > index ? $0 - 1 : $0 }
        }
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            currentIndex = min(currentIndex, tracks.count - 1)
        }
    }

    func move(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < tracks.count,
              destination >= 0, destination < tracks.count else { return }
        let track = tracks.remove(at: source)
        tracks.insert(track, at: destination)

        // Adjust currentIndex to follow the playing track
        if currentIndex == source {
            currentIndex = destination
        } else if source < currentIndex, destination >= currentIndex {
            currentIndex -= 1
        } else if source > currentIndex, destination <= currentIndex {
            currentIndex += 1
        }
    }

    func clear() {
        tracks.removeAll()
        shuffledIndices.removeAll()
        currentIndex = -1
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
        guard !tracks.isEmpty else { return }
        shuffledIndices = Array(tracks.indices).shuffled()
        let current = effectiveIndex
        if current >= 0, let pos = shuffledIndices.firstIndex(of: current) {
            shuffledIndices.swapAt(0, pos)
            currentIndex = 0
        }
    }
}
