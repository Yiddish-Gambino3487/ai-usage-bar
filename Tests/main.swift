import Foundation

// Fixture-driven checks for Sources/Model.swift. Run with ./test.sh.

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition { print("  ok   \(message)") } else { failures += 1; print("  FAIL \(message) (line \(line))") }
}
func check<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: Int = #line) {
    check(actual == expected, "\(message): got \(actual)", line: line)
}

let eastern = TimeZone(identifier: "America/New_York")!
// 2026-09-17 13:52:00 UTC (9:52 AM EDT)
let now = Date(timeIntervalSince1970: 1_789_998_720)

// MARK: Claude parsing (fixture shaped like the live response on 2026-09-17)
let claudeJSON = """
{"five_hour":null,"seven_day":null,
 "spend":{"used":{"amount_minor":169070,"currency":"USD","exponent":2},
          "limit":{"amount_minor":200000,"currency":"USD","exponent":2},
          "percent":85,"severity":"warning","enabled":true}}
""".data(using: .utf8)!
print("Claude parsing")
do {
    let usage = try parseClaudeUsage(claudeJSON, plan: "enterprise")
    check(usage.used, 1690.70, "used dollars")
    check(usage.limit, 2000.0, "limit dollars")
    check(usage.remaining, 309.30, "remaining dollars")
    check(usage.percent, 84, "percent floors like the desktop app")
    check(usage.plan, "enterprise", "plan carried through")
    let lines = claudeLines(usage, now: now, timeZone: eastern)
    check(lines[0], "$1,690.70 of $2,000.00 · $309.30 left", "money line")
    check(lines[1], "Resets in 14 days (Sep 30, 8:00 PM)", "reset line in Eastern")
} catch { check(false, "unexpected error \(error)") }

print("Claude with no spend block (consumer plan)")
let noSpend = #"{"five_hour":{"utilization":12.0},"spend":null}"#.data(using: .utf8)!
do { _ = try parseClaudeUsage(noSpend); check(false, "should have thrown") }
catch let error as UsageError { check(error, .missingField("spend"), "missing spend error") }
catch { check(false, "wrong error type \(error)") }

// MARK: Codex parsing
let codexJSON = """
{"plan_type":"plus",
 "rate_limit":{"allowed":true,
   "primary_window":{"used_percent":12.4,"limit_window_seconds":18000,"reset_at":1790005200},
   "secondary_window":{"used_percent":34.0,"limit_window_seconds":604800,"reset_after_seconds":300000}}}
""".data(using: .utf8)!
print("Codex parsing")
do {
    let usage = try parseCodexUsage(codexJSON, now: now)
    check(usage.planType, "plus", "plan type")
    check(usage.primary?.label, "5h window", "primary label")
    check(usage.secondary?.label, "Weekly", "secondary label")
    check(usage.percent, 34, "menubar percent is the fuller window")
    check(usage.secondary?.resetAt, now.addingTimeInterval(300_000), "reset_after_seconds fallback")
    let lines = codexLines(usage, now: now, timeZone: eastern)
    check(lines[0], "5h window 12% · resets 11:40 AM", "primary line")
    check(lines[1], "Weekly 34% · resets Sun 5:12 PM", "secondary line shows weekday when >24h out")
} catch { check(false, "unexpected error \(error)") }

print("Codex with no rate_limit")
do { _ = try parseCodexUsage(#"{"plan_type":"plus"}"#.data(using: .utf8)!, now: now); check(false, "should have thrown") }
catch let error as UsageError { check(error, .missingField("rate_limit"), "missing rate_limit error") }
catch { check(false, "wrong error type \(error)") }

// MARK: Dates and text
print("Dates and text")
let reset = nextMonthStartUTC(after: now)
check(reset, Date(timeIntervalSince1970: 1_791_158_400), "next month start is 2026-10-01 00:00 UTC")
check(daysUntil(reset, from: now), 14, "days until reset rounds up")
let decReset = nextMonthStartUTC(after: Date(timeIntervalSince1970: 1_797_000_000)) // 2026-12-11
check(Calendar(identifier: .gregorian).dateComponents(in: utc, from: decReset).year, 2027, "December rolls into next year")
check(menubarText(claude: 84, codex: nil), "Claude 84%  Codex n/a", "menubar text with a missing provider")
check(formatMoney(0, currency: "USD"), "$0.00", "zero dollars")

print(failures == 0 ? "\nAll checks passed" : "\n\(failures) check(s) FAILED")
exit(failures == 0 ? 0 : 1)
