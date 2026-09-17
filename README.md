# ai-usage-bar

Native macOS menubar app showing how much of each AI tool's quota is used.
No dependencies, no third-party binaries: one Swift executable compiled with the
Apple Command Line Tools.

- Claude: monthly spend against the plan limit, read from the same Keychain
  token and usage endpoint Claude Code's `/usage` uses.
- Codex: 5-hour and weekly rate windows, read from `~/.codex/auth.json`.
- ChatGPT chat app: not shown. It exposes no usage data locally and OpenAI has
  no consumer usage API.

The app only reads tokens. It never refreshes, rotates, writes, or logs them.

## Use

    ./test.sh                  # run fixture tests
    ./build.sh                 # compile to build/AIUsageBar
    ./build/AIUsageBar --check # print the numbers to Terminal
    ./install.sh               # start now and at every login

First run: macOS asks whether AIUsageBar may read the "Claude Code-credentials"
Keychain item. Choose Always Allow. Every rebuild produces a new binary, so the
prompt returns once per rebuild.

Layout: `Sources/Model.swift` is pure parsing and formatting (tested),
`Sources/Fetch.swift` is Keychain and HTTP, `Sources/App.swift` is the menubar UI.
