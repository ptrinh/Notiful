# Notiful

A tiny, **local-only** macOS menu-bar app that extracts one-time passcodes from your notifications (click to copy) and can run a custom shell command on the notification text.

It exists because macOS only autofills codes from native Messages/Mail. Codes that arrive via
the browser (e.g. **Google Voice**, which has no Mac app) or other apps render as notifications
but can't be autofilled — yet the text is already on disk in the Notification Center DB. Notiful
reads it from there.

- **No network. Ever.** All processing is local.
- **No third-party dependencies.** Pure Swift + system frameworks.
- Native menu-bar app (no Dock icon).

---

## Screenshots

A detected code as Notiful's own actionable notification — click to copy:

![Notiful notification banner](Screenshots/banner-example.png)

The menu-bar menu:

![Menu bar menu](Screenshots/menu-bar.png)

The visual configuration window — add sources straight from your recent notifications:

![Configuration window](Screenshots/config-screen.png)

---

## Install

> **Apple Silicon (arm64) only**, macOS 13+. Notiful is **ad-hoc signed, not notarized**, so macOS
> Gatekeeper needs a one-time bypass (covered below). It makes **no network calls** — you can read
> every line of source here.

### Option 1 — Homebrew (recommended)

```sh
brew tap ptrinh/notiful https://github.com/ptrinh/Notiful
brew install --cask --no-quarantine notiful
```

`--no-quarantine` is needed because the app isn't notarized. Then launch it:

```sh
open -a Notiful
```

Upgrade later with `brew upgrade --cask notiful`; remove with `brew uninstall --cask notiful`
(add `--zap` to also delete config/prefs).

### Option 2 — Download the app

