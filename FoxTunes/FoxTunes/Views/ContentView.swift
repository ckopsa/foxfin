import SwiftUI
import AppKit
import JellyfinAPI
import AudioEngine

// MARK: - Main Content

struct ContentView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var selectedTab: Tab = .library

    enum Tab: String, CaseIterable {
        case library = "Library"
        case songs = "Songs"
        case queue = "Queue"
        case search = "Search"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .library: return "music.note.house"
            case .songs: return "music.note.list"
            case .queue: return "list.bullet"
            case .search: return "magnifyingglass"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingView()
            Divider()

            if jellyfinClient.isAuthenticated {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                switch selectedTab {
                case .library: LibraryBrowserView()
                case .songs: SongsView()
                case .queue: QueueView()
                case .search: SearchView()
                case .settings: SettingsView()
                }
            } else {
                ConnectionView()
            }
        }
        .frame(width: 320, height: 480)
    }
}

private func baseItemToTrack(_ item: BaseItem, jellyfinClient: JellyfinClient) -> Track? {
    guard let source = item.MediaSources?.first,
          let url = jellyfinClient.streamURL(for: item.Id, mediaSourceId: source.Id) else { return nil }
    return Track(
        id: item.Id,
        name: item.Name,
        artist: item.AlbumArtist ?? "Unknown Artist",
        album: item.Album ?? "",
        streamURL: url,
        durationSeconds: item.durationSeconds ?? 0,
        mediaSourceId: source.Id
    )
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

// MARK: - Now Playing

struct NowPlayingView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var jellyfinClient: JellyfinClient

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                AsyncImage(url: artURL) { image in
                    image.resizable()
                } placeholder: {
                    Image(systemName: "music.note")
                        .font(.title)
                        .frame(width: 60, height: 60)
                        .background(Color.secondary.opacity(0.15))
                }
                .frame(width: 60, height: 60)
                .cornerRadius(4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(audioEngine.currentTrackName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(audioEngine.currentArtistName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            // Progress bar
            if audioEngine.duration > 0 {
                ProgressView(value: audioEngine.elapsed, total: audioEngine.duration)
                    .progressViewStyle(.linear)

                HStack {
                    Text(formatTime(audioEngine.elapsed))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTime(audioEngine.duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button(action: { audioEngine.queue.toggleShuffle() }) {
                    Image(systemName: audioEngine.queue.shuffleEnabled ? "shuffle.circle.fill" : "shuffle")
                        .foregroundColor(audioEngine.queue.shuffleEnabled ? .accentColor : .primary)
                        .font(.caption)
                }
                Button(action: audioEngine.previousTrack) {
                    Image(systemName: "backward.fill")
                }
                Button(action: audioEngine.togglePlayPause) {
                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Button(action: audioEngine.nextTrack) {
                    Image(systemName: "forward.fill")
                }
                Button(action: { audioEngine.queue.cycleRepeat() }) {
                    Image(systemName: repeatIcon)
                        .foregroundColor(audioEngine.queue.repeatMode != .off ? .accentColor : .primary)
                        .font(.caption)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: volumeIcon)
                        .font(.caption)
                    Slider(value: $audioEngine.volume, in: 0...1)
                        .frame(width: 60)
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var artURL: URL? {
        guard let track = audioEngine.currentTrack else { return nil }
        return jellyfinClient.imageURL(for: track.id, maxWidth: 120)
    }

    private var volumeIcon: String {
        if audioEngine.volume == 0 { return "speaker.slash.fill" }
        if audioEngine.volume < 0.5 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    private var repeatIcon: String {
        switch audioEngine.queue.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat.circle.fill"
        case .one: return "repeat.1.circle.fill"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Library Browser

struct LibraryBrowserView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var artists: [BaseItem] = []
    @State private var albums: [BaseItem] = []
    @State private var tracks: [BaseItem] = []
    @State private var navigationPath: [LibraryLevel] = []
    @State private var isLoading = false

    enum LibraryLevel: Hashable {
        case artists
        case albums(artistId: String, artistName: String)
        case tracks(albumId: String, albumName: String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb
            if !navigationPath.isEmpty {
                HStack {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                        Text(breadcrumbTitle)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else {
                currentLevelView
            }
        }
        .task { await loadArtists() }
    }

    @ViewBuilder
    private var currentLevelView: some View {
        switch navigationPath.last {
        case .tracks(let albumId, _):
            trackListView(albumId: albumId)
        case .albums(let artistId, _):
            albumListView(artistId: artistId)
        default:
            artistListView
        }
    }

    private var artistListView: some View {
        List(artists) { artist in
            Button {
                navigationPath.append(.albums(artistId: artist.Id, artistName: artist.Name))
                Task { await loadAlbums(artistId: artist.Id) }
            } label: {
                Text(artist.Name)
            }
            .buttonStyle(.plain)
        }
    }

    private func albumListView(artistId: String) -> some View {
        List(albums) { album in
            Button {
                navigationPath.append(.tracks(albumId: album.Id, albumName: album.Name))
                Task { await loadTracks(albumId: album.Id) }
            } label: {
                HStack(spacing: 8) {
                    AsyncImage(url: jellyfinClient.imageURL(for: album.Id, maxWidth: 40)) { img in
                        img.resizable()
                    } placeholder: {
                        Color.secondary.opacity(0.15)
                    }
                    .frame(width: 40, height: 40)
                    .cornerRadius(3)

                    Text(album.Name)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func trackListView(albumId: String) -> some View {
        List(tracks) { track in
            Button {
                playAlbumFromTrack(track)
            } label: {
                HStack {
                    if let num = track.IndexNumber {
                        Text("\(num)")
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                    Text(track.Name)
                    Spacer()
                    if let dur = track.durationSeconds {
                        Text(formatDuration(dur))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var breadcrumbTitle: String {
        if navigationPath.count >= 2 {
            switch navigationPath[navigationPath.count - 2] {
            case .albums(_, let name): return name
            case .tracks(_, let name): return name
            case .artists: return "Artists"
            }
        }
        return "Artists"
    }

    private func goBack() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }

    private func loadArtists() async {
        isLoading = true
        if case .success(let items) = await jellyfinClient.fetchArtists() {
            artists = items
        }
        isLoading = false
    }

    private func loadAlbums(artistId: String) async {
        isLoading = true
        if case .success(let items) = await jellyfinClient.fetchAlbums(byArtistId: artistId) {
            albums = items
        }
        isLoading = false
    }

    private func loadTracks(albumId: String) async {
        isLoading = true
        if case .success(let items) = await jellyfinClient.fetchTracks(inAlbumId: albumId) {
            tracks = items
        }
        isLoading = false
    }

    private func playAlbumFromTrack(_ item: BaseItem) {
        let allTracks = tracks.compactMap { baseItemToTrack($0, jellyfinClient: jellyfinClient) }
        guard let index = allTracks.firstIndex(where: { $0.id == item.Id }) else { return }
        audioEngine.playQueue(tracks: allTracks, startAt: index)
    }
}

// MARK: - Songs

struct SongsView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var songs: [BaseItem] = []
    @State private var filteredSongs: [BaseItem] = []
    @State private var query = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter songs...", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .onChange(of: query) { newValue in
                    applyFilter(newValue)
                }

            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if filteredSongs.isEmpty {
                VStack {
                    Spacer()
                    Text(query.isEmpty ? "No songs found" : "No matching songs")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(filteredSongs) { song in
                    Button {
                        playSong(song)
                    } label: {
                        HStack(spacing: 8) {
                            Text(song.Name)
                                .lineLimit(1)
                            Spacer()
                            Text(song.AlbumArtist ?? "Unknown Artist")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            if let dur = song.durationSeconds {
                                Text(formatDuration(dur))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await loadSongs() }
    }

    private func loadSongs() async {
        isLoading = true
        if case .success(let items) = await jellyfinClient.fetchSongs() {
            songs = items
            applyFilter(query)
        }
        isLoading = false
    }

    private func applyFilter(_ searchText: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            filteredSongs = songs
            return
        }

        let needle = trimmed.localizedLowercase
        filteredSongs = songs.filter { song in
            song.Name.localizedLowercase.contains(needle) ||
            (song.AlbumArtist?.localizedLowercase.contains(needle) ?? false) ||
            (song.Album?.localizedLowercase.contains(needle) ?? false)
        }
    }

    private func playSong(_ song: BaseItem) {
        let queue = filteredSongs.compactMap { baseItemToTrack($0, jellyfinClient: jellyfinClient) }
        guard let index = queue.firstIndex(where: { $0.id == song.Id }) else { return }
        audioEngine.playQueue(tracks: queue, startAt: index)
    }
}

// MARK: - Queue View

struct QueueView: View {
    @EnvironmentObject var audioEngine: AudioEngine

    var body: some View {
        if audioEngine.queue.isEmpty {
            VStack {
                Spacer()
                Text("Queue is empty")
                    .foregroundColor(.secondary)
                Text("Play something from the library")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else {
            List {
                ForEach(Array(audioEngine.queue.tracks.enumerated()), id: \.element.id) { index, track in
                    HStack {
                        if index == audioEngine.queue.currentIndex {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                        } else {
                            Text("\(index + 1)")
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                        }
                        VStack(alignment: .leading) {
                            Text(track.name)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioEngine.playQueue(tracks: audioEngine.queue.tracks, startAt: index)
                    }
                }
                .onDelete { indices in
                    indices.forEach { audioEngine.removeFromQueue(at: $0) }
                }
                .onMove { source, destination in
                    if let from = source.first {
                        audioEngine.moveInQueue(from: from, to: destination)
                    }
                }
            }

            HStack {
                Button(action: { audioEngine.queue.toggleShuffle() }) {
                    Image(systemName: audioEngine.queue.shuffleEnabled ? "shuffle.circle.fill" : "shuffle")
                }
                Button(action: { audioEngine.queue.cycleRepeat() }) {
                    Image(systemName: repeatIcon)
                }
                Spacer()
                Button("Clear") { audioEngine.clearQueue() }
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }

    private var repeatIcon: String {
        switch audioEngine.queue.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat.circle.fill"
        case .one: return "repeat.1.circle.fill"
        }
    }
}

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var query = ""
    @State private var results: [BaseItem] = []
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search music...", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .onSubmit { Task { await search() } }

            if isSearching {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if results.isEmpty && !query.isEmpty {
                VStack {
                    Spacer()
                    Text("No results")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(results) { item in
                    Button {
                        playItem(item)
                    } label: {
                        HStack(spacing: 8) {
                            AsyncImage(url: jellyfinClient.imageURL(for: item.Id, maxWidth: 40)) { img in
                                img.resizable()
                            } placeholder: {
                                Color.secondary.opacity(0.15)
                            }
                            .frame(width: 40, height: 40)
                            .cornerRadius(3)

                            VStack(alignment: .leading) {
                                Text(item.Name)
                                    .lineLimit(1)
                                Text(subtitle(for: item))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(item.itemType)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func search() async {
        guard !query.isEmpty else { return }
        isSearching = true
        if case .success(let items) = await jellyfinClient.search(query: query) {
            results = items
        }
        isSearching = false
    }

    private func playItem(_ item: BaseItem) {
        guard item.itemType == "Audio",
              let track = baseItemToTrack(item, jellyfinClient: jellyfinClient) else { return }
        audioEngine.playQueue(tracks: [track])
    }

    private func subtitle(for item: BaseItem) -> String {
        switch item.itemType {
        case "Audio":
            let values = [item.AlbumArtist ?? "Unknown Artist", item.Album].compactMap { $0 }
            return values.joined(separator: " — ")
        case "MusicAlbum": return item.AlbumArtist ?? ""
        default: return item.itemType
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            if jellyfinClient.isAuthenticated {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.green)
                    Text("Connected")
                        .font(.headline)
                    if let url = jellyfinClient.serverURL {
                        Text(url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Button("Disconnect") {
                    jellyfinClient.logout()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Divider()

            Button("Quit FoxTunes") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom, 8)
        }
        .padding()
    }
}

// MARK: - Connection

struct ConnectionView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "music.note.house")
                .font(.largeTitle)
                .foregroundColor(.accentColor)

            Text("Connect to Jellyfin")
                .font(.headline)

            VStack(spacing: 8) {
                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button(isConnecting ? "Connecting..." : "Connect") {
                Task { await connect() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serverURL.isEmpty || username.isEmpty || isConnecting)

            Spacer()

            Divider()

            Button("Quit FoxTunes") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .padding(.bottom, 8)
        }
        .padding()
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        let result = await jellyfinClient.authenticate(
            serverURL: serverURL,
            username: username,
            password: password
        )
        isConnecting = false
        if case .failure(let error) = result {
            switch error {
            case .invalidServerURL: errorMessage = "Invalid server URL"
            case .authenticationFailed: errorMessage = "Invalid username or password"
            case .networkError(let msg): errorMessage = "Network error: \(msg)"
            default: errorMessage = "Connection failed"
            }
        }
    }
}
