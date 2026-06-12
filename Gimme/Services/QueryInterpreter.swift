import Foundation

/// The result of turning what the user *typed* into what we *search*.
/// `displayLabel` powers the transparent "Zyns → convenience store" caption.
struct InterpretedQuery: Equatable, Sendable {
    let searchText: String
    let displayLabel: String
}

protocol QueryInterpreting: Sendable {
    /// Never throws: interpretation must not be able to break the search flow.
    func interpret(_ raw: String) async -> InterpretedQuery
}

/// On-device interpreter. Maps known product/slang queries to the category of
/// place most likely to carry them; anything unknown passes through verbatim —
/// Places Text Search already handles natural language well.
struct RuleBasedInterpreter: QueryInterpreting {

    static let mappings: [String: String] = [
        "zyn": "convenience store",
        "zyns": "convenience store",
        "nicotine pouches": "convenience store",
        "cigarettes": "convenience store",
        "smokes": "convenience store",
        "vape": "vape shop",
        "juul": "vape shop",
        "gas": "gas station",
        "fuel": "gas station",
        "petrol": "gas station",
        "ice cream": "ice cream shop",
        "coffee": "coffee shop",
        "cold brew": "coffee shop",
        "latte": "coffee shop",
        "atm": "atm",
        "cash": "atm",
        "beer": "liquor store",
        "liquor": "liquor store",
        "wine": "liquor store",
        "advil": "pharmacy",
        "tylenol": "pharmacy",
        "ibuprofen": "pharmacy",
        "band aids": "pharmacy",
        "groceries": "grocery store",
        "weed": "cannabis dispensary",
    ]

    func interpret(_ raw: String) async -> InterpretedQuery {
        let normalized = Self.normalize(raw)
        if let mapped = Self.mappings[normalized] {
            return InterpretedQuery(searchText: mapped, displayLabel: mapped)
        }
        return InterpretedQuery(searchText: normalized, displayLabel: normalized)
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .joined(separator: " ")
    }
}

/// Optional Claude-backed interpreter. Talks to the Gimme proxy (server/), never
/// to Anthropic directly — no LLM API key ships in the app (spec §4.1).
/// Hard 1.5 s budget; any failure silently falls back to the rule-based
/// interpreter. The user should never be able to tell an LLM was involved.
struct ClaudeProxyInterpreter: QueryInterpreting {

    let endpoint: URL
    let authToken: String?
    var session: URLSession = .shared
    var timeout: TimeInterval = 1.5

    private struct RequestBody: Encodable {
        let query: String
    }

    private struct ResponseBody: Decodable {
        let searchText: String
        let label: String
    }

    func interpret(_ raw: String) async -> InterpretedQuery {
        let fallback = RuleBasedInterpreter()
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let authToken {
                request.setValue(authToken, forHTTPHeaderField: "X-Gimme-Auth")
            }
            request.httpBody = try JSONEncoder().encode(RequestBody(query: RuleBasedInterpreter.normalize(raw)))

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return await fallback.interpret(raw)
            }
            let reply = try JSONDecoder().decode(ResponseBody.self, from: data)
            let searchText = reply.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !searchText.isEmpty else {
                return await fallback.interpret(raw)
            }
            let label = reply.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return InterpretedQuery(
                searchText: searchText,
                displayLabel: label.isEmpty ? searchText : label
            )
        } catch {
            return await fallback.interpret(raw)
        }
    }
}
