import Foundation

struct SkillsCatalogItem: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let name: String
    let source: String
    let installs: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, source, installs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        installs = try container.decodeIfPresent(Int.self, forKey: .installs) ?? 0
    }

    var pageURL: URL? {
        var components = URLComponents(string: "https://skills.sh")
        components?.path = "/\(id)"
        return components?.url
    }

    var installCountLabel: String {
        if installs == 1 { return "1 install" }
        return "\(installs.formatted(.number.notation(.compactName))) installs"
    }
}

enum SkillsCatalogError: LocalizedError, Equatable {
    case queryTooShort
    case invalidEndpoint
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .queryTooShort:
            "Enter at least two characters."
        case .invalidEndpoint:
            "SkillKit could not build the skills.sh search request."
        case .invalidResponse:
            "skills.sh returned an invalid response."
        case .requestFailed(let status):
            "skills.sh search failed with HTTP \(status)."
        }
    }
}

enum SkillsCatalogClient {
    private struct SearchResponse: Decodable {
        let skills: [SkillsCatalogItem]
    }

    static func search(
        _ rawQuery: String,
        limit: Int = 20,
        session: URLSession = .shared
    ) async throws -> [SkillsCatalogItem] {
        var request = try URLRequest(
            url: endpoint(for: rawQuery, limit: limit),
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SkillsCatalogError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SkillsCatalogError.requestFailed(response.statusCode)
        }
        return try decode(data)
    }

    static func endpoint(for rawQuery: String, limit: Int = 20) throws -> URL {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { throw SkillsCatalogError.queryTooShort }
        guard var components = URLComponents(string: "https://skills.sh/api/search") else {
            throw SkillsCatalogError.invalidEndpoint
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(min(200, max(1, limit)))),
        ]
        guard let url = components.url else { throw SkillsCatalogError.invalidEndpoint }
        return url
    }

    static func decode(_ data: Data) throws -> [SkillsCatalogItem] {
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.skills
            .filter {
                !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { lhs, rhs in
                if lhs.installs != rhs.installs { return lhs.installs > rhs.installs }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}
