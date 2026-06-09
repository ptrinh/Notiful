# Selling & licensing Notiful

Notiful can't ship on the Mac App Store — its core features (reading the notification database via
Full Disk Access, Accessibility banner capture, running shell commands) are exactly what the App
Store sandbox forbids. So it's sold **direct**, using the existing Developer ID + notarized +
Homebrew distribution plus **offline license keys**.

## How licensing works

- **Model:** perpetual one-time license, **soft enforcement**. A 60-day trial starts on first launch;
  after it ends Notiful keeps working but shows an "⚠️ Trial ended — buy a license" reminder. Nothing
  is gated.
- **Offline verification:** you hold an Ed25519 **private key** and sign each license. The app embeds
  only the **public key** and verifies licenses locally with CryptoKit — no phone-home, consistent
  with Notiful's "no network ever" promise. Implementation: `Sources/NotifulCore/License.swift`.
- A license string looks like `NOTIFUL1.<payload>.<signature>` and encodes `{ email, edition }`.

## One-time setup

1. **Generate your key pair** (keep the private key secret — a password manager or CI secret):
   ```sh
   swift run NotifulLicense keygen
   ```
2. **Embed the public key** in the app: paste it into `Licensing.publicKeyHex`
   (`Sources/Notiful/Licensing.swift`). The default all-zero placeholder makes every license fail to
   verify, so the app stays in trial/nag mode until you wire in your real key.
3. **Set your checkout URL** in `Licensing.purchaseURL` (your Paddle / Lemon Squeezy / Gumroad link).
4. Rebuild + release as usual (`./scripts/release.sh <version>`).

## Selling a license

1. Take payment via a checkout that can deliver a custom string per sale. Recommended:
   **Paddle** or **Lemon Squeezy** — both act as merchant of record and handle VAT/sales tax.
2. For each sale, sign a license with the buyer's email:
   ```sh
   swift run NotifulLicense sign --email buyer@example.com --key <YOUR_PRIVATE_HEX>
   ```
   Deliver the printed `NOTIFUL1.…` string to the buyer (most checkouts can email a "license key"
   field — either pre-generate a batch or wire `sign` into a tiny fulfillment webhook).
3. The buyer pastes it into **Notiful menu → Enter License…**. Done — verified offline, stored locally.

Sanity-check any key:
```sh
swift run NotifulLicense verify "NOTIFUL1.…" --pub <YOUR_PUBLIC_HEX>
```

## Notes

- Soft enforcement is deliberately easy to bypass; that's the trade-off for goodwill on a utility app.
  If you ever want harder gating, tighten the checks in `Licensing` / `AppDelegate`.
- Because verification is offline, you can't remotely revoke a leaked key without shipping a new build
  that rotates the public key. For a low-price utility this is usually fine.
