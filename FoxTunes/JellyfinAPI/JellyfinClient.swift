import Foundation

/// Typed errors for Jellyfin API operations.
public enum JellyfinError: Error, Equatable {
    case notAuthenticated
    case invalidServerURL
    case authenticationFailed(statusCode: Int)
    case httpError(statusCode: Int)
    case networkError(String)
    case decodingError(String)

    public static func == (lhs: JellyfinError, rhs: JellyfinError) -> Bool {
        switch (lhs, rhs) {
        case (.notAuthenticated, .notAuthenticated): return true
        case (.invalidServerURL, .invalidServerURL): return true
        case let (.authenticationFailed(a), .authenticationFailed(b)): return a == b
        case let (.httpError(a), .httpError(b)): return a == b
        case let (.networkError(a), .networkError(b)): return a == b
        case let (.decodingError(a), .decodingError(b)): return a == b
        default: return false
        }
    }
}

/// Jellyfin REST API client. Handles authentication, library browsing,
/// search, favorites, playlists, and stream URL construction.
public class JellyfinClient: ObservableObject {
    @Published public var isAuthenticated = false
    @Published public var userId: String?
    @Published public var serverName: String?

    public private(set) var serverURL: String?
    private var accessToken: String?
    private var username: String?
    private var password: String?
    private let deviceId: String

