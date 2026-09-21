# 07: Speaker Picker UI and Status Badging

**What to build:** An intuitive speaker selection interface in the player controls. A speaker icon opens a popover listing "This Mac" and all discovered Sonos rooms/groups with their online and volume status. The player view clearly indicates when audio is streaming to Sonos (e.g. "Playing to Living Room").

**Blocked by:** 06: PlayerService Output Target Routing and Handoff

**Status:** completed

- [x] Create `SpeakerPickerPopover` SwiftUI view presenting "This Mac" and the list of discovered Sonos rooms from `SonosDiscoveryService`.
- [x] Display checkmark for active output target, speaker volume level, and group composition badges (e.g. "Living Room (+ Kitchen)").
- [x] Add a refresh/re-scan button to trigger an immediate SSDP search.
- [x] Add a speaker route button (e.g. `airplayaudio` or `hifispeaker.2`) to `PlayerControlsView` in the header action buttons.
- [x] Add a visual status indicator in `PlayerControlsView` when Sonos is active (e.g. displaying the Sonos room name).
- [x] Manually verify UI interactions: selecting a room switches the route, updates checkmark, and reflects current volume.
