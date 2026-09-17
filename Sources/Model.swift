import Foundation

// Pure data types and functions. No network, no Keychain, no AppKit.
// Everything in this file is exercised by Tests/main.swift.

struct ClaudeSpend: Equatable, Sendable {
    let usedMinor: Int
    let limitMinor: Int
    let exponent: Int
    let currency: String

    var used: Double { Double(usedMinor) / divisor }
    var limit: Double { Double(limitMinor) / divisor }
    var remaining: Double { Double(max(limitMinor - usedMinor, 0)) / divisor }
    // Floor, not round, so 84.5% reads as 84% like the Claude desktop app.
    var percent: Int { limitMinor > 0 ? Int(Double(usedMinor) * 100 / Double(limitMinor)) : 0 }

    private var divisor: Double { pow(10.0, Double(exponent)) }
}

struct ClaudeWindow: Equatable, Sendable {
    let label: String
    let utilization: Double
    let resetsAt: Date?
}

struct ClaudeUsage: Equatable, Sendable {
    let plan: String?
    let spend: ClaudeSpend?          // Enterprise/Team monthly spend limit
    let windows: [ClaudeWindow]      // 5-hour and 7-day windows on plans that have them

    // Spend limit wins when present; otherwise the fuller rate window.
    var percent: Int? {
        if let spend { return spend.percent }
        return windows.map(\.utilization).max().map { Int($0) }
    }

    var shortStatus: String { percent.map { "\($0)%" } ?? "n/a" }
}

struct CodexWindow: Equatable, Sendable {
    let usedPercent: Double
    let windowSeconds: Int?
    let resetAt: Date?

    var label: String {
        guard let seconds = windowSeconds else { return "Window" }
        if seconds == 604_800 { return "Weekly" }
        return "\(seconds / 3600)h window"
    }
}

struct CodexUsage: Equatable, Sendable {
    let planType: String?
    let primary: CodexWindow?
    let secondary: CodexWindow?
    let unlimitedCredits: Bool
    let limitReached: Bool

    // The binding limit is whichever window is fuller. Nil when the plan has no metered windows.
    var percent: Int? {
        let values = [primary, secondary].compactMap { $0?.usedPercent }
        return values.max().map { Int($0) }
    }

    var shortStatus: String {
        if limitReached { return "LIMITED" }
        if let percent { return "\(percent)%" }
        return unlimitedCredits ? "OK" : "n/a"
    }
}

enum UsageError: LocalizedError, Equatable {
    case missingField(String)
    case credentialsUnavailable(String)
    case unauthorized(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .missingField(let field): return "response missing \(field)"
        case .credentialsUnavailable(let why): return why
        case .unauthorized(let who): return "\(who) token rejected; open \(who) to refresh it"
        case .http(let code): return "HTTP \(code)"
        }
    }
}

// MARK: - Parsing

private struct ClaudeResponse: Decodable {
    struct Money: Decodable { let amountMinor: Int; let currency: String; let exponent: Int }
    struct Spend: Decodable { let used: Money?; let limit: Money? }
    struct Window: Decodable { let utilization: Double?; let resetsAt: FlexibleDate? }
    let spend: Spend?
    let fiveHour: Window?
    let sevenDay: Window?
}

// resets_at has been seen as an ISO 8601 string; accept a unix timestamp too.
struct FlexibleDate: Decodable {
    let date: Date?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) { date = Date(timeIntervalSince1970: seconds); return }
        if let text = try? container.decode(String.self) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = iso.date(from: text) ?? ISO8601DateFormatter().date(from: text)
            return
        }
        date = nil
    }
}

func parseClaudeUsage(_ data: Data, plan: String? = nil) throws -> ClaudeUsage {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let response = try decoder.decode(ClaudeResponse.self, from: data)

    var spend: ClaudeSpend?
    if let used = response.spend?.used, let limit = response.spend?.limit {
        spend = ClaudeSpend(usedMinor: used.amountMinor, limitMinor: limit.amountMinor,
                            exponent: used.exponent, currency: used.currency)
    }

    func window(_ raw: ClaudeResponse.Window?, _ label: String) -> ClaudeWindow? {
        guard let raw, let utilization = raw.utilization else { return nil }
        return ClaudeWindow(label: label, utilization: utilization, resetsAt: raw.resetsAt?.date)
    }
    let windows = [window(response.fiveHour, "5-hour window"), window(response.sevenDay, "Weekly")].compactMap { $0 }

    guard spend != nil || !windows.isEmpty else { throw UsageError.missingField("spend limit or rate windows") }
    return ClaudeUsage(plan: plan, spend: spend, windows: windows)
}

