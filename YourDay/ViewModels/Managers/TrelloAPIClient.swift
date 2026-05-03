//
//  TrelloAPIClient.swift
//  YourDay
//

import Foundation

struct TrelloMemberDTO: Decodable {
    let id: String
    let fullName: String?
    let username: String?
}

struct TrelloBoardAPIItem: Decodable, Identifiable {
    let id: String
    let name: String?
    let closed: Bool?
}

struct TrelloCardAPIItem: Decodable, Identifiable {
    let id: String
    let name: String?
    let desc: String?
    let due: Date?
    let dueComplete: Bool?
    let closed: Bool?
    let idBoard: String?
    let idList: String?
    let idMembers: [String]?
    let dateLastActivity: Date?
}

enum TrelloAPIError: LocalizedError {
    case invalidURL
    case http(Int, String?)
    case decode(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Trello request URL."
        case .http(let code, let body): return "Trello error (\(code)): \(body ?? "")"
        case .decode(let err): return "Could not read Trello response: \(err.localizedDescription)"
        }
    }
}

enum TrelloAPIClient {
    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso8601WithFractionalSeconds.date(from: string) ?? iso8601.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Trello date: \(string)")
        }
        return d
    }()
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso8601 = ISO8601DateFormatter()

    static func memberMe(token: String) async throws -> TrelloMemberDTO {
        let data = try await getData(path: "members/me", token: token, query: [URLQueryItem(name: "fields", value: "id,fullName,username")])
        do {
            return try jsonDecoder.decode(TrelloMemberDTO.self, from: data)
        } catch {
            throw TrelloAPIError.decode(error)
        }
    }

    static func memberBoards(token: String) async throws -> [TrelloBoardAPIItem] {
        let data = try await getData(path: "members/me/boards", token: token, query: [URLQueryItem(name: "fields", value: "id,name,closed")])
        do {
            return try jsonDecoder.decode([TrelloBoardAPIItem].self, from: data)
        } catch {
            throw TrelloAPIError.decode(error)
        }
    }

    static func openCards(boardId: String, token: String) async throws -> [TrelloCardAPIItem] {
        let data = try await getData(
            path: "boards/\(boardId)/cards",
            token: token,
            query: [
                URLQueryItem(name: "filter", value: "open"),
                URLQueryItem(name: "fields", value: "id,name,desc,due,dueComplete,closed,idBoard,idList,idMembers,dateLastActivity")
            ]
        )
        do {
            return try jsonDecoder.decode([TrelloCardAPIItem].self, from: data)
        } catch {
            throw TrelloAPIError.decode(error)
        }
    }

    static func updateCardDueComplete(cardId: String, isComplete: Bool, token: String) async throws {
        _ = try await requestData(
            path: "cards/\(cardId)",
            method: "PUT",
            token: token,
            query: [URLQueryItem(name: "dueComplete", value: isComplete ? "true" : "false")]
        )
    }

    static func updateCard(cardId: String, name: String, desc: String, due: Date, token: String) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        _ = try await requestData(
            path: "cards/\(cardId)",
            method: "PUT",
            token: token,
            query: [
                URLQueryItem(name: "name", value: name),
                URLQueryItem(name: "desc", value: desc),
                URLQueryItem(name: "due", value: formatter.string(from: due))
            ]
        )
    }

    static func deleteCard(cardId: String, token: String) async throws {
        _ = try await requestData(path: "cards/\(cardId)", method: "DELETE", token: token, query: [])
    }

    private static func getData(path: String, token: String, query: [URLQueryItem]) async throws -> Data {
        try await requestData(path: path, method: "GET", token: token, query: query)
    }

    private static func requestData(path: String, method: String, token: String, query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(string: "https://api.trello.com/1/\(path)")
        var items = query
        items.append(URLQueryItem(name: "key", value: TrelloOAuthConfig.apiKey))
        items.append(URLQueryItem(name: "token", value: token))
        components?.queryItems = items
        guard let url = components?.url else { throw TrelloAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TrelloAPIError.http(-1, nil) }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            if http.statusCode == 401 || http.statusCode == 403 {
                ConnectionReauthorizationNotifier.requestTrello(reason: body)
            }
            throw TrelloAPIError.http(http.statusCode, body)
        }
        return data
    }
}
