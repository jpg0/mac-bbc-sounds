# 02: Sonos SSDP Discovery and Group Topology

**What to build:** Automatic zero-configuration discovery of Sonos speakers on the local network. The service listens for SSDP multicast announcements, parses device description XML to resolve room names, queries the Sonos topology endpoint to identify active groups and coordinator speakers, and exposes an observable list of discovered Sonos rooms.

**Blocked by:** 01: SPM Dependency Setup and Mock Sonos Test Harness

**Status:** complete

- [x] Define `SonosDevice` and `AudioOutputTarget` models representing room names, IP addresses, ports, coordinator status, and group relationships.
- [x] Implement `SonosDiscoveryService` using `SSDPClient` searching for target `urn:schemas-upnp-org:device:ZonePlayer:1`.
- [x] Parse `device_description.xml` to extract `<roomName>`, `<displayName>`, and `<UDN>`.
- [x] Parse `status/topology` to identify group coordinators and determine combined room names (e.g. "Living Room + Kitchen").
- [x] Expose an observable `@Published var discoveredDevices: [SonosDevice]` list that updates as speakers appear and disappear.
- [x] Write unit tests verifying that `SonosDiscoveryService` correctly parses `MockSonosDevice` description and topology responses.
