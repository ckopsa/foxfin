import Foundation

/// Jellyfin REST API client. Handles authentication, library browsing,
/// and stream URL construction.
class JellyfinClient: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userId: String?

    private var serverURL: String?
    private var accessToken: String?

    func authenticate(serverURL: String, username: String, password: String) async {
        self.serverURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: "\(self.serverURL!)/Users/AuthenticateByName") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")

        let body = AuthRequest(Username: username, Pw: password)
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(AuthResponse.self, from: data)
            await MainActor.run {
                self.accessToken = response.AccessToken
                self.userId = response.User.Id
                self.isAuthenticated = true
            }
        } catch {
            await MainActor.run {
                self.isAuthenticated = false
            }
        }
    }

    func streamURL(for itemId: String, mediaSourceId: String) -> URL? {
        guard let serverURL, let accessToken else { return nil }
        var components = URLComponents(string: "\(serverURL)/Audio/\(itemId)/stream")
        components?.queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
            URLQueryItem(name: "api_key", value: accessToken),
        ]
        return components?.url
    }

    func imageURL(for itemId: String, maxWidth: Int = 300) -> URL? {
        guard let serverURL else { return nil }
        var components = URLComponents(string: "\(serverURL)/Items/\(itemId)/Images/Primary")
        components?.queryItems = [
            URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            URLQueryItem(name: "quality", value: "90"),
        ]
        return components?.url
    }

    private func authorizationHeader() -> String {
        "MediaBrowser Client=\"FoxTunes\", Device=\"macOS\", DeviceId=\"foxtunes-\(ProcessInfo.processInfo.globallyUniqueString)\", Version=\"1.0.0\""
    }
}
