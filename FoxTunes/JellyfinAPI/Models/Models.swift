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

struct BaseItem: Codable, Identifiable {
    let Id: String
    let Name: String
    let Type: String
    let AlbumArtist: String?
    let Album: String?
    let IndexNumber: Int?
    let RunTimeTicks: Int64?
    let MediaSources: [MediaSource]?

    var id: String { Id }

    var durationSeconds: TimeInterval? {
        guard let ticks = RunTimeTicks else { return nil }
        return TimeInterval(ticks) / 10_000_000
    }
}

struct MediaSource: Codable {
    let Id: String
    let Container: String
    let Bitrate: Int?
}

struct ItemsResponse: Codable {
    let Items: [BaseItem]
    let TotalRecordCount: Int
}
