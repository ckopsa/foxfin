import SwiftUI
import JellyfinAPI
import AudioEngine

struct MainWindowView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var selectedTab: SidebarTab = .library

    enum SidebarTab: String, CaseIterable, Identifiable {
        case library = "Library"
        case songs = "Songs"
        case queue = "Queue"
        case search = "Search"
        case settings = "Settings"

        var id: String { rawValue }

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
        if jellyfinClient.isAuthenticated {
            VStack(spacing: 0) {
                NavigationSplitView {
                    List(SidebarTab.allCases, selection: $selectedTab) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                    .navigationTitle("FoxTunes")
                    .listStyle(.sidebar)
                } detail: {
                    switch selectedTab {
                    case .library: MainLibraryView()
                    case .songs: MainSongsView()
                    case .queue: MainQueueView()
                    case .search: MainSearchView()
                    case .settings: MainSettingsView()
                    }
                }

                Divider()
                TransportBar()
            }
        } else {
            MainConnectionView()
        }
    }
}

// MARK: - Transport Bar

struct TransportBar: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var jellyfinClient: JellyfinClient

    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: artURL) { image in
                image.resizable()
            } placeholder: {
                Image(systemName: "music.note")
                    .frame(width: 44, height: 44)
                    .background(Color.secondary.opacity(0.1))
            }
            .frame(width: 44, height: 44)
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
            .frame(minWidth: 120, alignment: .leading)

            Spacer()

            HStack(spacing: 12) {
                Button(action: { audioEngine.queue.toggleShuffle() }) {
                    Image(systemName: audioEngine.queue.shuffleEnabled ? "shuffle.circle.fill" : "shuffle")
                        .foregroundColor(audioEngine.queue.shuffleEnabled ? .accentColor : .primary)
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
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if audioEngine.duration > 0 {
                Text(formatTime(audioEngine.elapsed))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                ProgressView(value: audioEngine.elapsed, total: audioEngine.duration)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                Text(formatTime(audioEngine.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 4) {
                Image(systemName: volumeIcon)
                    .font(.caption)
                Slider(value: $audioEngine.volume, in: 0...1)
                    .frame(width: 80)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var artURL: URL? {
        guard let track = audioEngine.currentTrack else { return nil }
        return jellyfinClient.imageURL(for: track.id, maxWidth: 88)
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

// MARK: - Library

struct MainLibraryView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var artists: [BaseItem] = []
    @State private var selectedArtist: BaseItem?
    @State private var albums: [BaseItem] = []
    @State private var selectedAlbum: BaseItem?
    @State private var tracks: [BaseItem] = []
    @State private var isLoading = false

    var body: some View {
        HSplitView {
            // Artist list
            List(artists, selection: Binding(
                get: { selectedArtist?.Id },
                set: { id in
                    selectedArtist = artists.first { $0.Id == id }
                    selectedAlbum = nil
                    tracks = []
                    if let artistId = id {
                        Task { await loadAlbums(artistId: artistId) }
                    }
                }
            )) { artist in
                Text(artist.Name).tag(artist.Id)
            }
            .frame(minWidth: 150)

            // Album list
            if selectedArtist != nil {
                List(albums, selection: Binding(
                    get: { selectedAlbum?.Id },
                    set: { id in
                        selectedAlbum = albums.first { $0.Id == id }
                        if let albumId = id {
                            Task { await loadTracks(albumId: albumId) }
                        }
                    }
                )) { album in
                    HStack(spacing: 8) {
                        AsyncImage(url: jellyfinClient.imageURL(for: album.Id, maxWidth: 40)) { img in
                            img.resizable()
                        } placeholder: {
                            Color.secondary.opacity(0.15)
                        }
                        .frame(width: 36, height: 36)
                        .cornerRadius(3)

                        Text(album.Name)
                    }
                    .tag(album.Id)
                }
                .frame(minWidth: 180)
            }

            // Track list
            if selectedAlbum != nil {
                List(tracks) { track in
                    Button { playAlbumFromTrack(track) } label: {
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
                .frame(minWidth: 200)
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .task { await loadArtists() }
    }

    private func loadArtists() async {
        isLoading = true
        if case .success(let items) = await jellyfinClient.fetchArtists() {
            artists = items
        }
        isLoading = false
    }

    private func loadAlbums(artistId: String) async {
        if case .success(let items) = await jellyfinClient.fetchAlbums(byArtistId: artistId) {
            albums = items
        }
    }

    private func loadTracks(albumId: String) async {
        if case .success(let items) = await jellyfinClient.fetchTracks(inAlbumId: albumId) {
            tracks = items
        }
    }

    private func playAlbumFromTrack(_ item: BaseItem) {
        let allTracks = tracks.compactMap { baseItemToMainTrack($0, jellyfinClient: jellyfinClient) }
        guard let index = allTracks.firstIndex(where: { $0.id == item.Id }) else { return }
        audioEngine.playQueue(tracks: allTracks, startAt: index)
    }
}

// MARK: - Songs

struct MainSongsView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var songs: [BaseItem] = []
    @State private var filteredSongs: [BaseItem] = []
    @State private var query = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter songs...", text: $query)
                    .textFieldStyle(.plain)
                    .onChange(of: query) { newValue in applyFilter(newValue) }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.05))

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                Table(filteredSongs) {
                    TableColumn("Name") { song in
                        Button { playSong(song) } label: {
                            Text(song.Name).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                    .width(min: 150)

                    TableColumn("Artist") { song in
                        Text(song.AlbumArtist ?? "Unknown Artist")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 120)

                    TableColumn("Album") { song in
                        Text(song.Album ?? "")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 120)

                    TableColumn("Duration") { song in
                        if let dur = song.durationSeconds {
                            Text(formatDuration(dur))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .width(60)
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
        guard !trimmed.isEmpty else { filteredSongs = songs; return }
        let needle = trimmed.localizedLowercase
        filteredSongs = songs.filter {
            $0.Name.localizedLowercase.contains(needle) ||
            ($0.AlbumArtist?.localizedLowercase.contains(needle) ?? false) ||
            ($0.Album?.localizedLowercase.contains(needle) ?? false)
        }
    }

    private func playSong(_ song: BaseItem) {
        let queue = filteredSongs.compactMap { baseItemToMainTrack($0, jellyfinClient: jellyfinClient) }
        guard let index = queue.firstIndex(where: { $0.id == song.Id }) else { return }
        audioEngine.playQueue(tracks: queue, startAt: index)
    }
}

// MARK: - Queue

struct MainQueueView: View {
    @EnvironmentObject var audioEngine: AudioEngine

    var body: some View {
        if audioEngine.queue.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "music.note.list")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Queue is empty")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Play something from the library")
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                List {
                    ForEach(Array(audioEngine.queue.tracks.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 12) {
                            if index == audioEngine.queue.currentIndex {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.accentColor)
                                    .frame(width: 24)
                            } else {
                                Text("\(index + 1)")
                                    .foregroundColor(.secondary)
                                    .frame(width: 24)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.name).lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(formatDuration(track.durationSeconds))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
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
                        Label("Shuffle", systemImage: audioEngine.queue.shuffleEnabled ? "shuffle.circle.fill" : "shuffle")
                    }
                    Button(action: { audioEngine.queue.cycleRepeat() }) {
                        Label("Repeat", systemImage: repeatIcon)
                    }
                    Spacer()
                    Button("Clear Queue") { audioEngine.clearQueue() }
                }
                .buttonStyle(.plain)
                .padding(12)
            }
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

struct MainSearchView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var query = ""
    @State private var results: [BaseItem] = []
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search music...", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await search() } }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.05))

            if isSearching {
                Spacer()
                ProgressView()
                Spacer()
            } else if results.isEmpty && !query.isEmpty {
                Spacer()
                Text("No results")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(results) { item in
                    Button { playItem(item) } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: jellyfinClient.imageURL(for: item.Id, maxWidth: 48)) { img in
                                img.resizable()
                            } placeholder: {
                                Color.secondary.opacity(0.15)
                            }
                            .frame(width: 44, height: 44)
                            .cornerRadius(4)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.Name).lineLimit(1)
                                Text(subtitle(for: item))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(item.itemType)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
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
              let track = baseItemToMainTrack(item, jellyfinClient: jellyfinClient) else { return }
        audioEngine.playQueue(tracks: [track])
    }

    private func subtitle(for item: BaseItem) -> String {
        switch item.itemType {
        case "Audio":
            return [item.AlbumArtist ?? "Unknown Artist", item.Album].compactMap { $0 }.joined(separator: " — ")
        case "MusicAlbum": return item.AlbumArtist ?? ""
        default: return item.itemType
        }
    }
}

// MARK: - Settings

struct MainSettingsView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if jellyfinClient.isAuthenticated {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("Connected")
                    .font(.title2)
                if let url = jellyfinClient.serverURL {
                    Text(url)
                        .foregroundColor(.secondary)
                }

                Button("Disconnect") {
                    jellyfinClient.logout()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Connection

struct MainConnectionView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "music.note.house")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Connect to Jellyfin")
                .font(.title)

            VStack(spacing: 10) {
                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 300)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }

            Button(isConnecting ? "Connecting..." : "Connect") {
                Task { await connect() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serverURL.isEmpty || username.isEmpty || isConnecting)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Helpers

private func baseItemToMainTrack(_ item: BaseItem, jellyfinClient: JellyfinClient) -> Track? {
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
