import DaybriefCore
import Foundation

/// The shape stashed into ``RawItem/json`` by ``SlackConnector/fetch(_:)``.
///
/// `search.messages` and `conversations.history` return Slack messages in slightly
/// different shapes and `normalize(_:)` needs to know *where* a message came from
/// (a mention vs a DM vs a group DM) and which channel — context the bare provider
/// message doesn't carry. We therefore wrap the verbatim provider message in a small
/// envelope so fetch and normalize stay decoupled and everything round-trips through
/// a plain ``JSONValue`` (fixture- and XPC-safe).
struct SlackRawEnvelope {
    /// Where a stashed message originated.
    enum Origin: String {
        /// A `search.messages` hit (the user was @-mentioned).
        case mention
        /// A 1:1 direct message (`conversations.history` on an `im`).
        case directMessage = "dm"
        /// A multi-person group DM (`conversations.history` on an `mpim`).
        case groupDM = "mpim"
    }

    /// Where the message came from.
    let origin: Origin
    /// The channel/DM display name, if known.
    let channelName: String?
    /// The verbatim Slack message object.
    let message: JSONValue

    /// The envelope encoded as a ``JSONValue`` for ``RawItem/json``.
    var json: JSONValue {
        var object: [String: JSONValue] = [
            "_origin": .string(origin.rawValue),
            "message": message,
        ]
        if let channelName {
            object["_channelName"] = .string(channelName)
        }
        return .object(object)
    }

    /// Reconstructs an envelope from a stashed ``JSONValue`` (nil if malformed).
    init?(json: JSONValue) {
        guard let originRaw = json["_origin"]?.string,
              let origin = Origin(rawValue: originRaw),
              let message = json["message"]
        else { return nil }
        self.origin = origin
        channelName = json["_channelName"]?.string
        self.message = message
    }

    /// Creates an envelope to stash during fetch.
    init(origin: Origin, channelName: String?, message: JSONValue) {
        self.origin = origin
        self.channelName = channelName
        self.message = message
    }
}
