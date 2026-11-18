# Contributing to Dumpling

Thanks for your interest in contributing to Dumpling! Contributions of all kinds—bug reports, feature suggestions, documentation improvements, and pull requests—are welcome.

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md) in all interactions within this project.

## Development Setup

### Prerequisites

- macOS 13+
- Swift 5.9+ (Xcode or Xcode Command Line Tools)
- Node.js

### Running Locally

1. Fork and clone the repository:

   ```bash
   git clone https://github.com/<your-username>/dumpling.git
   cd dumpling
   ```

2. Start the daemon and HUD app:

   ```bash
   ./start.sh
   ```

3. *(Optional)* Build the Swift HUD app directly during development:

   ```bash
   cd hud-app
   swift build
   ```

4. *(Optional)* Register Claude Code hooks locally to test hook events:

   ```bash
   node scripts/install-hooks.mjs
   ```

## Project Layout

- `hud-app/` — Native macOS SwiftUI floating panel & menu bar app (`Sources/Dumpling/`)
- `daemon/server.mjs` — Local HTTP/SSE daemon aggregating Claude Code hooks and Antigravity sessions
- `hooks/claude-hook.mjs` — Claude Code hook bridge forwarding events to the daemon
- `scripts/install-hooks.mjs` — Helper to register hooks in `~/.claude/settings.json`
- `start.sh` — Launches the daemon and builds/runs the HUD app

## Reporting Bugs & Requesting Features

- **Bugs**: Open an issue using the [Bug Report](.github/ISSUE_TEMPLATE/bug_report.md) template. Include your macOS version, Swift/Node versions, and steps to reproduce.
- **Features**: Open an issue using the [Feature Request](.github/ISSUE_TEMPLATE/feature_request.md) template to discuss the idea before writing large changes.

## Pull Request Process

1. Create a new branch from `main` for your change (for example, `fix/hud-focus` or `feat/new-status-badge`).
2. Keep changes focused and small so they are easy to review.
3. Verify your changes locally:
   - Run `swift build` inside `hud-app/` if you modified Swift code.
   - Run `./start.sh` and test the HUD and daemon together.
4. Open a Pull Request against `main` using the PR template and describe what changed and how you tested it.

## License

By contributing to Dumpling, you agree that your contributions will be licensed under the [MIT License](LICENSE).
