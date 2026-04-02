import Foundation
import Combine
import JellyfinAPI

/// Sync state for individual offline tracks.
enum SyncState: String {
    case pending
    case downloading
    case downloaded
    case error
}

/// Metadata for a pinned album stored in SQLite.
struct PinnedAlbum: Identifiable {
    let itemId: String
    let name: String
    let artist: String
    let pinnedAt: Date
    var totalTracks: Int
    var downloadedTracks: Int

    var id: String { itemId }
    var progress: Double {
        totalTracks > 0 ? Double(downloadedTracks) / Double(totalTracks) : 0
    }
}

/// Metadata for an offline track.
struct OfflineTrack: Identifiable {
    let itemId: String
    let albumId: String
    let name: String
    let artist: String
    let trackNumber: Int
    let durationTicks: Int64
    let container: String
    var filePath: String?
    var fileSize: Int64
    var syncState: SyncState
    var errorMessage: String?

    var id: String { itemId }
    var durationSeconds: TimeInterval { TimeInterval(durationTicks) / 10_000_000 }
}

/// Manages offline content: pinning albums, downloading tracks, serving cached audio.
class OfflineManager: ObservableObject {
    @Published var pinnedAlbums: [PinnedAlbum] = []
    @Published var isOnline = true

    private let jellyfinClient: JellyfinClient
    private let offlineDir: URL
    private let maxStorageBytes: Int64
    private let maxConcurrentDownloads = 2
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var syncQueue: [(trackId: String, action: String)] = []
    private var cancellables = Set<AnyCancellable>()

    // In-memory store (SQLite would be used in production; this is the functional scaffold)
    private var albumStore: [String: PinnedAlbum] = [:]
    private var trackStore: [String: OfflineTrack] = [:]

