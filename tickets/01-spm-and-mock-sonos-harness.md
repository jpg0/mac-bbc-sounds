# 01: SPM Dependency Setup and Mock Sonos Test Harness

**What to build:** An in-process mock Sonos UPnP HTTP server running inside the test suite, along with SPM dependency setup for SSDP client networking. This provides a repeatable, deterministic foundation so all subsequent Sonos features can be developed and verified test-first without requiring physical hardware on the local network.

**Blocked by:** None (can start immediately)

**Status:** completed

- [x] Add `SSDPClient` dependency to `Package.swift` and verify the package resolves and builds cleanly with `swift build`.
- [x] Implement `MockSonosDevice` in `Tests/BBCSoundsMenuBarTests/` using `NWListener` on loopback (`127.0.0.1`) that spins up on an ephemeral port and cleanly shuts down.
- [x] Support serving mock `device_description.xml` returning friendly room name, UDN, and model name.
- [x] Support serving mock `status/topology` XML returning zone groups and coordinators.
- [x] Support capturing SOAP requests to `/MediaRenderer/AVTransport/Control` and `/MediaRenderer/RenderingControl/Control` with inspection properties (`receivedURI`, `receivedDIDLLite`, `currentVolume`).
- [x] Write a verification test proving the mock server starts, responds to HTTP requests, records state, and stops without leaking sockets.
