import Foundation

struct AuthRequest: Codable {
    let Username: String
    let Pw: String
}

struct AuthResponse: Codable {
    let User: JellyfinUser
    let AccessToken: String
    let ServerId: String
}

struct JellyfinUser: Codable {
    let Id: String
    let Name: String
}

public struct BaseItem: Codable, Identifiable {
    public let Id: String
    public let Name: String
    public let itemType: String
    public let AlbumArtist: String?
    public let Album: String?
    public let IndexNumber: Int?
    public let RunTimeTicks: Int64?
    public let MediaSources: [MediaSource]?

    enum CodingKeys: String, CodingKey {
        case Id
        case Name
        case itemType = "Type"
        case AlbumArtist
        case Album
        case IndexNumber
        case RunTimeTicks
        case MediaSources
    }

    public var id: String { Id }

    public var durationSeconds: TimeInterval? {
        guard let ticks = RunTimeTicks else { return nil }
        return TimeInterval(ticks) / 10_000_000
    }
}

public struct MediaSource: Codable {
    public let Id: String
    public let Container: String
    public let Bitrate: Int?
}

struct ItemsResponse: Codable {
    let Items: [BaseItem]
    let TotalRecordCount: Int
}
