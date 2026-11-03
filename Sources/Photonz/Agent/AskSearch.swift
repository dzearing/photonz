import Foundation
import PhotonzCore
import Security

/// The search service Ask's reader searches with (`AskLookup`, "Looking things
/// up" in `docs/design/ask.md`): Brave Search's web API, with a key the person
/// makes on its site and pastes into Settings > Ask. The key is kept in the
/// login keychain, never in settings. A walk searches a stand-in on this Mac's
/// own loopback instead (`walkPort`), so no walk ever needs a key or the web.
enum AskSearch {

    /// A walk's search stand-in (`PlaytestSetup.askSearch`), or nil.
    @MainActor static var walkPort: Int?

    /// Where a search goes and the key it carries, or nil when searching is
    /// not set up.
    @MainActor static var service: (endpoint: URL, key: String)? {
        if let port = walkPort, let endpoint = AskLookup.walkEndpoint(port: port) { return (endpoint, "walk") }
        guard let endpoint = AskLookup.service, let key = AskSearchKey.read(), !key.isEmpty else { return nil }
        return (endpoint, key)
    }

    enum Trouble: Error { case failed }

    /// One search: an ephemeral session (no cookies, no cache), ten seconds.
    static func search(_ query: String, endpoint: URL, key: String) async -> Result<(results: [AskLookup.Result], address: String), Trouble> {
        guard let address = AskLookup.searchAddress(endpoint: endpoint, query: query) else { return .failure(.failed) }
        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return .failure(.failed) }
        return .success((AskLookup.results(fromSearch: data), address.absoluteString))
    }
}

/// The search key in the login keychain, one item for this app.
enum AskSearchKey {
    private static let service = "Photonz Ask search"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: AskLookup.keyAccount]
    }

    static func read() -> String? {
        var item: CFTypeRef?
        var asking = query
        asking[kSecReturnData as String] = true
        asking[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(asking as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Keeps the key, or forgets it when it is empty.
    static func write(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(query as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var adding = query
        adding[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(adding as CFDictionary, nil)
    }
}
