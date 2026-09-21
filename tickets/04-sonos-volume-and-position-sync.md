# 04: Sonos Volume Control and Position Synchronization

**What to build:** Bi-directional volume control and playback position synchronization with Sonos. Adjusting volume in the app updates Sonos, and adjustments made via physical speaker buttons or the Sonos mobile app reflect back in the menu bar app. For on-demand programmes, scrub bar seeking and progress tracking stay synchronized.

**Blocked by:** 03: Sonos AVTransport Direct Playback and Metadata

**Status:** closed

- [x] Implement `SetVolume` and `GetVolume` SOAP actions on `RenderingControl` (`Master` channel, scale 0–100).
- [x] Implement `GetPositionInfo` SOAP action on `AVTransport` to parse track duration and current elapsed time (`RelTime`).
- [x] Implement `GetTransportInfo` SOAP action on `AVTransport` to track playback state changes (`PLAYING`, `PAUSED_PLAYBACK`, `STOPPED`).
- [x] Implement `Seek` (`REL_TIME`) SOAP action for jumping to specific timestamps in on-demand programmes.
- [x] Add a background polling task in `SonosController` (e.g. every 1.5s while active) to publish volume and position updates.
- [x] Write unit tests verifying volume changes, position polling, and seek actions against `MockSonosDevice`.