1. Download **`Notiful.zip`** from the [latest release](https://github.com/ptrinh/Notiful/releases/latest).
2. Unzip it and move **Notiful.app** to **/Applications**.
3. Because it isn't notarized, remove the quarantine flag, then open it:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Notiful.app
   open -a Notiful
   ```
   (Or right-click the app → **Open** → **Open** on the warning dialog.)

### First run (either method)

1. A 🔑 icon appears in the menu bar and a welcome popup explains the next step.
2. **Grant Full Disk Access** (required to read the notification database):
   System Settings → Privacy & Security → **Full Disk Access** → add/enable **Notiful** → relaunch it.
3. Optionally enable **Instant capture (Accessibility)** from the menu for sub-second capture
   (needs the Accessibility permission — see [Instant capture](#instant-capture-accessibility--optional)).
4. Use **Configure…** in the menu to pick which notifications to watch.

See [Setup](#grant-full-disk-access-required) and [Google Voice setup](#google-voice-setup-single-banner)
for details.

---

## Requirements

- macOS 13 (Ventura) or later. Verified on **macOS 26**. Apple Silicon (arm64).
- To build from source: Swift toolchain (Xcode **or** Command Line Tools — `xcode-select --install`).

## Build from source

```sh
./scripts/build-app.sh
```

This compiles a release binary and assembles a code-signed **`Notiful.app`** in the repo root.
(Ad-hoc signing is required for `UNUserNotificationCenter` and login-item registration.)

Run it:

```sh
open Notiful.app
```

A 🔑 icon appears in the menu bar. On first launch a short popup explains what Notiful does and why
it needs Full Disk Access.

### Menu options

- **Enable / Disable** — pause detection.
- **Recent codes** — last few detected codes, masked; click to re-copy.
- **Auto-copy codes** — when on, every detected code is copied to the clipboard the moment it arrives
  (in addition to click-to-copy). Off by default.
- **Configure…** — visual editor that lists your **recent notifications** so you can add a source by
  clicking a real one ("Add by App" for native apps, "Add by Sender text" for browser sources), set a
  per-source command, or toggle auto-copy — no JSON required. "Open config file" still opens the raw JSON.
- **Hide menu bar icon** — hides the icon; Notiful keeps running. To bring it back, **open Notiful
  again** from Applications/Spotlight and the icon reappears.
- **Launch at login**, **Open config file**, **Open log**, **Grant Full Disk Access…**, **Credit**, **Quit**.

### Run a command when a code arrives

Each source can run a shell command on detection (`actions.runCommand`, or set it in **Configure…**).
The notification text and code are passed as **environment variables** (not interpolated into the
string — avoids injection):

`NOTIFUL_CODE`, `NOTIFUL_SOURCE`, `NOTIFUL_APP`, `NOTIFUL_TITLE`, `NOTIFUL_SUBTITLE`, `NOTIFUL_BODY`

```json
"actions": { "runCommand": "echo \"$NOTIFUL_SOURCE: $NOTIFUL_CODE\" >> ~/otp.log" }
```

⚠️ This runs arbitrary shell code with your privileges — only put commands you trust here.

### Headless / scripted use

```sh
Notiful.app/Contents/MacOS/Notiful --once
```

Scans the latest matching OTP notification, copies the code to the clipboard, and prints a
**masked** result (e.g. `Google Voice · 6••••0 — copied to clipboard`). Exit code `0` on a hit,
`1` if nothing matched.

---

## Grant Full Disk Access (required)

Notiful reads another process's database, so it needs Full Disk Access (FDA) and is **not**
sandboxed.

1. **System Settings → Privacy & Security → Full Disk Access**
   (or run `open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"`)
2. Click **+** and add **Notiful.app**, then enable it.
3. **Relaunch Notiful** (the grant only applies on relaunch).

Until FDA is granted, the menu-bar icon shows a ⚠️ and Notiful posts a notification linking you
to the right settings pane.

> When running the raw `swift`-built binary during development (not the `.app`), grant FDA to
> your **terminal** instead — child processes inherit it.

---

## ⚠️ Important: stop double banners

You **cannot** override another app's notification click — the app that posts a notification owns
it. So Notiful posts its *own* notification and you mute the source app's banner. To avoid seeing
two banners per code:

For each source app (Google Voice in your browser, Telegram, WhatsApp, …):

**System Settings → Notifications → \<the app\>:**
- Keep **Allow Notifications: ON** ← critical, so the code still reaches Notification Center / the DB.
- **Uncheck "Desktop"** — this is the on-screen banner you want to suppress.
- Keep **"Notification Center" ON** so the code still reaches the database. ("Lock Screen" is your choice.)

(On macOS 15/26 there's no "None" style dropdown — the on-screen banner is the **Desktop** checkbox.)

Notiful then shows the only banner. Notiful can't *remove* other apps' notifications, which is why
we mute the banner rather than disabling the notification.

> **A note on latency.** macOS holds a delivered notification in memory for a short presentation
> window (~5s) before committing it to this database — and that happens whether or not a banner is
> shown. Because Notiful reads the database, codes typically appear **a few seconds after** they
> arrive. Unchecking "Desktop" removes the duplicate banner but does **not** change this delay; it's
> a macOS limitation of the database approach. **For instant capture, enable "Instant capture
> (Accessibility)" in the menu — see below.**

---

## Instant capture (Accessibility) — optional

The database is only written ~5s after a notification arrives, so the default (database) path always
lags. **Instant capture** reads the banner directly off the screen via the macOS Accessibility API the
moment it appears, copying the code immediately. The database watcher stays on as a fallback.

Enable it from the menu: **Instant capture (Accessibility)** → grant Notiful **Accessibility** in
System Settings → Privacy & Security → Accessibility (it starts working automatically once granted).

Trade-offs:
- The source app's banner **must stay visible** (don't hide its "Desktop" banner) — there has to be a
  banner on screen to read.
- Optional **Auto-dismiss source banner** clears the source's banner right after capture, so you mostly
  see only Notiful's banner.
- Matching here is **text-based** (the banner doesn't expose the posting app's bundle id), so it covers
  sources matched by `senderContains` / `titleContains` / `bodyContains` (e.g. Google Voice). Native
  sources matched purely by `appBundleIds` (Telegram, WhatsApp) still arrive via the database fallback.
- Requires a second permission (Accessibility). Codes are still never written to disk.

---

## Google Voice setup (single banner)

Google Voice has no Mac app — it runs inside Chrome, and by default Chrome files all web notifications
under "Google Chrome", so you can't mute *just* Google Voice. Install it as its own app and give it a
separate notification entry:

**1. Install Google Voice as an app**
- In Chrome, open **voice.google.com** and sign in.
- Click the **install icon** in the address bar (or **⋮ → Cast, Save, and Share → Install page as app…**).

**2. Turn on PWA notification attribution**
- Open **chrome://flags/#enable-mac-pwas-notification-attribution** (or search `chrome://flags` for
  **"Mac PWA notification attribution"**).
- Set it to **Enabled**.
- **Quit and reopen Chrome** (click Relaunch, then fully quit Chrome ⌘Q and start it again) — the flag
  only takes effect on a fresh Chrome launch.

**3. Run Google Voice as the app, not a tab**
- Close any `voice.google.com` **tab** in Chrome (a tab posts under Chrome).
- Open the **Google Voice** app from Launchpad/Applications; allow notifications if prompted.

**4. Mute its banner** — trigger one code so macOS registers the app, then in
**System Settings → Notifications → Google Voice**:
- **Allow notifications:** ON
- **Uncheck "Desktop"** (this is the banner)
- **"Notification Center":** ON

Now Notiful shows the only banner for the code. (The code still appears a few seconds after it
arrives — see the latency note above; that delay is inherent to reading the macOS database.)

**5. (If needed) point Notiful at it** — open **Configure…**; after a code arrives, select the Google
Voice row and **Add by App**, or rely on the built-in `voice.google.com` rule that already matches.

> The same pattern works for any browser-delivered source: install it as an app, enable the flag, and
> uncheck that app's "Desktop" banner. Native apps (Telegram, WhatsApp) already have their own entry —
> just uncheck "Desktop" for them.

---

## Configuration

`~/Library/Application Support/Notiful/config.json` — created with sensible defaults on first run.
Edit it visually via the menu's **Configure…** window (which can also open the raw JSON). Any omitted
key falls back to its default, so you can keep entries minimal.

