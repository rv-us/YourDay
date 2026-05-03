//
//  TrelloOAuthConfig.swift
//  YourDay
//
//  Public API key for Trello `/1/authorize` (token flow). Add matching return URL to Power-Up allowed origins.
//

import Foundation

enum TrelloOAuthConfig {
    /// Trello Power-Up API key (non-secret; shipped with the app).
    static let apiKey = "cc92f69379e8c3370abfe82701a2ba20"

    static let callbackScheme = "yourday-trello"

    /// Must match `CFBundleURLTypes` and Trello Power-Up allowed origins / return URL.
    static var redirectURL: URL {
        URL(string: "\(callbackScheme)://oauth-callback")!
    }

    static func makeAuthorizeURL() -> URL? {
        var components = URLComponents(string: "https://trello.com/1/authorize")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "name", value: "YourDay"),
            URLQueryItem(name: "expiration", value: "30days"),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope", value: "read,write"),
            URLQueryItem(name: "return_url", value: redirectURL.absoluteString)
        ]
        return components?.url
    }
}
