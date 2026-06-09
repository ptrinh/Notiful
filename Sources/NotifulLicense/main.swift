import Foundation
import NotifulCore

// Vendor-side license tool. Keep the private key SECRET (e.g. a password manager / CI secret).
//
//   swift run NotifulLicense keygen
//       → prints a new (private, public) key pair. Paste the public key into the app once.
//
//   swift run NotifulLicense sign --email buyer@example.com [--edition pro] --key <PRIVATE_HEX>
//       → prints the license string to deliver to the buyer (via Paddle/Lemon Squeezy/email).
//
//   swift run NotifulLicense verify <LICENSE> --pub <PUBLIC_HEX>
//       → sanity-check a license against a public key.

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
    exit(1)
}

/// Parse `--flag value` pairs from the argument list.
func options(_ args: [String]) -> [String: String] {
    var out: [String: String] = [:]
    var i = 0
    while i < args.count {
        let a = args[i]
        if a.hasPrefix("--"), i + 1 < args.count {
            out[String(a.dropFirst(2))] = args[i + 1]
            i += 2
        } else { i += 1 }
    }
    return out
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fail("usage: NotifulLicense <keygen|sign|verify> …")
}
let rest = Array(args.dropFirst())
let opts = options(rest)

switch command {
case "keygen":
    let pair = LicenseCodec.generateKeyPair()
    print("""
    Generated Ed25519 key pair.

    PRIVATE key (keep secret — used to sign licenses):
      \(pair.privateKeyHex)

    PUBLIC key (paste into the app — Licensing.publicKeyHex):
      \(pair.publicKeyHex)
    """)

case "sign":
    guard let email = opts["email"] else { fail("sign requires --email") }
    guard let priv = opts["key"] else { fail("sign requires --key <PRIVATE_HEX>") }
    let edition = opts["edition"] ?? "pro"
    do {
        let license = License(email: email, edition: edition)
        let str = try LicenseCodec.sign(license, privateKeyHex: priv)
        print(str)
    } catch { fail("could not sign: \(error)") }

case "verify":
    guard let licenseString = rest.first, !licenseString.hasPrefix("--") else {
        fail("usage: verify <LICENSE> --pub <PUBLIC_HEX>")
    }
    guard let pub = opts["pub"] else { fail("verify requires --pub <PUBLIC_HEX>") }
    do {
        let license = try LicenseCodec.verify(licenseString, publicKeyHex: pub)
        print("valid ✓  email=\(license.email)  edition=\(license.edition)")
    } catch { fail("invalid: \(error)") }

default:
    fail("unknown command '\(command)' — use keygen, sign, or verify")
}
