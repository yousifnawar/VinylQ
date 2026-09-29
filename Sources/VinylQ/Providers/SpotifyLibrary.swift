import AppKit
import Combine
import Foundation

/// A Spotify playlist, album or artist you've added to VinylQ by link.
struct SpotifyCollection: Codable, Identifiable, Equatable {
    /// `spotify:playlist:…` — what the Spotify app is told to play.
    var uri: String
    var name: String
    /// playlist, album, artist, show…
    var kind: String
    var imageURL: URL?

    var id: String { uri }
}

/// A Spotify link or URI, pulled apart.
struct SpotifyLink: Equatable {
    let kind: String
    let id: String

    var uri: String { "spotify:\(kind):\(id)" }
    var webURL: URL { URL(string: "https://open.spotify.com/\(kind)/\(id)")! }

    private static let kinds: Set<String> = ["playlist", "album", "artist", "show", "episode", "track"]

    /// Accepts `https://open.spotify.com/playlist/…` (with or without a
    /// locale segment or `?si=` tracking), and `spotify:playlist:…` URIs.
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts: [String]
        if trimmed.lowercased().hasPrefix("spotify:") {
            parts = trimmed.split(separator: ":").map(String.init)
        } else if let url = URL(string: trimmed), let host = url.host?.lowercased(),
                  host == "spotify.com" || host.hasSuffix(".spotify.com") || host == "spotify.link" {
            parts = url.pathComponents.filter { $0 != "/" }
        } else {
            return nil
        }
        for index in parts.indices.dropLast() where Self.kinds.contains(parts[index].lowercased()) {
            let candidate = parts[index + 1]
            if Self.looksLikeID(candidate) {
                kind = parts[index].lowercased()
                id = candidate
                return
            }
        }
        return nil
    }

    private static func looksLikeID(_ text: String) -> Bool {
        (16...40).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

/// Your Spotify music, with no account linking at all.
///
/// Spotify only lets registered developer apps list a person's playlists, and
/// since 2026 those are capped at five users and need the developer's own
/// Premium plan — not something a record player should ask of you. So VinylQ does
/// what it can with the Spotify app you're already signed into:
///
/// * it remembers what you play, as a **Recently Played** list you can go back to;
/// * it keeps any playlist, album or artist you **drop in by link** — dragged
///   out of Spotify or pasted — and plays it through the Spotify app.
///
/// Names and covers for those links come from Spotify's public oEmbed endpoint,
/// which needs no key.
@MainActor
final class SpotifyLibrary: ObservableObject {

    @Published private(set) var recent: [Track] = []
    @Published private(set) var saved: [SpotifyCollection] = []

    let cache: SpotifyCache
    var onChange: () -> Void = {}

    private static let recentKey = "spotify.recent"
    private static let savedKey = "spotify.saved"
    private static let recentLimit = 40

    init(cache: SpotifyCache) {
        self.cache = cache
        recent = Self.load([Track].self, key: Self.recentKey) ?? []
        saved = Self.load([SpotifyCollection].self, key: Self.savedKey) ?? []
        cache.setRecent(recent)
        cache.setSaved(saved)
    }

    // MARK: Recently played

    /// Called when Spotify starts a new song.
    func record(_ track: Track) {
        guard !track.isSilence, track.id.hasPrefix("spotify:") else { return }
        var list = recent.filter { $0.id != track.id }
        list.insert(track, at: 0)
        if list.count > Self.recentLimit { list.removeLast(list.count - Self.recentLimit) }
        recent = list
        cache.setRecent(list)
        Self.store(list, key: Self.recentKey)
        onChange()
    }

    func clearRecent() {
        recent = []
        cache.setRecent([])
        Self.store(recent, key: Self.recentKey)
        onChange()
    }

    // MARK: Saved links

    enum AddError: LocalizedError {
        case notALink
        case alreadyAdded(String)

        var errorDescription: String? {
            switch self {
            case .notALink:            return "That isn't a Spotify link. Copy one from Share → Copy link in Spotify."
            case .alreadyAdded(let n): return "\u{201C}\(n)\u{201D} is already in VinylQ."
            }
        }
    }

    /// Adds a playlist, album or artist from a link or URI.
    @discardableResult
    func add(_ text: String) async throws -> SpotifyCollection {
        guard let link = SpotifyLink(text) else { throw AddError.notALink }
        if let existing = saved.first(where: { $0.uri == link.uri }) {
            throw AddError.alreadyAdded(existing.name)
        }
        let details = await Self.lookUp(link)
        let collection = SpotifyCollection(
            uri: link.uri,
            name: details?.title ?? "Spotify \(link.kind)",
            kind: link.kind,
            imageURL: details?.thumbnail
        )
        saved.append(collection)
        cache.setSaved(saved)
        Self.store(saved, key: Self.savedKey)
        onChange()
        return collection
    }

    func remove(_ collection: SpotifyCollection) {
        saved.removeAll { $0.uri == collection.uri }
        cache.setSaved(saved)
        Self.store(saved, key: Self.savedKey)
        onChange()
    }

    // MARK: oEmbed

    private struct Details {
        var title: String?
        var thumbnail: URL?
    }

    private static func lookUp(_ link: SpotifyLink) async -> Details? {
        var components = URLComponents(string: "https://open.spotify.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: link.webURL.absoluteString)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Details(
            title: (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            thumbnail: (json["thumbnail_url"] as? String).flatMap(URL.init(string:))
        )
    }

    // MARK: Persistence

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func store<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
