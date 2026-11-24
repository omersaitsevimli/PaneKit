# Contributing to PaneKit

Thanks for helping improve PaneKit.

## Development setup

1. macOS 13+, Xcode 15+  
2. Clone the repo  
3. Prefer the release install path for Accessibility testing:

```bash
./scripts/build-release.sh
open ~/Applications/PaneKit.app
```

Grant Accessibility **only** to `~/Applications/PaneKit.app`.

Optional: `brew install xcodegen && xcodegen generate` if you need to regenerate the Xcode project.

## Pull requests

- Keep changes focused (one feature or fix per PR when possible)  
- Match existing Swift / AppKit style  
- Do not add Electron, SPM dependencies, or App Store sandbox unless discussed  
- Test snaps / Layouts / Accessibility on a real Mac before opening the PR  
- No Cursor / AI co-author trailers required in commits  

## Issues

- Bugs / features → [Issues](https://github.com/omersaitsevimli/PaneKit/issues) (use the templates)  
- Security → [Security](https://github.com/omersaitsevimli/PaneKit/security) (private reporting)  

## Docs

User-facing guides live in the [Wiki](https://github.com/omersaitsevimli/PaneKit/wiki) and `docs/wiki/`. Update both when behavior changes in a user-visible way.

## License

By contributing you agree your contributions are licensed under the [MIT License](LICENSE).
