import Foundation
import Combine
import JellyfinAPI
import AudioEngine

/// Reports playback state to Jellyfin server for dashboard visibility
/// and resume-from-position support.
class SessionReporter {
    private let jellyfinClient: JellyfinClient
    private let audioEngine: AudioEngine
    private var cancellables = Set<AnyCancellable>()
    private var progressTimer: Timer?
    private var webSocketTask: URLSessionWebSocketTask?
    private var keepAliveTimer: Timer?
    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 30
    private var playSessionId: String?

    init(jellyfinClient: JellyfinClient, audioEngine: AudioEngine) {
        self.jellyfinClient = jellyfinClient
        self.audioEngine = audioEngine
        observePlayback()
    }

    deinit {
        disconnect()
    }

    // MARK: - WebSocket

    func connect() {
        guard let serverURL = jellyfinClient.serverURL,
              let url = buildWebSocketURL(serverURL: serverURL) else { return }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        reconnectAttempt = 0
        startKeepAlive()
        receiveMessages()
    }

    func disconnect() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        progressTimer?.invalidate()
        progressTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Playback Reporting

    private func observePlayback() {
        audioEngine.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self else { return }
                if let track {
                    self.reportPlaybackStart(track: track)
                } else {
                    self.reportPlaybackStop()
                }
            }
            .store(in: &cancellables)

        audioEngine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .playing:
                    self?.startProgressReporting()
                case .paused:
                    self?.stopProgressReporting()
                    self?.reportProgress()
                case .idle:
                    self?.stopProgressReporting()
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // Auto-connect when authenticated
        jellyfinClient.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authenticated in
                if authenticated {
                    self?.connect()
                } else {
                    self?.disconnect()
                }
            }
            .store(in: &cancellables)
    }

    private func reportPlaybackStart(track: Track) {
        playSessionId = UUID().uuidString
        let body: [String: Any] = [
            "ItemId": track.id,
            "MediaSourceId": track.mediaSourceId,
            "CanSeek": true,
            "PlayMethod": "DirectStream",
            "PlaySessionId": playSessionId ?? "",
        ]
        Task { await postSession(path: "/Sessions/Playing", body: body) }
    }

    private func reportProgress() {
        guard let track = audioEngine.currentTrack else { return }
        let positionTicks = Int64(audioEngine.elapsed * 10_000_000)
        let body: [String: Any] = [
            "ItemId": track.id,
            "MediaSourceId": track.mediaSourceId,
            "PositionTicks": positionTicks,
            "IsPaused": !audioEngine.isPlaying,
            "PlaySessionId": playSessionId ?? "",
        ]
        Task { await postSession(path: "/Sessions/Playing/Progress", body: body) }
    }

    private func reportPlaybackStop() {
        guard let track = audioEngine.currentTrack else {
            stopProgressReporting()
            return
        }
        let positionTicks = Int64(audioEngine.elapsed * 10_000_000)
        let body: [String: Any] = [
            "ItemId": track.id,
            "MediaSourceId": track.mediaSourceId,
            "PositionTicks": positionTicks,
            "PlaySessionId": playSessionId ?? "",
        ]
        Task { await postSession(path: "/Sessions/Playing/Stopped", body: body) }
        stopProgressReporting()
        playSessionId = nil
    }

    private func startProgressReporting() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.reportProgress()
        }
    }

    private func stopProgressReporting() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - WebSocket Internals

    private func buildWebSocketURL(serverURL: String) -> URL? {
        // Get token from client (access via streamURL construction as proxy)
        // WebSocket URL: ws(s)://server/socket?api_key=TOKEN
        var wsURL = serverURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        wsURL += "/socket"

        // Extract token from a dummy stream URL
        if let dummyURL = jellyfinClient.streamURL(for: "dummy", mediaSourceId: "dummy"),
           let components = URLComponents(url: dummyURL, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "api_key" })?.value {
            wsURL += "?api_key=\(token)"
        }

        return URL(string: wsURL)
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success:
                // Continue receiving
                self?.receiveMessages()
            case .failure:
                // Connection lost — attempt reconnect
                DispatchQueue.main.async {
                    self?.attemptReconnect()
                }
            }
        }
    }

    private func startKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            let message = URLSessionWebSocketTask.Message.string("{\"MessageType\":\"KeepAlive\"}")
            self?.webSocketTask?.send(message) { _ in }
        }
    }

    private func attemptReconnect() {
        guard jellyfinClient.isAuthenticated else { return }
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    // MARK: - HTTP

    private func postSession(path: String, body: [String: Any]) async {
        guard let serverURL = jellyfinClient.serverURL,
              let url = URL(string: "\(serverURL)\(path)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Extract token
        if let dummyURL = jellyfinClient.streamURL(for: "dummy", mediaSourceId: "dummy"),
           let components = URLComponents(url: dummyURL, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "api_key" })?.value {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }
}
