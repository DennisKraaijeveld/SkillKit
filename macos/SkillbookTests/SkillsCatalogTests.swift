import Foundation
import Testing
@testable import Skillbook

@Suite("skills.sh catalog")
struct SkillsCatalogTests {
    @Test("Search endpoint trims and encodes the query")
    func searchEndpoint() throws {
        let url = try SkillsCatalogClient.endpoint(for: "  react native  ", limit: 999)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)

        #expect(components.scheme == "https")
        #expect(components.host == "skills.sh")
        #expect(components.path == "/api/search")
        #expect(queryItems.first { $0.name == "q" }?.value == "react native")
        #expect(queryItems.first { $0.name == "limit" }?.value == "200")
    }

    @Test("Search endpoint rejects short queries")
    func shortSearchQuery() {
        #expect(throws: SkillsCatalogError.queryTooShort) {
            try SkillsCatalogClient.endpoint(for: " x ")
        }
    }

    @Test("Catalog responses filter invalid rows and sort by installs")
    func decodeCatalogResponse() throws {
        let data = try #require(
            """
            {
              "skills": [
                {
                  "id": "acme/skills/lower",
                  "skillId": "lower",
                  "name": "Lower",
                  "source": "acme/skills",
                  "installs": 12
                },
                {
                  "id": "acme/skills/popular",
                  "skillId": "popular",
                  "name": "Popular",
                  "source": "acme/skills",
                  "installs": 2400
                },
                {
                  "id": "acme/skills/invalid",
                  "name": "Invalid",
                  "source": ""
                }
              ]
            }
            """.data(using: .utf8)
        )

        let skills = try SkillsCatalogClient.decode(data)

        #expect(skills.map(\.name) == ["Popular", "Lower"])
        #expect(skills.first?.pageURL?.absoluteString == "https://skills.sh/acme/skills/popular")
    }
}
