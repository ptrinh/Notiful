import Foundation
import CryptoKit

/// Offline license verification using Ed25519 (Curve25519) signatures.
///
/// The vendor holds a PRIVATE key and signs each license; the app embeds only the matching PUBLIC
/// key and verifies licenses locally — no network call, preserving Notiful's "no network ever"
/// promise. A license is self-contained: `NOTIFUL1.<base64url(payload)>.<base64url(signature)>`.
///
/// Generate a key pair and sign licenses with the `notiful-license` tool (see Sources/NotifulLicense).
public struct License: Codable, Equatable, Sendable {
    /// Buyer's email — shown in the app so the owner can see who it's licensed to.
    public var email: String
    /// Edition string (e.g. "pro"). Perpetual one-time licenses carry no expiry.
    public var edition: String

    public init(email: String, edition: String = "pro") {
        self.email = email
        self.edition = edition
    }
}

public enum LicenseError: Error, Equatable {
    case malformed
    case badSignature
    case unsupportedVersion
}

public enum LicenseCodec {
    private static let prefix = "NOTIFUL1"

    /// Verify a license string against the embedded public key. Returns the decoded `License` on
    /// success, or throws `LicenseError` if the format is wrong or the signature doesn't match.
    public static func verify(_ licenseString: String, publicKeyHex: String) throws -> License {
        let parts = licenseString.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3 else { throw LicenseError.malformed }
        guard parts[0] == prefix else { throw LicenseError.unsupportedVersion }
        guard let payloadData = base64urlDecode(String(parts[1])),
              let sigData = base64urlDecode(String(parts[2])),
              let pubKeyData = Data(hexString: publicKeyHex) else { throw LicenseError.malformed }

        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
        } catch { throw LicenseError.malformed }

        guard publicKey.isValidSignature(sigData, for: payloadData) else { throw LicenseError.badSignature }
        guard let license = try? JSONDecoder().decode(License.self, from: payloadData) else {
            throw LicenseError.malformed
        }
        return license
    }

    // MARK: - Signing (used by the vendor tool, not the app)

    /// Sign a license with the private key, producing the distributable license string.
    public static func sign(_ license: License, privateKeyHex: String) throws -> String {
        guard let keyData = Data(hexString: privateKeyHex) else { throw LicenseError.malformed }
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        let payload = try JSONEncoder.canonical.encode(license)
        let signature = try privateKey.signature(for: payload)
        return "\(prefix).\(base64urlEncode(payload)).\(base64urlEncode(signature))"
    }

    /// Generate a fresh Ed25519 key pair as (privateKeyHex, publicKeyHex).
    /// Keep the private key secret; paste the public key into the app (see License.embeddedPublicKeyHex).
    public static func generateKeyPair() -> (privateKeyHex: String, publicKeyHex: String) {
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation.hexString, key.publicKey.rawRepresentation.hexString)
    }

    // MARK: - base64url

    private static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64urlDecode(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        return Data(base64Encoded: b64)
    }
}

private extension JSONEncoder {
    /// Deterministic encoding so the signed bytes are stable across platforms.
    static var canonical: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    init?(hexString: String) {
        let clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count % 2 == 0 else { return nil }
        var data = Data(capacity: clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let byte = UInt8(clean[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        self = data
    }
}
