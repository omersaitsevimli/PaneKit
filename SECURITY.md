# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| Latest release on [Releases](https://github.com/omersaitsevimli/PaneKit/releases) | Yes |
| Older releases | Best effort |

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Prefer one of:

1. **GitHub private vulnerability reporting** — Security tab → Report a vulnerability  
2. Or contact the maintainer via GitHub (@omersaitsevimli)

Include:

- PaneKit version / commit  
- macOS version  
- Steps to reproduce  
- Impact (e.g. unexpected Accessibility use, local privilege, data exposure)

You should get an acknowledgement within a few days. We will coordinate a fix and, if needed, a GitHub Security Advisory before public disclosure.

## Scope notes

PaneKit is a **local** macOS menu-bar app. It requires **Accessibility** permission by design to move other apps’ windows. That is expected behavior, not a vulnerability by itself.

Reports about Gatekeeper / local signing (distribution outside the Mac App Store) are out of scope unless they enable remote code execution or unexpected privilege escalation.
