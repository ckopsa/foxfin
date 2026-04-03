import Foundation
import MediaPlayer
import Combine
import AppKit
import AudioEngine

/// Bridges AudioEngine state to macOS Now Playing info center and media key commands.
class NowPlayingManager {
    private let audioEngine: AudioEngine
    private var cancellables = Set<AnyCancellable>()

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
        setupRemoteCommands()
        observePlaybackState()
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.audioEngine.togglePlayPause()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.audioEngine.togglePlayPause()
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.audioEngine.togglePlayPause()
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.audioEngine.nextTrack()
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.audioEngine.previousTrack()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.audioEngine.seek(to: positionEvent.positionTime)
            return .success
        }
    }

    // MARK: - State Observation

    private func observePlaybackState() {
        // Update now playing info when track changes
        audioEngine.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                if track != nil {
                    self?.updateNowPlayingInfo()
                } else {
                    self?.clearNowPlaying()
                }
            }
            .store(in: &cancellables)

        // Update playback state
        audioEngine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updatePlaybackState(state)
            }
            .store(in: &cancellables)

        // Update elapsed time after seeks
        audioEngine.seeked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let track = audioEngine.currentTrack else { return }

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = track.name
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyAlbumTitle] = track.album
        info[MPMediaItemPropertyPlaybackDuration] = audioEngine.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioEngine.elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = audioEngine.isPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updatePlaybackState(_ state: PlaybackState) {
        switch state {
        case .playing:
            MPNowPlayingInfoCenter.default().playbackState = .playing
        case .paused:
            MPNowPlayingInfoCenter.default().playbackState = .paused
        case .idle:
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        case .loading, .buffering:
            MPNowPlayingInfoCenter.default().playbackState = .playing
        }
        updateNowPlayingInfo()
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

}
