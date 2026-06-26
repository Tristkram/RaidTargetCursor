# Changelog

## 0.2.1

- Added PvP match-state rebuilds for battleground/arena transitions.
- Added multi-pass delayed rebuilds after entering world and roster updates.
- Added `/rtc frames` diagnostics for visible Blizzard raid/party frames.
- Added `/rtc events` diagnostics for recent addon events and rebuilds.
- Registered `/rtc` earlier during addon load.
- Made manual `/rtc rebuild` report when it is queued by combat lockdown.

## 0.2.0

- Added delayed/debounced rebuilds after login, world entry, and roster updates.
- Added Blizzard raid-frame layout hooks to reduce desync when frame layout addons move frames.
- Reduced full UI frame enumeration to a fallback path.
- Removed an unused local addon-name variable.
- Added README and MIT license for publishing.

## 0.1.7

- Initial local version with secure directional targeting buttons.
