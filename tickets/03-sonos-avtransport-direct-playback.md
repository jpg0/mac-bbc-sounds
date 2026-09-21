# 03: Sonos AVTransport Direct Playback and Metadata

**What to build:** Native UPnP AVTransport control enabling BBC Sounds streams to play directly on a target Sonos speaker. The controller formats rich DIDL-Lite metadata so the programme name, station name, and album artwork thumbnail display accurately on Sonos devices and the Sonos app.

**Blocked by:** 02: Sonos SSDP Discovery and Group Topology

**Status:** ready-for-agent

- [ ] Implement `SonosController` targeting a specific `SonosDevice` (using its coordinator endpoint).
- [ ] Implement `SetAVTransportURI` SOAP action sending stream URL and XML-escaped DIDL-Lite metadata.
- [ ] Format DIDL-Lite XML with `<dc:title>` (programme name), `<dc:creator>` (channel/station), and `<upnp:albumArtURI>` (artwork URL).
- [ ] Implement `Play`, `Pause`, and `Stop` SOAP actions on `AVTransport`.
- [ ] Write unit tests verifying that invoking playback commands on `SonosController` delivers the expected SOAP envelopes and DIDL-Lite metadata to `MockSonosDevice`.
