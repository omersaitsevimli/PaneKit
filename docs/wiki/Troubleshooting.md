# Troubleshooting

## Windows do not move

- Menu shows **Accessibility: OK ✓**?  
- Only `~/Applications/PaneKit.app` is enabled  
- Quit and reopen PaneKit  
- Check the ignore-app list  

## Accessibility prompt on every rebuild

Use `./scripts/build-release.sh` instead of DerivedData Run.

## Gap “flickers” or sizes jump

- Window gap setting  
- Size-cycle on repeated shortcuts (intentional)  
- Update to latest release (shrink-nudge flicker fixed)  

## Gatekeeper warning

Right-click → **Open**. Locally signed, not notarized for the App Store.

## Layouts has no candidates

Accessibility off, ignored apps, or minimized windows.

## Related

- [Accessibility](Accessibility) · [Getting Started](Getting-Started)