```jsonc
{
  "defaultOTPRegex": "\\b(\\d{4,8})\\b",   // global fallback; smart keyword-biased extraction runs first
  "clipboardAutoClearSeconds": 0,           // 0 = never auto-clear
  "pollIntervalSeconds": 2,                 // watch debounce / fallback poll
  "sources": [ /* see below */ ]
}
```

### A `source` has

| field         | meaning |
|---------------|---------|
| `name`        | label shown in the notification & menu, e.g. `"Google Voice"` |
| `match`       | how to recognise it (see below). Matches when **any** positive criterion hits. |
| `otpRegex`    | *(optional)* per-source regex override (capture group 1 = the code) |
| `actions`     | `autoCopy`, `showActionableNotification`, `openButton`, `openTarget` |

### `match` options (any one is enough)

- `appBundleIds` — match notifications posted by these apps (case-insensitive). **Use for native apps.**
- `senderContains` — substring match on the title **or subtitle**. **Use for browser-delivered sources.**
- `titleContains` — substring match on the title only.
- `bodyContains` — *(optional extra gate)* the body must also contain one of these.

### `actions`

- `autoCopy` *(default `false`)* — copy the moment the code arrives. Off by default so your clipboard
  is only overwritten when you click — see [Security](#security).
- `showActionableNotification` *(default `true`)* — post Notiful's clickable notification.
- `openButton` / `openTarget` — add an "Open Source" button; `openTarget` is a URL (`https://voice.google.com`)
  or an app bundle id (`com.tdesktop.Telegram`).

### Worked examples (these ship as defaults)

**Google Voice** — browser-delivered. Real GV notifications come from Chrome with the phone number
in the title and `voice.google.com` in the subtitle, so we match on the subtitle marker:

```json
{
  "name": "Google Voice",
  "match": { "senderContains": ["Google Voice", "voice.google.com"] },
  "actions": { "openButton": true, "openTarget": "https://voice.google.com" }
}
```

**Telegram** — native app, matched by bundle id:

```json
{
  "name": "Telegram",
  "match": { "appBundleIds": ["com.tdesktop.Telegram", "ru.keepcoder.Telegram"] },
  "actions": { "openButton": true, "openTarget": "com.tdesktop.Telegram" }
}
```

**WhatsApp** — native app:

```json
{
  "name": "WhatsApp",
  "match": { "appBundleIds": ["net.whatsapp.WhatsApp"] },
  "actions": { "openButton": true, "openTarget": "net.whatsapp.WhatsApp" }
}
```

#### Finding an app's bundle id

```sh
osascript -e 'id of app "Telegram"'
# or, for an app that's already posted a notification, inspect the DB's `app` table.
```

---

## Security & blast radius

- **Local only — no network code exists.** Audit it: nothing imports URLSession/Network.
- Because Notiful has Full Disk Access, it *can* read **every** app's notifications. It only acts on
  notifications matching your configured sources. The codebase is deliberately small and auditable —
  read `Sources/NotifulCore` before trusting it with FDA.
- **Codes are never written to disk.** The de-dupe state file stores only record IDs/timestamps. The
  "Recent codes" menu keeps the last few **in memory only** and clears on quit.
- **Codes are masked everywhere** in logs and the menu (e.g. `6••••0`).
- **Click-to-copy by default** (`autoCopy` off) so your clipboard is only overwritten on intent.
- Optional `clipboardAutoClearSeconds` clears the clipboard after a timeout — but only if it *still*
  holds that exact code (it won't clobber something you copied since).

---

## How it works

1. Locates the DB (`~/Library/Group Containers/group.com.apple.usernoted/db2/db` on macOS 15+).
2. Copies `db` + `db-wal` + `db-shm` to a temp dir and opens the copy **read-only** — this avoids
   locking the live DB *and* picks up just-delivered notifications, which live in the WAL.
3. Watches `db-wal` via a `DispatchSource` (kqueue) file monitor — event-driven, ~0% CPU when idle —
   with a sparse interval timer purely as a safety net. A cheap `mtime` check skips the copy+query
   entirely when nothing has changed, so idle timer ticks cost only a `stat()`.
4. Decodes each new record's binary plist (`req → titl/subt/body`; posting app from the `app` table),
   runs it through your source matchers, and extracts the code (keyword-biased; rejects phone numbers,
   dates, and currency amounts).
5. De-dupes against a watermark (last processed record id) and the app's launch time, so the same code
   is never acted on twice and stale codes from before launch are ignored.

---

## Tests

```sh
swift run NotifulTests
```

A dependency-free runner (XCTest needs full Xcode; this works with Command Line Tools). Covers bplist
decoding against the real layout, OTP extraction over real GV/Telegram/WhatsApp/Amex/Slack formats plus
negatives (phones, dates, dollar amounts), and the source matcher.

---

## Uninstall

1. Quit Notiful (menu → **Quit**).
2. If you enabled "Launch at login", toggle it off first (or it remains registered).
3. Delete the app and its data:
   ```sh
   rm -rf Notiful.app
   rm -rf "$HOME/Library/Application Support/Notiful"
   ```
4. Remove **Notiful** from **System Settings → Privacy & Security → Full Disk Access**.
5. Restore the muted source apps' notification styles if you want their banners back.
