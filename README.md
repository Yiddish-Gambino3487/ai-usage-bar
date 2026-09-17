# ai-usage-bar

A native macOS menubar app that shows how much of your AI coding tools' quota
you have used. One Swift executable, compiled locally with Apple's Command Line
Tools. No dependencies, no third-party binaries, nothing phones home except the
two usage endpoints the tools themselves already call.

    Claude 85%  Codex OK

Click it for the detail:

    Claude (Enterprise)
        $1,700.35 of $2,000.00 · $299.65 left
        Resets in 14 days (Sep 30, 8:00 PM)
    Codex (Business)
        Unlimited credits, no rate windows
    Refreshed 11:14 AM
    Refresh now
    Quit

## What it reads

| Provider | Source | Shown |
|----------|--------|-------|
| Claude | Claude Code's OAuth token in Keychain, and the usage endpoint behind Claude Code's `/usage` command | Monthly spend against the plan limit (Enterprise/Team), or the 5-hour and 7-day windows on plans that have them |
| Codex | `~/.codex/auth.json` and the Codex rate-limit endpoint | 5-hour and weekly windows when metered, `OK` when the plan is unmetered, `LIMITED` when OpenAI reports a cap reached |

The ChatGPT chat app is not shown. It exposes no usage data locally and OpenAI
has no consumer usage API.

The Claude reset date is computed as 00:00 UTC on the 1st of next month (the
desktop app shows this as 8:00 PM Eastern on the last day). The API does not
return it.

The app only reads tokens. It never refreshes, rotates, writes, or logs them.
If a token has expired the dropdown says so and asks you to open the owning
tool, which refreshes it.

## Requirements

- macOS 13 or later on Apple Silicon or Intel
- Apple Command Line Tools (`xcode-select --install`). Full Xcode is not needed.
- Claude Code logged in (for the Claude line), Codex CLI or app logged in with
  ChatGPT (for the Codex line). Either can be missing; the other still works.

## Install

    git clone https://github.com/Yiddish-Gambino3487/ai-usage-bar.git
    cd ai-usage-bar
    ./test.sh        # run the fixture tests
    ./build.sh       # compile to build/AIUsageBar
    ./install.sh     # start now and at every login

On first launch macOS asks whether AIUsageBar may read the
"Claude Code-credentials" Keychain item. Enter your Mac login password and
choose **Always Allow**. Every rebuild produces a new binary, so the prompt
comes back once per rebuild.

Useful commands:

    ./build/AIUsageBar --check   # print the numbers to Terminal, no menubar
    ./uninstall.sh               # stop the app and remove the LaunchAgent

If the menubar item does not appear on a MacBook screen, the menubar is full
and macOS hid it. It will show on an external display; on the built-in screen,
remove other menubar icons to make room.

## Layout

- `Sources/Model.swift`: parsing, date math, formatting. Pure functions, all tested.
- `Sources/Fetch.swift`: Keychain read, file read, HTTP. Never logs a token.
- `Sources/App.swift`: the menubar item and dropdown.
- `Sources/main.swift`: entry point and the `--check` mode.
- `Tests/main.swift`: fixture tests, run with `./test.sh`.

## Known gaps

- Claude 5-hour and 7-day window parsing is tested against fixtures only. The
  author's Enterprise account returns those fields as null, so the live shape
  has not been observed. If yours renders oddly, open an issue with the output
  of `--check`.
- Refresh interval is fixed at 5 minutes.
