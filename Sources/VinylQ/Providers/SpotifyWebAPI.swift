import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import OSLog

/// Your Spotify library, through the Web API — the same way Cascade does it.
///
/// Signing in (the Spotify consent sheet, once) lets the app list everything:
/// your playlists, Liked Songs and what you've played recently. Playback and
/// the needle still go through the Spotify app over Apple Events, which works
/// on Free and Premium alike.
///
/// Spotify's 2026 rules shape two details: playlist *contents* are only served
/// for playlists you own or collaborate on, so ones you merely follow are
/// listed but play as a whole; and pages are capped at 50 items.
@MainActor
final class SpotifyWebAPI: NSObject, ObservableObject {

    // MARK: Published state

    @Published private(set) var isConnected = false
    @Published private(set) var isWorking = false
    @Published private(set) var status: String?
    @Published private(set) var displayName: String?
    @Published private(set) var playlistCount = 0

    /// Background-readable mirror, shared with `SpotifyProvider`.
    let cache: SpotifyCache
    /// Called whenever the library changes, so the browser can redraw.
    var onLibraryChange: () -> Void = {}


    private static let log = Logger(subsystem: "app.wax.deck", category: "spotify")

    private var refreshToken: String? {
        get { Keychain.get("spotify.refresh") }
        set { Keychain.set(newValue, for: "spotify.refresh") }
    }

    private var accessToken: String?
    private var accessTokenExpiry: Date = .distantPast
    private var refreshTask: Task<String?, Never>?
    private var session: ASWebAuthenticationSession?
    private var lastLibraryLoad: Date = .distantPast

    init(cache: SpotifyCache) {
        self.cache = cache
        super.init()
        isConnected = refreshToken != nil
        displayName = UserDefaults.standard.string(forKey: "spotify.displayName")
        if let userID = UserDefaults.standard.string(forKey: "spotify.userID") {
            cache.setUserID(userID)
        }
    }

    // MARK: Signing in

