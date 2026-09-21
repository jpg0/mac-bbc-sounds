# 05: LAN-Bound Smart Delivery Relay for Proxied Streams

**What to build:** Local proxy relay support over the local network so geo-blocked or authenticated streams play seamlessly on Sonos when a proxy is configured. When proxying is active, `LocalProxyServer` binds to all local interfaces (`0.0.0.0`) and resolves the Mac's LAN IP address, supplying Sonos with a local relay URL that proxies through the upstream VPN/proxy.

**Blocked by:** 03: Sonos AVTransport Direct Playback and Metadata

**Status:** done

- [x] Update `LocalProxyServer` to support binding to `0.0.0.0` (or specified host address) in addition to loopback `127.0.0.1`.
- [x] Add network utility to resolve the Mac's primary Wi-Fi / Ethernet LAN IP address.
- [x] Build a relay URL generator (`http://<lan-ip>:<port>/playlist?url=...`) for Sonos when `proxyConfig` is present.
- [x] Implement smart delivery decision logic: use direct BBC stream URL when no proxy is configured, and use LAN relay URL when proxy is enabled.
- [x] Write integration test verifying that a proxied stream playlist and segment can be fetched through `LocalProxyServer` via its LAN-bound interface.
