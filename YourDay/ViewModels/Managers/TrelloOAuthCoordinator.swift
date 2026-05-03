//
//  TrelloOAuthCoordinator.swift
//  YourDay
//

import AuthenticationServices
import Foundation
import UIKit

enum TrelloOAuthError: LocalizedError {
    case missingAuthorizeURL
    case userCancelled
    case missingToken
    case trelloDenied(String?)

    var errorDescription: String? {
        switch self {
        case .missingAuthorizeURL: return "Could not build Trello sign-in URL."
        case .userCancelled: return "Sign in was cancelled."
        case .missingToken: return "Trello did not return a token. Check allowed origins and return URL in your Power-Up settings."
        case .trelloDenied(let msg): return msg ?? "Trello denied access."
        }
    }
}

final class TrelloOAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = TrelloOAuthCoordinator()

    private var session: ASWebAuthenticationSession?

    private override init() {
        super.init()
    }

    /// Reserved for deep-link style resumes; token flow uses `ASWebAuthenticationSession` completion only.
    @discardableResult
    func resumeIfOpenURL(_ url: URL) -> Bool {
        _ = url
        return false
    }

    func start(presentationAnchor: ASPresentationAnchor, completion: @escaping (Result<String, Error>) -> Void) {
        session?.cancel()
        guard let url = TrelloOAuthConfig.makeAuthorizeURL() else {
            completion(.failure(TrelloOAuthError.missingAuthorizeURL))
            return
        }

        let callback = ASWebAuthenticationSession.Callback.customScheme(TrelloOAuthConfig.callbackScheme)
        let authSession = ASWebAuthenticationSession(url: url, callback: callback) { [weak self] callbackURL, error in
            self?.session = nil
            if let error {
                let ns = error as NSError
                if ns.domain == ASWebAuthenticationSessionError.errorDomain,
                   ns.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
                    completion(.failure(TrelloOAuthError.userCancelled))
                } else {
                    completion(.failure(error))
                }
                return
            }
            guard let callbackURL else {
                completion(.failure(TrelloOAuthError.missingToken))
                return
            }
            if let denied = Self.parseDenial(from: callbackURL) {
                completion(.failure(TrelloOAuthError.trelloDenied(denied)))
                return
            }
            guard let token = Self.parseToken(from: callbackURL) else {
                completion(.failure(TrelloOAuthError.missingToken))
                return
            }
            completion(.success(token))
        }
        authSession.presentationContextProvider = self
        authSession.prefersEphemeralWebBrowserSession = false
        session = authSession
        if !authSession.start() {
            session = nil
            completion(.failure(TrelloOAuthError.missingAuthorizeURL))
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) { return window }
            if let window = scene.windows.first { return window }
        }
        preconditionFailure("TrelloOAuthCoordinator: no UIWindow for presentation anchor")
    }

    private static func parseToken(from url: URL) -> String? {
        if let fragment = url.fragment {
            if let token = value(named: "token", in: fragment) { return token }
        }
        if let query = url.query {
            if let token = value(named: "token", in: query) { return token }
        }
        return nil
    }

    private static func parseDenial(from url: URL) -> String? {
        if let fragment = url.fragment, let err = value(named: "error", in: fragment) { return err }
        if let query = url.query, let err = value(named: "error", in: query) { return err }
        return nil
    }

    private static func value(named name: String, in parameterString: String) -> String? {
        for pair in parameterString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, parts[0] == name else { continue }
            return parts[1].removingPercentEncoding ?? parts[1]
        }
        return nil
    }
}