    /// Shows Spotify's sign-in sheet. Returns whether you ended up signed in.
    @discardableResult
    func connect() async -> Bool {
        isWorking = true
        status = "Waiting for Spotify…"
        defer { isWorking = false }

        let verifier = Self.randomToken(bytes: 64)
        let state = String(Self.randomToken(bytes: 18).prefix(24))
        var components = URLComponents(url: SpotifyConfig.accounts.appendingPathComponent("authorize"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: SpotifyConfig.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: Self.challenge(for: verifier)),
            .init(name: "state", value: state),
            .init(name: "scope", value: SpotifyConfig.scopes.joined(separator: " "))
        ]

        guard let url = components.url, let callback = await presentSignIn(url: url) else {
            status = "Sign-in cancelled."
            return false
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value,
              items.first(where: { $0.name == "state" })?.value == state else {
            let reason = items.first(where: { $0.name == "error" })?.value
            status = reason == "access_denied" ? "Sign-in cancelled." : "Spotify didn't finish signing in."
            return false
        }

        let exchanged = await exchange([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": verifier
        ])
        guard exchanged else {
            status = "Spotify didn't accept the sign-in. Try again in a moment."
            return false
        }
        isConnected = true
        status = nil
        await loadLibrary(force: true)
        return true
    }

    func disconnect() {
        refreshToken = nil
        accessToken = nil
        accessTokenExpiry = .distantPast
        cache.clearWebLibrary()
        cache.setUserID(nil)
        UserDefaults.standard.removeObject(forKey: "spotify.userID")
        UserDefaults.standard.removeObject(forKey: "spotify.displayName")
        displayName = nil
        playlistCount = 0
        isConnected = false
        status = nil
        onLibraryChange()
    }

    private func presentSignIn(url: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: SpotifyConfig.callbackScheme
            ) { callback, _ in
                continuation.resume(returning: callback)
            }
            session.presentationContextProvider = self
            // Reuse the browser's Spotify login, so it's usually just "Agree".
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: Tokens

    /// A token good for at least another minute, refreshed if need be.
    /// Concurrent callers share one refresh.
    private func validToken() async -> String? {
        if let accessToken, accessTokenExpiry.timeIntervalSinceNow > 60 { return accessToken }
        if let refreshTask { return await refreshTask.value }
        guard let refreshToken else { return nil }

        let task = Task<String?, Never> {
            let ok = await self.exchange([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": SpotifyConfig.clientID
            ])
            return ok ? self.accessToken : nil
        }
        refreshTask = task
        let token = await task.value
        refreshTask = nil
        return token
    }

    private func exchange(_ fields: [String: String]) async -> Bool {
        var request = URLRequest(url: SpotifyConfig.accounts.appendingPathComponent("api/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { "\(Self.formEncode($0.key))=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        guard (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            let body = String(data: data, encoding: .utf8) ?? ""
            Self.log.error("token exchange failed (\(http.statusCode)): \(body.prefix(200), privacy: .public)")
            // Only a revoked grant means signed out; a bad minute isn't a bad account.
            if body.contains("invalid_grant") || body.contains("invalid_client") {
                refreshToken = nil
                isConnected = false
            }
            return false
        }
        accessToken = token
        let lifetime = (json["expires_in"] as? Double) ?? Double(json["expires_in"] as? Int ?? 3600)
        accessTokenExpiry = Date().addingTimeInterval(lifetime)
        // Spotify rotates the refresh token on PKCE refreshes — keep the newest.
        if let fresh = json["refresh_token"] as? String { refreshToken = fresh }
        return true
    }

    // MARK: Library

    /// Profile, playlists, Liked Songs and recent plays. Skipped if it ran
    /// in the last couple of minutes, unless `force`.
    func loadLibrary(force: Bool = false) async {
        guard isConnected else { return }
        guard force || Date().timeIntervalSince(lastLibraryLoad) > 120 else { return }
        lastLibraryLoad = Date()

        if let me = await getJSON("me") {
            let userID = me["id"] as? String
            let name = (me["display_name"] as? String) ?? userID
            cache.setUserID(userID)
            UserDefaults.standard.set(userID, forKey: "spotify.userID")
            UserDefaults.standard.set(name, forKey: "spotify.displayName")
            displayName = name
        }
        let userID = cache.userID

        var lists: [Playlist] = []

        // Liked Songs: just the count for now; the songs load when opened.
        if let liked = await getJSON("me/tracks", query: ["limit": "1"]) {
            let total = liked["total"] as? Int ?? 0
            if total > 0 {
                lists.append(Playlist(id: SpotifyProvider.likedID, name: "Liked Songs", source: .spotify, trackCount: total))
            }
        }

        let items = await getPaged("me/playlists", query: ["limit": "50"], max: 300)
        for item in items {
            guard let id = item["id"] as? String, let name = item["name"] as? String else { continue }
            // `items` since the 2026 API; `tracks` before it.
            let counts = (item["items"] as? [String: Any]) ?? (item["tracks"] as? [String: Any])
            let total = counts?["total"] as? Int ?? 0
            let ownerID = (item["owner"] as? [String: Any])?["id"] as? String
            let collaborative = item["collaborative"] as? Bool ?? false
            // Spotify only lists the songs of playlists you own or share.
            let browsable = collaborative || (ownerID != nil && ownerID == userID)
            let image = Self.smallestImage(item["images"])
            lists.append(Playlist(id: id, name: name, source: .spotify, trackCount: total,
                                  isCollection: !browsable, artworkURL: image))
        }
        cache.setPlaylists(lists)
        playlistCount = lists.count

        // Recently played, as Spotify remembers it (phone and all).
        if let history = await getJSON("me/player/recently-played", query: ["limit": "50"]),
           let entries = history["items"] as? [[String: Any]] {
            var seen = Set<String>()
            let tracks = entries.compactMap { ($0["track"] as? [String: Any]).flatMap(Self.track) }
                .filter { seen.insert($0.id).inserted }
            cache.setWebRecent(tracks)
        }

        Self.log.notice("library loaded: \(lists.count) playlists")
        onLibraryChange()
    }

    func cachedTracks(for playlistID: String) -> [Track] { cache.tracks(for: playlistID) }

    /// Loads the songs in a playlist (or Liked Songs) into the cache.
    func loadTracks(for playlistID: String) async {
        guard !cache.hasTracks(for: playlistID) else { return }
        let entries: [[String: Any]]
        if playlistID == SpotifyProvider.likedID {
            entries = await getPaged("me/tracks", query: ["limit": "50"], max: 500)
        } else {
            entries = await getPaged("playlists/\(playlistID)/items",
                                     query: ["limit": "50", "additional_types": "track"], max: 500)
        }
        // Liked Songs wrap each song as `track`; playlists as `item` since 2026.
        let tracks = entries.compactMap { entry -> Track? in
            let raw = (entry["item"] as? [String: Any]) ?? (entry["track"] as? [String: Any])
            return raw.flatMap(Self.track)
        }
        cache.setTracks(tracks, for: playlistID)
    }

    // MARK: Requests

    private func getJSON(_ path: String, query: [String: String] = [:]) async -> [String: Any]? {
        var components = URLComponents(url: SpotifyConfig.api.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { return nil }
        return await getJSON(url: url)
    }

    private func getJSON(url: URL, attempt: Int = 0) async -> [String: Any]? {
        guard let token = await validToken() else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }

        switch http.statusCode {
        case 200...299:
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        case 401 where attempt == 0:
            // The token died early: invalidate before asking again.
            accessToken = nil
            accessTokenExpiry = .distantPast
            return await getJSON(url: url, attempt: 1)
        case 429 where attempt == 0:
            let wait = min(Double(http.value(forHTTPHeaderField: "Retry-After") ?? "2") ?? 2, 10)
            try? await Task.sleep(nanoseconds: UInt64((wait + 0.3) * 1_000_000_000))
            return await getJSON(url: url, attempt: 1)
        default:
            Self.log.error("GET \(url.path, privacy: .public) → \(http.statusCode): \(String(decoding: data.prefix(200), as: UTF8.self), privacy: .public)")
            return nil
        }
    }

    /// Follows `next` links until `max` items are collected.
    private func getPaged(_ path: String, query: [String: String], max: Int) async -> [[String: Any]] {
        guard var page = await getJSON(path, query: query) else { return [] }
        var collected: [[String: Any]] = page["items"] as? [[String: Any]] ?? []
        while collected.count < max, let next = page["next"] as? String, let url = URL(string: next),
              let fresh = await getJSON(url: url) {
            let items = fresh["items"] as? [[String: Any]] ?? []
            if items.isEmpty { break }
            collected += items
            page = fresh
        }
        return Array(collected.prefix(max))
    }

    // MARK: Parsing

    private static func track(_ t: [String: Any]) -> Track? {
        guard let uri = t["uri"] as? String, uri.hasPrefix("spotify:track:"),
              let name = t["name"] as? String else { return nil }
        let artists = (t["artists"] as? [[String: Any]])?
            .compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
        let album = t["album"] as? [String: Any]
        return Track(id: uri, title: name, artist: artists,
                     album: album?["name"] as? String ?? "",
                     duration: ((t["duration_ms"] as? Double) ?? 0) / 1000,
                     artworkURL: smallestImage(album?["images"]))
    }

    /// Images come largest first; rows only need a thumbnail.
    private static func smallestImage(_ value: Any?) -> URL? {
        guard let images = value as? [[String: Any]] else { return nil }
        let urls = images.compactMap { $0["url"] as? String }
        return (urls.dropFirst().first ?? urls.first).flatMap(URL.init(string:))
    }

    // MARK: PKCE helpers

    private static func randomToken(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

extension SpotifyWebAPI: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) ?? NSWindow()
        }
    }
}