    init(jellyfinClient: JellyfinClient, maxStorageGB: Int = 2) {
        self.jellyfinClient = jellyfinClient
        self.maxStorageBytes = Int64(maxStorageGB) * 1_000_000_000

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.offlineDir = appSupport.appendingPathComponent("FoxTunes/Offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: offlineDir, withIntermediateDirectories: true)
    }

    // MARK: - Pin / Unpin

    /// Pin an album for offline playback. Downloads all tracks in background.
    func pin(album: BaseItem, tracks: [BaseItem]) {
        let albumDir = offlineDir.appendingPathComponent(album.Id, isDirectory: true)
        try? FileManager.default.createDirectory(at: albumDir, withIntermediateDirectories: true)

        let pinned = PinnedAlbum(
            itemId: album.Id,
            name: album.Name,
            artist: album.AlbumArtist ?? "",
            pinnedAt: Date(),
            totalTracks: tracks.count,
            downloadedTracks: 0
        )
        albumStore[album.Id] = pinned

        for item in tracks {
            let container = item.MediaSources?.first?.Container ?? "unknown"
            let offlineTrack = OfflineTrack(
                itemId: item.Id,
                albumId: album.Id,
                name: item.Name,
                artist: item.AlbumArtist ?? "",
                trackNumber: item.IndexNumber ?? 0,
                durationTicks: item.RunTimeTicks ?? 0,
                container: container,
                filePath: nil,
                fileSize: 0,
                syncState: .pending,
                errorMessage: nil
            )
            trackStore[item.Id] = offlineTrack
            syncQueue.append((trackId: item.Id, action: "download"))
        }

        refreshPublished()
        processQueue()
    }

    /// Unpin an album and remove downloaded files.
    func unpin(albumId: String) {
        // Cancel in-flight downloads for this album
        let albumTracks = trackStore.values.filter { $0.albumId == albumId }
        for track in albumTracks {
            downloadTasks[track.itemId]?.cancel()
            downloadTasks.removeValue(forKey: track.itemId)
            trackStore.removeValue(forKey: track.itemId)
        }
        syncQueue.removeAll { trackStore[$0.trackId]?.albumId == albumId }

        // Remove files
        let albumDir = offlineDir.appendingPathComponent(albumId)
        try? FileManager.default.removeItem(at: albumDir)

        albumStore.removeValue(forKey: albumId)
        refreshPublished()
    }

    /// Check if an album is pinned.
    func isPinned(_ albumId: String) -> Bool {
        albumStore[albumId] != nil
    }

    // MARK: - Offline Playback

    /// Get a local file URL for a track if downloaded, nil otherwise.
    func localURL(for trackId: String) -> URL? {
        guard let track = trackStore[trackId],
              track.syncState == .downloaded,
              let path = track.filePath else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Get all downloaded tracks for an album, sorted by track number.
    func offlineTracks(for albumId: String) -> [OfflineTrack] {
        trackStore.values
            .filter { $0.albumId == albumId && $0.syncState == .downloaded }
            .sorted { $0.trackNumber < $1.trackNumber }
    }

    // MARK: - Storage

    /// Total bytes used by offline content.
    var diskUsage: Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: offlineDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    var formattedDiskUsage: String {
        ByteCountFormatter.string(fromByteCount: diskUsage, countStyle: .file)
    }

    var formattedStorageLimit: String {
        ByteCountFormatter.string(fromByteCount: maxStorageBytes, countStyle: .file)
    }

    // MARK: - Sync Queue Processing

    private func processQueue() {
        let activeCount = downloadTasks.values.count
        guard activeCount < maxConcurrentDownloads, !syncQueue.isEmpty else { return }

        let slotsAvailable = maxConcurrentDownloads - activeCount
        let batch = Array(syncQueue.prefix(slotsAvailable))
        syncQueue.removeFirst(min(slotsAvailable, syncQueue.count))

        for entry in batch {
            guard entry.action == "download" else { continue }
            guard var track = trackStore[entry.trackId] else { continue }

            track.syncState = .downloading
            trackStore[entry.trackId] = track

            let task = Task { [weak self] in
                guard let self else { return }
                await self.downloadTrack(trackId: entry.trackId)
                self.downloadTasks.removeValue(forKey: entry.trackId)
                self.processQueue() // Process next in queue
            }
            downloadTasks[entry.trackId] = task
        }
    }

    private func downloadTrack(trackId: String) async {
        guard var track = trackStore[trackId] else { return }
        guard let source = track.container != "unknown" ? track.container : nil,
              let streamURL = jellyfinClient.streamURL(for: trackId, mediaSourceId: trackId) else {
            track.syncState = .error
            track.errorMessage = "Cannot construct stream URL"
            trackStore[trackId] = track
            refreshPublished()
            return
        }

        let albumDir = offlineDir.appendingPathComponent(track.albumId)
        let filename = String(format: "%02d - %@.%@", track.trackNumber, sanitize(track.name), source)
        let destURL = albumDir.appendingPathComponent(filename)

        do {
            let (data, response) = try await URLSession.shared.data(from: streamURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                track.syncState = .error
                track.errorMessage = "HTTP error"
                trackStore[trackId] = track
                refreshPublished()
                return
            }

            try data.write(to: destURL)
            track.filePath = destURL.path
            track.fileSize = Int64(data.count)
            track.syncState = .downloaded
            track.errorMessage = nil
            trackStore[trackId] = track

            // Update album progress
            if var album = albumStore[track.albumId] {
                album.downloadedTracks = trackStore.values
                    .filter { $0.albumId == track.albumId && $0.syncState == .downloaded }
                    .count
                albumStore[track.albumId] = album
            }

            refreshPublished()
        } catch {
            if !Task.isCancelled {
                track.syncState = .error
                track.errorMessage = error.localizedDescription
                trackStore[trackId] = track
                refreshPublished()
            }
        }
    }

    private func refreshPublished() {
        pinnedAlbums = albumStore.values.sorted { $0.pinnedAt > $1.pinnedAt }
    }

    private func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
}
