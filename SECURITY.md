# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 2.x     | Yes                |
| 1.x     | No                 |

## Scope

This tool reads Claude Code session data (JSONL transcripts, cost information) and git repository state from the local filesystem. It makes **no network connections** and writes only to `~/.claude/` and `~/.cache/claude-code-statusline/`.

Security issues in scope:
- Arbitrary code execution via crafted input (JSON, git state, config files)
- Path traversal or unauthorized file access
- Information disclosure beyond what the status bar is designed to show
- Denial of service against the Claude Code render cycle

Out of scope:
- Issues requiring pre-existing shell access to the user's machine
- Issues in the Claude Code application itself

## Reporting a Vulnerability

Please report security vulnerabilities through [GitHub Security Advisories](https://github.com/ridjex/claude-code-statusline/security/advisories/new).

Do **not** file a public issue for security vulnerabilities.

We will acknowledge receipt within 48 hours and aim to provide a fix or mitigation within 7 days for critical issues.
