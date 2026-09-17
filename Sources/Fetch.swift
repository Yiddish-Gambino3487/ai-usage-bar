import Foundation
import Security

// Reads tokens other tools already keep on this Mac and calls the same usage
// endpoints those tools call. Read-only: this file never refreshes, rotates,
// writes, or logs a token.

private let userAgent = "ai-usage-bar/1.0"

func attempt<T: Sendable>(_ operation: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await operation()) } catch { return .failure(error) }
}

private func send(_ request: URLRequest, owner: String) async throws -> Data {
    var request = request
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 20
    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    if code == 401 || code == 403 { throw UsageError.unauthorized(owner) }
    guard (200..<300).contains(code) else { throw UsageError.http(code) }
    return data
}

// MARK: - Claude

struct ClaudeCredentials { let accessToken: String; let plan: String? }

func readClaudeCredentials() throws -> ClaudeCredentials {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
        throw UsageError.credentialsUnavailable("Keychain item 'Claude Code-credentials' unreadable (status \(status)); is Claude Code logged in?")
    }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = root["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String else {
        throw UsageError.credentialsUnavailable("Claude Code credentials have no OAuth access token")
    }
    return ClaudeCredentials(accessToken: token, plan: oauth["subscriptionType"] as? String)
}

func fetchClaudeUsage() async throws -> ClaudeUsage {
    let credentials = try readClaudeCredentials()
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    let data = try await send(request, owner: "Claude Code")
    return try parseClaudeUsage(data, plan: credentials.plan)
}

// MARK: - Codex

struct CodexCredentials { let accessToken: String; let accountId: String }

func readCodexCredentials() throws -> CodexCredentials {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    guard let data = try? Data(contentsOf: url) else {
        throw UsageError.credentialsUnavailable("~/.codex/auth.json not found; is Codex logged in?")
    }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tokens = root["tokens"] as? [String: Any],
          let token = tokens["access_token"] as? String else {
        throw UsageError.credentialsUnavailable("Codex is not logged in with ChatGPT (API-key mode has no quota)")
    }
    guard let accountId = (tokens["account_id"] as? String) ?? chatGPTAccountId(fromJWT: token) else {
        throw UsageError.credentialsUnavailable("Codex credentials have no account id")
    }
    return CodexCredentials(accessToken: token, accountId: accountId)
}

// The account id also lives inside the JWT payload; used only if auth.json lacks it.
private func chatGPTAccountId(fromJWT token: String) -> String? {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while payload.count % 4 != 0 { payload += "=" }
    guard let data = Data(base64Encoded: payload),
          let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let auth = claims["https://api.openai.com/auth"] as? [String: Any] else { return nil }
    return auth["chatgpt_account_id"] as? String
}

func fetchCodexUsage() async throws -> CodexUsage {
    let credentials = try readCodexCredentials()
    var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue(credentials.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
    let data = try await send(request, owner: "Codex")
    return try parseCodexUsage(data)
}
