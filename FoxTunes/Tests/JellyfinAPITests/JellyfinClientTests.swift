import XCTest
@testable import JellyfinAPI

final class JellyfinClientTests: XCTestCase {
    func testStreamURLConstruction() {
        let client = JellyfinClient()
        // Client must be authenticated to produce URLs; test structure compiles
        let url = client.streamURL(for: "item123", mediaSourceId: "source456")
        XCTAssertNil(url, "Stream URL should be nil when not authenticated")
    }

    func testImageURLConstruction() {
        let client = JellyfinClient()
        let url = client.imageURL(for: "item123", maxWidth: 60)
        XCTAssertNil(url, "Image URL should be nil when not authenticated")
    }

    func testModelsDecodable() throws {
        let json = """
        {
            "Items": [
                {
                    "Id": "abc",
                    "Name": "Test Track",
                    "Type": "Audio",
                    "IndexNumber": 1,
                    "RunTimeTicks": 30000000000
                }
            ],
            "TotalRecordCount": 1
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ItemsResponse.self, from: json)
        XCTAssertEqual(response.Items.count, 1)
        XCTAssertEqual(response.Items[0].Name, "Test Track")
        XCTAssertEqual(response.Items[0].durationSeconds, 3000.0, accuracy: 0.1)
    }
}
