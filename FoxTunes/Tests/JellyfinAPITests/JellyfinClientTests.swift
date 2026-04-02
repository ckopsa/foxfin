import XCTest
@testable import JellyfinAPI

final class JellyfinClientTests: XCTestCase {

    // MARK: - URL Construction

    func testStreamURLNilWhenNotAuthenticated() {
        let client = JellyfinClient()
        let url = client.streamURL(for: "item123", mediaSourceId: "source456")
        XCTAssertNil(url, "Stream URL should be nil when not authenticated")
    }

    func testImageURLNilWhenNoServer() {
        let client = JellyfinClient()
        let url = client.imageURL(for: "item123", maxWidth: 60)
        XCTAssertNil(url, "Image URL should be nil when server not set")
    }

    // MARK: - Model Decoding

    func testBaseItemDecoding() throws {
        let json = """
        {
            "Items": [
                {
                    "Id": "abc123",
                    "Name": "Test Track",
                    "Type": "Audio",
                    "AlbumArtist": "Test Artist",
                    "Album": "Test Album",
                    "IndexNumber": 1,
                    "RunTimeTicks": 30000000000,
                    "MediaSources": [
                        {"Id": "src1", "Container": "flac", "Bitrate": 1411000}
                    ]
                }
            ],
            "TotalRecordCount": 1
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ItemsResponse.self, from: json)
        XCTAssertEqual(response.Items.count, 1)

        let item = response.Items[0]
        XCTAssertEqual(item.Id, "abc123")
        XCTAssertEqual(item.Name, "Test Track")
        XCTAssertEqual(item.itemType, "Audio")
        XCTAssertEqual(item.AlbumArtist, "Test Artist")
        XCTAssertEqual(item.Album, "Test Album")
        XCTAssertEqual(item.IndexNumber, 1)
        XCTAssertEqual(item.durationSeconds!, 3000.0, accuracy: 0.1)
        XCTAssertEqual(item.MediaSources?.first?.Container, "flac")
        XCTAssertEqual(item.MediaSources?.first?.Bitrate, 1411000)
    }

    func testBaseItemOptionalFieldsNil() throws {
        let json = """
        {
            "Items": [
                {"Id": "xyz", "Name": "Minimal", "Type": "MusicArtist"}
            ],
            "TotalRecordCount": 1
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ItemsResponse.self, from: json)
        let item = response.Items[0]
        XCTAssertNil(item.AlbumArtist)
        XCTAssertNil(item.Album)
        XCTAssertNil(item.IndexNumber)
        XCTAssertNil(item.RunTimeTicks)
        XCTAssertNil(item.durationSeconds)
        XCTAssertNil(item.MediaSources)
    }

    func testAuthResponseDecoding() throws {
        let json = """
        {
            "User": {"Id": "user1", "Name": "testuser"},
            "AccessToken": "tok_abc123",
            "ServerId": "server1"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AuthResponse.self, from: json)
        XCTAssertEqual(response.User.Id, "user1")
        XCTAssertEqual(response.User.Name, "testuser")
        XCTAssertEqual(response.AccessToken, "tok_abc123")
        XCTAssertEqual(response.ServerId, "server1")
    }

    // MARK: - Error Types

    func testJellyfinErrorEquality() {
        XCTAssertEqual(JellyfinError.notAuthenticated, JellyfinError.notAuthenticated)
        XCTAssertEqual(JellyfinError.invalidServerURL, JellyfinError.invalidServerURL)
        XCTAssertEqual(JellyfinError.httpError(statusCode: 404), JellyfinError.httpError(statusCode: 404))
        XCTAssertNotEqual(JellyfinError.httpError(statusCode: 404), JellyfinError.httpError(statusCode: 500))
        XCTAssertNotEqual(JellyfinError.notAuthenticated, JellyfinError.invalidServerURL)
    }

    // MARK: - Duration Calculation

    func testDurationTicksConversion() throws {
        let json = """
        {"Items": [{"Id": "a", "Name": "t", "Type": "Audio", "RunTimeTicks": 2735390000}], "TotalRecordCount": 1}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ItemsResponse.self, from: json)
        // 2735390000 ticks / 10_000_000 = 273.539 seconds = ~4:33
        XCTAssertEqual(response.Items[0].durationSeconds!, 273.539, accuracy: 0.001)
    }

    // MARK: - Client State

    func testLogoutClearsState() {
        let client = JellyfinClient()
        client.logout()
        XCTAssertFalse(client.isAuthenticated)
        XCTAssertNil(client.userId)
        XCTAssertNil(client.serverURL)
    }

    func testAuthenticateRejectsInvalidURL() async {
        let client = JellyfinClient()
        let result = await client.authenticate(serverURL: "", username: "user", password: "pass")
        switch result {
        case .success:
            XCTFail("Should fail with empty URL")
        case .failure(let error):
            XCTAssertEqual(error, JellyfinError.invalidServerURL)
        }
    }
}
