import AppKit

enum Welcome {
    static let donationURL = URL(string: "https://buy.stripe.com/7sY28t0pqa2Odj94rb8AE01")!

    private static let contentWidth: CGFloat = 480

    /// First-run explainer: what Notiful is and why it needs Full Disk Access.
    /// Returns true if the user clicked "Open Full Disk Access".
    @discardableResult
    static func showIfNeeded(force: Bool = false) -> Bool {
        guard force || !Preferences.welcomeShown else { return false }
        Preferences.welcomeShown = true

        let granted = FDA.isGranted()
        let alert = NSAlert()
        // The styled content lives in the accessory view so we control the type sizes.
        alert.messageText = ""
        alert.informativeText = ""
        alert.alertStyle = .informational
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        // Show the donation/credit only when reopened from "About" (force) — not during first-run
        // onboarding, where asking for money before any value has been delivered reads as pushy.
        alert.accessoryView = contentView(granted: granted, showCredit: force)
        if !granted {
            alert.addButton(withTitle: "Open Full Disk Access")
        }
        alert.addButton(withTitle: granted ? "Close" : "Later")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if !granted, response == .alertFirstButtonReturn {
            FDA.openSettings()
            return true
        }
        return false
    }

    // MARK: - Content

    private static func contentView(granted: Bool, showCredit: Bool) -> NSView {
        var rows: [NSView] = []

        rows.append(title("Welcome to Notiful"))
        rows.append(body(
            "Notiful watches notifications from sources you choose — like Google Voice, Telegram or "
            + "WhatsApp — and acts on them: it extracts one-time passcodes (2FA / verification codes) "
            + "so you can copy them with a single click, and it can run a custom shell command on the "
            + "notification text (the code and title/body are passed as environment variables)."))

        if granted {
            rows.append(body(
                "Full Disk Access is granted, so you’re all set. Open “Configure…” from the menu "
                + "to choose which notifications to watch."))
        } else {
            rows.append(subtitle("Why Full Disk Access?"))
            rows.append(body(
                "The codes already arrive as macOS notifications, stored in a protected system "
                + "database. macOS only lets an app read that database if you grant it Full Disk "
                + "Access. Notiful reads it locally and never sends anything over the network."))
        }

        if showCredit { rows.append(creditView()) }

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setHuggingPriority(.required, for: .vertical)
        // Size to fit the fixed content width.
        let fitting = stack.fittingSize
        stack.frame = NSRect(x: 0, y: 0, width: contentWidth, height: fitting.height)
        return stack
    }

    // MARK: - Text helpers

    private static func title(_ s: String) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font = .systemFont(ofSize: 22, weight: .bold)
        f.textColor = .labelColor
        return f
    }

    private static func subtitle(_ s: String) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font = .systemFont(ofSize: 15, weight: .semibold)
        f.textColor = .labelColor
        return f
    }

    private static func body(_ s: String) -> NSTextField {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let f = NSTextField(wrappingLabelWithString: "")
        f.attributedStringValue = NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ])
        f.preferredMaxLayoutWidth = contentWidth
        f.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return f
    }

    /// Prominent credit line: "© Phil Trinh — phil@trinh.uk. Donation here ♥" with a clickable link.
    private static func creditView() -> NSView {
        let field = NSTextField(labelWithString: "")
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]
        let text = NSMutableAttributedString(string: "© Phil Trinh — phil@trinh.uk.  ", attributes: base)
        text.append(NSAttributedString(
            string: "Donation here ♥",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .link: donationURL,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]))
        field.attributedStringValue = text
        field.isSelectable = true
        field.allowsEditingTextAttributes = true  // required for clickable links
        field.isBezeled = false
        field.drawsBackground = false
        field.alignment = .center
        field.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.layer?.borderWidth = 1
        box.layer?.cornerRadius = 6
        box.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            field.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            field.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            box.widthAnchor.constraint(equalToConstant: contentWidth),
        ])
        return box
    }
}