    public init() {
        self.deviceId = "foxtunes-" + (UserDefaults.standard.string(forKey: "FoxTunesDeviceId") ?? {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "FoxTunesDeviceId")
            return id
        }())
    }

    // MARK: - Authentication

    public func authenticate(serverURL: String, username: String, password: String) async -> Result<Void, JellyfinError> {
        let trimmed = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard URL(string: trimmed) != nil else {
            return .failure(.invalidServerURL)
        }

        self.serverURL = trimmed
        self.username = username
        self.password = password

        guard let url = URL(string: "\(trimmed)/Users/AuthenticateByName") else {
            return .failure(.invalidServerURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")

        let body = AuthRequest(Username: username, Pw: password)
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.networkError("Invalid response"))
            }
            guard http.statusCode == 200 else {
                return .failure(.authenticationFailed(statusCode: http.statusCode))
            }

            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            await MainActor.run {
                self.accessToken = authResponse.AccessToken
                self.userId = authResponse.User.Id
                self.serverName = authResponse.ServerId
                self.isAuthenticated = true
            }

            try? KeychainHelper.save(token: authResponse.AccessToken, for: trimmed)
            return .success(())
        } catch let error as JellyfinError {
            return .failure(error)
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    public func restoreSession(serverURL: String) async -> Bool {
        let trimmed = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let token = KeychainHelper.loadToken(for: trimmed) else { return false }
        self.serverURL = trimmed
        self.accessToken = token

        // Verify token is still valid
        switch await fetchCurrentUser() {
        case .success(let user):
            await MainActor.run {
                self.userId = user.Id
                self.isAuthenticated = true
            }
            return true
        case .failure:
            self.accessToken = nil
            KeychainHelper.deleteToken(for: trimmed)
            return false
        }
    }

    public func logout() {
        if let serverURL {
            KeychainHelper.deleteToken(for: serverURL)
        }
        accessToken = nil
        userId = nil
        serverURL = nil
        isAuthenticated = false
    }

    // MARK: - Library Browsing

    public func fetchArtists() async -> Result<[BaseItem], JellyfinError> {
        guard let userId else { return .failure(.notAuthenticated) }
        return await getItems(path: "/Artists", query: [
            "userId": userId,
            "sortBy": "SortName",
            "sortOrder": "Ascending",
        ])
    }

    public func fetchAlbums(byArtistId artistId: String) async -> Result<[BaseItem], JellyfinError> {
        guard let userId else { return .failure(.notAuthenticated) }
        return await getItems(path: "/Items", query: [
            "userId": userId,
            "parentId": artistId,
            "IncludeItemTypes": "MusicAlbum",
            "sortBy": "ProductionYear,SortName",
            "sortOrder": "Descending,Ascending",
        ])
    }

    public func fetchTracks(inAlbumId albumId: String) async -> Result<[BaseItem], JellyfinError> {
        guard let userId else { return .failure(.notAuthenticated) }
        return await getItems(path: "/Items", query: [
            "userId": userId,
            "parentId": albumId,
            "IncludeItemTypes": "Audio",
            "Fields": "MediaSources",
            "sortBy": "IndexNumber",
            "sortOrder": "Ascending",
        ])
    }

    public func fetchSongs() async -> Result<[BaseItem], JellyfinError> {
        guard let userId else { return .failure(.notAuthenticated) }
        return await getItems(path: "/Items", query: [
            "userId": userId,
            "IncludeItemTypes": "Audio",
            "Recursive": "true",
            "Fields": "MediaSources",
            "sortBy": "SortName",
            "sortOrder": "Ascending",
        ])
    }

    // MARK: - Search

    public func search(query searchTerm: String) async -> Result<[BaseItem], JellyfinError> {
        guard let userId else { return .failure(.notAuthenticated) }
        return await getItems(path: "/Items", query: [
            "userId": userId,
            "searchTerm": searchTerm,
            "IncludeItemTypes": "Audio,MusicAlbum,MusicArtist",
            "Recursive": "true",
            "Fields": "MediaSources",
            "Limit": "50",
        ])
    }

    // MARK: - Favorites

    public func fetchFavorites() async -> Result<[BaseItem], JellyfinError> {
        guard let userId else { return .failure(.notAuthenticated) }
        return await getItems(path: "/Items", query: [
            "userId": userId,
            "IsFavorite": "true",
            "IncludeItemTypes": "Audio,MusicAlbum,MusicArtist",
            "Recursive": "true",
            "Fields": "MediaSources",
            "sortBy": "SortName",
            "sortOrder": "Ascending",
        ])
    }

    public func toggleFavorite(itemId: String, favorite: Bool) async -> Result<Void, JellyfinError> {
        guard let userId else { return .failure(.notAuthenticated) }
        let path = "/Users/\(userId)/FavoriteItems/\(itemId)"
        let method = favorite ? "POST" : "DELETE"
        return await performRequest(path: path, method: method)
    }

    // MARK: - Playlists

    public func fetchPlaylists() async -> Result<[BaseItem], JellyfinError> {
        guard let userId else { return .failure(.notAuthenticated) }
        return await getItems(path: "/Items", query: [
            "userId": userId,
            "IncludeItemTypes": "Playlist",
            "Recursive": "true",
            "sortBy": "SortName",
            "sortOrder": "Ascending",
        ])
    }

    public func fetchPlaylistItems(playlistId: String) async -> Result<[BaseItem], JellyfinError> {
        guard let userId else { return .failure(.notAuthenticated) }
        return await getItems(path: "/Playlists/\(playlistId)/Items", query: [
            "userId": userId,
        ])
    }

    // MARK: - Instant Mix

    public func fetchInstantMix(for itemId: String, limit: Int = 50) async -> Result<[BaseItem], JellyfinError> {
        guard let userId else { return .failure(.notAuthenticated) }
        return await getItems(path: "/Items/\(itemId)/InstantMix", query: [
            "userId": userId,
            "Fields": "MediaSources",
            "Limit": String(limit),
        ])
    }

    // MARK: - URLs

    public func streamURL(for itemId: String, mediaSourceId: String) -> URL? {
        guard let serverURL, let accessToken else { return nil }
        var components = URLComponents(string: "\(serverURL)/Audio/\(itemId)/stream")
        components?.queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
            URLQueryItem(name: "api_key", value: accessToken),
        ]
        return components?.url
    }

    public func imageURL(for itemId: String, maxWidth: Int = 300) -> URL? {
        guard let serverURL else { return nil }
        var components = URLComponents(string: "\(serverURL)/Items/\(itemId)/Images/Primary")
        components?.queryItems = [
            URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            URLQueryItem(name: "quality", value: "90"),
        ]
        return components?.url
    }

    // MARK: - Internal

    private func fetchCurrentUser() async -> Result<JellyfinUser, JellyfinError> {
        guard let userId else { return .failure(.notAuthenticated) }
        let result: Result<Data, JellyfinError> = await fetchData(path: "/Users/\(userId)")
        switch result {
        case .success(let data):
            do {
                let user = try JSONDecoder().decode(JellyfinUser.self, from: data)
                return .success(user)
            } catch {
                return .failure(.decodingError(error.localizedDescription))
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    private func getItems(path: String, query: [String: String]) async -> Result<[BaseItem], JellyfinError> {
        let result: Result<Data, JellyfinError> = await fetchData(path: path, query: query)
        switch result {
        case .success(let data):
            do {
                let response = try JSONDecoder().decode(ItemsResponse.self, from: data)
                return .success(response.Items)
            } catch {
                return .failure(.decodingError(error.localizedDescription))
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    private func fetchData(path: String, query: [String: String] = [:]) async -> Result<Data, JellyfinError> {
        guard let serverURL, let accessToken else { return .failure(.notAuthenticated) }
        guard var components = URLComponents(string: "\(serverURL)\(path)") else {
            return .failure(.invalidServerURL)
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { return .failure(.invalidServerURL) }

        var request = URLRequest(url: url)
        request.setValue(accessToken, forHTTPHeaderField: "X-Emby-Token")
        request.setValue(authorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.networkError("Invalid response"))
            }

            if http.statusCode == 401 {
                // Attempt re-auth if credentials are available
                if let username, let password {
                    let reauth = await authenticate(serverURL: serverURL, username: username, password: password)
                    switch reauth {
                    case .success:
                        return await fetchData(path: path, query: query)
                    case .failure(let error):
                        await MainActor.run { self.isAuthenticated = false }
                        return .failure(error)
                    }
                }
                await MainActor.run { self.isAuthenticated = false }
                return .failure(.notAuthenticated)
            }

            guard (200...299).contains(http.statusCode) else {
                return .failure(.httpError(statusCode: http.statusCode))
            }
            return .success(data)
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    private func performRequest(path: String, method: String) async -> Result<Void, JellyfinError> {
        guard let serverURL, let accessToken else { return .failure(.notAuthenticated) }
        guard let url = URL(string: "\(serverURL)\(path)") else {
            return .failure(.invalidServerURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(accessToken, forHTTPHeaderField: "X-Emby-Token")
        request.setValue(authorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.networkError("Invalid response"))
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(.httpError(statusCode: http.statusCode))
            }
            return .success(())
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    private func authorizationHeader() -> String {
        "MediaBrowser Client=\"FoxTunes\", Device=\"macOS\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\""
    }
}
