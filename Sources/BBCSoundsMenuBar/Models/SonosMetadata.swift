import Foundation

/// Represents metadata for playback on a Sonos device, formatted into UPnP DIDL-Lite XML.
public struct SonosMetadata: Equatable, Sendable {

    /// Title of the programme or episode
    public let title: String

    /// Channel, station, or artist/creator name
    public let creator: String?

    /// Album artwork thumbnail URL
    public let albumArtURI: String?

    /// Whether the programme is a live broadcast
    public let isLive: Bool

    public init(title: String, creator: String? = nil, albumArtURI: String? = nil, isLive: Bool = false) {
        self.title = title
        self.creator = creator
        self.albumArtURI = albumArtURI
        self.isLive = isLive
    }

    /// Convenience initializer mapping from BBC Sounds `Programme`
    init(programme: Programme) {
        self.title = programme.name
        self.creator = programme.channel.isEmpty ? nil : programme.channel
        let artwork = programme.artworkURL?.replacingOccurrences(of: "{recipe}", with: "400x400")
        self.albumArtURI = (artwork?.isEmpty == false) ? artwork : nil
        self.isLive = programme.isLive
    }

    /// Generates unescaped DIDL-Lite XML for UPnP metadata.
    public func didlLiteXML(uri: String? = nil) -> String {
        var xml = "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\" xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\">"
        xml += "<item id=\"-1\" parentID=\"-1\" restricted=\"true\">"
        if let uri = uri {
            let protocolInfo = isLive ? "sonos.com-hls-radio:*:application/x-mpegURL:*" : "http-get:*:application/vnd.apple.mpegurl:*"
            xml += "<res protocolInfo=\"\(protocolInfo)\">\(Self.escapeXML(uri))</res>"
        }
        xml += "<dc:title>\(Self.escapeXML(title))</dc:title>"
        if let creator = creator, !creator.isEmpty {
            xml += "<dc:creator>\(Self.escapeXML(creator))</dc:creator>"
        }
        if let albumArtURI = albumArtURI, !albumArtURI.isEmpty {
            xml += "<upnp:albumArtURI>\(Self.escapeXML(albumArtURI))</upnp:albumArtURI>"
        }
        let upnpClass = isLive ? "object.item.audioItem.audioBroadcast" : "object.item.audioItem.musicTrack"
        xml += "<upnp:class>\(upnpClass)</upnp:class>"
        xml += "</item></DIDL-Lite>"
        return xml
    }

    /// XML-escapes text for inclusion in XML elements and attributes.
    public static func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
