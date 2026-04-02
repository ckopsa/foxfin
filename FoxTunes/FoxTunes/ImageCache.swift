import AppKit
import Foundation

/// Two-tier image cache (memory + disk) with request coalescing and LRU eviction.
class ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let diskCacheURL: URL
    private let maxDiskBytes: Int64
    private var inflightRequests: [String: Task<NSImage?, Error>] = [:]
    private let queue = DispatchQueue(label: "com.foxtunes.imagecache")

    init(maxDiskMB: Int = 500) {
        self.maxDiskBytes = Int64(maxDiskMB) * 1_000_000

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.diskCacheURL = appSupport.appendingPathComponent("FoxTunes/Cache/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        memoryCache.countLimit = 100
    }

    /// Fetch image, checking memory → disk → network in order.
    func image(for url: URL, cacheKey: String) async -> NSImage? {
        let nsKey = cacheKey as NSString

        // Memory hit
        if let img = memoryCache.object(forKey: nsKey) {
            return img
        }

        // Disk hit
        let diskPath = diskCacheURL.appendingPathComponent(sanitizeFilename(cacheKey))
        if let img = NSImage(contentsOf: diskPath) {
            memoryCache.setObject(img, forKey: nsKey)
            touchFile(at: diskPath)
            return img
        }

        // Coalesce concurrent requests for same key
        let existing: Task<NSImage?, Error>? = queue.sync { inflightRequests[cacheKey] }
        if let existing {
            return try? await existing.value
        }

        let task = Task<NSImage?, Error> {
            defer {
                queue.sync { _ = inflightRequests.removeValue(forKey: cacheKey) }
            }

            do {
                var request = URLRequest(url: url)
                // ETag support: check if we have a stored ETag
                let etagPath = diskPath.appendingPathExtension("etag")
                if let etag = try? String(contentsOf: etagPath, encoding: .utf8) {
                    request.setValue(etag, forHTTPHeaderField: "If-None-Match")
                }

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return nil }

                if http.statusCode == 304 {
                    // Not modified — load from disk
                    if let img = NSImage(contentsOf: diskPath) {
                        self.memoryCache.setObject(img, forKey: nsKey)
                        return img
                    }
                }

                guard (200...299).contains(http.statusCode) else { return nil }

                guard let img = NSImage(data: data) else { return nil }
                self.memoryCache.setObject(img, forKey: nsKey)

                // Write to disk
                try? data.write(to: diskPath)
                if let etag = http.value(forHTTPHeaderField: "ETag") {
                    try? etag.write(to: etagPath, atomically: true, encoding: .utf8)
                }

                return img
            } catch {
                return nil
            }
        }

        queue.sync { inflightRequests[cacheKey] = task }
        return try? await task.value
    }

    /// Convenience for Jellyfin album art.
    func albumArt(itemId: String, serverURL: String, maxWidth: Int = 300) async -> NSImage? {
        let key = "\(itemId)_\(maxWidth)"
        guard let url = URL(string: "\(serverURL)/Items/\(itemId)/Images/Primary?maxWidth=\(maxWidth)&quality=90") else {
            return nil
        }
        return await image(for: url, cacheKey: key)
    }

    /// Current disk cache size in bytes.
    var diskUsage: Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: diskCacheURL,
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

    /// Evict oldest entries until under size limit.
    func evictIfNeeded() {
        guard diskUsage > maxDiskBytes else { return }

        guard let enumerator = FileManager.default.enumerator(
            at: diskCacheURL,
            includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        struct CacheEntry {
            let url: URL
            let accessDate: Date
            let size: Int64
        }

        var entries: [CacheEntry] = []
        for case let fileURL as URL in enumerator {
            guard !fileURL.pathExtension.hasSuffix("etag") else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.contentAccessDateKey, .fileSizeKey])
            entries.append(CacheEntry(
                url: fileURL,
                accessDate: values?.contentAccessDate ?? .distantPast,
                size: Int64(values?.fileSize ?? 0)
            ))
        }

        // Sort oldest first
        entries.sort { $0.accessDate < $1.accessDate }

        var currentSize = diskUsage
        for entry in entries {
            guard currentSize > maxDiskBytes else { break }
            try? FileManager.default.removeItem(at: entry.url)
            // Remove associated etag
            let etagURL = entry.url.appendingPathExtension("etag")
            try? FileManager.default.removeItem(at: etagURL)
            currentSize -= entry.size
        }
    }

    /// Remove all cached images.
    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    private func sanitizeFilename(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private func touchFile(at url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }
}
