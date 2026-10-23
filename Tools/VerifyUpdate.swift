import Foundation
import CryptoKit

// Verify with the public key embedded in the app, independently of the signing key.
final class AppcastReader: NSObject, XMLParserDelegate {
    var signature: String?
    var length: String?
    var downloadURL: String?
    var descriptionFormat: String?
    var values: [String: String] = [:]
    private var element = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        element = name
        if name == "enclosure" {
            signature = attributes["sparkle:edSignature"]
            length = attributes["length"]
            downloadURL = attributes["url"]
        }
        if name == "description" { descriptionFormat = attributes["sparkle:format"] }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        values[element, default: ""] += string
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { element = "" }
}

@main
struct VerifyUpdate {
    static func main() {
        do { try verify() } catch {
            fputs("Update verification failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func verify() throws {
        guard CommandLine.arguments.count == 5 else {
            fatalError("Usage: VerifyUpdate Info.plist appcast.xml archive.zip download-url")
        }
        let args = CommandLine.arguments
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: args[1])), format: nil) as! [String: Any]
        let feedData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let feedText = String(decoding: feedData, as: UTF8.self)
        let pattern = #"<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->"#
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: feedText, range: NSRange(feedText.startIndex..., in: feedText)),
              let signatureRange = Range(match.range(at: 1), in: feedText),
              let lengthRange = Range(match.range(at: 2), in: feedText),
              let feedSignature = Data(base64Encoded: String(feedText[signatureRange])),
              let signedLength = Int(feedText[lengthRange]), signedLength <= feedData.count,
              let publicData = Data(base64Encoded: info["SUPublicEDKey"] as! String),
              try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
                .isValidSignature(feedSignature, for: feedData.prefix(signedLength)) else {
            throw NSError(domain: "RadioBar.FeedSignature", code: 1)
        }
        let reader = AppcastReader()
        let parser = XMLParser(data: feedData)
        parser.delegate = reader
        guard parser.parse(),
              reader.values["sparkle:version"]?.trimmingCharacters(in: .whitespacesAndNewlines) == info["CFBundleVersion"] as? String,
              reader.values["sparkle:shortVersionString"]?.trimmingCharacters(in: .whitespacesAndNewlines) == info["CFBundleShortVersionString"] as? String,
              reader.downloadURL == args[4],
              reader.descriptionFormat == "plain-text",
              reader.values["description"]?.contains(info["CFBundleShortVersionString"] as! String) == true,
              reader.values["description"]?.contains("• ") == true,
              let publicKey = Data(base64Encoded: info["SUPublicEDKey"] as! String),
              let signature = reader.signature.flatMap({ Data(base64Encoded: $0) }) else {
            throw NSError(domain: "RadioBar.UpdateMetadata", code: 1)
        }
        let archive = try Data(contentsOf: URL(fileURLWithPath: args[3]))
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard reader.length == String(archive.count), key.isValidSignature(signature, for: archive) else {
            throw NSError(domain: "RadioBar.UpdateSignature", code: 1)
        }
        print("PASS: appcast version, URL, length and feed and archive EdDSA signatures match the app")
    }
}
