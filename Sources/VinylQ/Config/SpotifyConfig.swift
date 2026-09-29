import Foundation

/// Signing in to Spotify.
///
/// This is the same Spotify developer app Cascade uses — its Client ID and its
/// registered redirect, `cascade://callback` — so signing in from here needs
/// nothing new on Spotify's side. The sign-in sheet catches that redirect
/// itself; nothing else has to own the `cascade` link scheme on this Mac.
///
/// Sign-in is Authorization Code + PKCE, the flow Spotify recommends for apps
/// that can't keep a secret: there is no client secret, and the Client ID
/// isn't one. The refresh token lives in the Keychain.
enum SpotifyConfig {

    static let clientID = "8194cad5a9a94a35a6296854680114f4"

    /// Must match a Redirect URI registered for the app in the Spotify dashboard.
    static let redirectURI = "cascade://callback"
    static let callbackScheme = "cascade"

    /// Read-only, apart from starting playback of what you pick.
    static let scopes = [
        "user-read-private",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-library-read",
        "user-read-recently-played",
        "user-read-playback-state",
        "user-read-currently-playing",
        "user-modify-playback-state",
    ]

    static let accounts = URL(string: "https://accounts.spotify.com")!
    static let api = URL(string: "https://api.spotify.com/v1")!
}