private struct CodexResponse: Decodable {
    struct Window: Decodable {
        let usedPercent: Double?
        let limitWindowSeconds: Int?
        let resetAt: Double?
        let resetAfterSeconds: Double?
    }
    struct RateLimit: Decodable { let primaryWindow: Window?; let secondaryWindow: Window? }
    struct Credits: Decodable { let unlimited: Bool? }
    struct SpendControl: Decodable { let reached: Bool? }
    let planType: String?
    let rateLimit: RateLimit?
    let rateLimitReachedType: String?
    let credits: Credits?
    let spendControl: SpendControl?
}

func parseCodexUsage(_ data: Data, now: Date = Date()) throws -> CodexUsage {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let response = try decoder.decode(CodexResponse.self, from: data)

    func window(_ raw: CodexResponse.Window?) -> CodexWindow? {
        guard let raw, let used = raw.usedPercent else { return nil }
        var reset: Date?
        if let at = raw.resetAt { reset = Date(timeIntervalSince1970: at) }
        else if let after = raw.resetAfterSeconds { reset = now.addingTimeInterval(after) }
        return CodexWindow(usedPercent: used, windowSeconds: raw.limitWindowSeconds, resetAt: reset)
    }

    return CodexUsage(planType: response.planType,
                      primary: window(response.rateLimit?.primaryWindow),
                      secondary: window(response.rateLimit?.secondaryWindow),
                      unlimitedCredits: response.credits?.unlimited ?? false,
                      limitReached: response.rateLimitReachedType != nil || response.spendControl?.reached == true)
}

// MARK: - Dates

let utc = TimeZone(identifier: "UTC")!

// Claude's monthly spend limit resets at 00:00 UTC on the 1st (shown as 8 PM EDT on the last day).
func nextMonthStartUTC(after date: Date) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    return calendar.date(byAdding: .month, value: 1, to: thisMonth)!
}

func daysUntil(_ date: Date, from now: Date) -> Int {
    Int(ceil(date.timeIntervalSince(now) / 86_400))
}

// MARK: - Formatting

func formatMoney(_ amount: Double, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.locale = Locale(identifier: "en_US")
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f %@", amount, currency)
}

func formatReset(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = timeZone
    formatter.dateFormat = date.timeIntervalSince(now) < 86_400 ? "h:mm a" : "EEE h:mm a"
    return formatter.string(from: date)
}

func menubarText(claude: String, codex: String) -> String {
    "Claude \(claude)  Codex \(codex)"
}

func claudeLines(_ usage: ClaudeUsage, now: Date, timeZone: TimeZone = .current) -> [String] {
    var lines: [String] = []
    if let spend = usage.spend {
        let reset = nextMonthStartUTC(after: now)
        let resetFormatter = DateFormatter()
        resetFormatter.locale = Locale(identifier: "en_US")
        resetFormatter.timeZone = timeZone
        resetFormatter.dateFormat = "MMM d, h:mm a"
        lines.append("\(formatMoney(spend.used, currency: spend.currency)) of \(formatMoney(spend.limit, currency: spend.currency)) · \(formatMoney(spend.remaining, currency: spend.currency)) left")
        lines.append("Resets in \(daysUntil(reset, from: now)) days (\(resetFormatter.string(from: reset)))")
    }
    for window in usage.windows {
        var line = "\(window.label) \(Int(window.utilization))%"
        if let reset = window.resetsAt { line += " · resets \(formatReset(reset, now: now, timeZone: timeZone))" }
        lines.append(line)
    }
    return lines
}

func codexLines(_ usage: CodexUsage, now: Date, timeZone: TimeZone = .current) -> [String] {
    var lines: [String] = [usage.primary, usage.secondary].compactMap { window in
        guard let window else { return nil }
        var line = "\(window.label) \(Int(window.usedPercent))%"
        if let reset = window.resetAt { line += " · resets \(formatReset(reset, now: now, timeZone: timeZone))" }
        return line
    }
    if lines.isEmpty {
        lines.append(usage.unlimitedCredits ? "Unlimited credits, no rate windows" : "No rate windows reported")
    }
    if usage.limitReached { lines.append("Limit reached") }
    return lines
}
