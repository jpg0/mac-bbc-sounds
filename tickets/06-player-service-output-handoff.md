# 06: PlayerService Output Target Routing and Handoff

**What to build:** Unified audio routing and seamless handoff in `PlayerService`. The user can switch the active output target between "This Mac" and any Sonos room. Selecting Sonos pauses the local Mac `AVPlayer` and hands off the stream to `SonosController`; switching back resumes locally at the same playback offset. All transport controls (Play, Pause, Stop, Seek, Volume) route to whichever output target is active.

**Blocked by:**
- 04: Sonos Volume Control and Position Synchronization
- 05: LAN-Bound Smart Delivery Relay for Proxied Streams

**Status:** ready-for-agent

- [ ] Add `@Published var outputTarget: AudioOutputTarget = .thisMac` to `PlayerService`.
- [ ] Connect `PlayerService` to `SonosDiscoveryService` and instantiate/manage `SonosController` for the active Sonos target.
- [ ] Route `play()`, `pause()`, `resume()`, `stop()`, `seek()`, and `setVolume()` based on the active `outputTarget`.
- [ ] Implement seamless output handoff: switching target during playback transfers the current stream URL and elapsed time without losing state.
- [ ] Ensure local Mac `AVPlayer` is silenced/paused when Sonos is active to prevent duplicate audio.
- [ ] Write unit tests verifying that toggling `outputTarget` stops local playback, engages `SonosController`, and preserves playback time.
