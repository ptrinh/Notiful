cask "notiful" do
  version "1.0.0"
  sha256 "7a7529281da34b827d10e0cc4056aa70064fb69b74bb4edea89e5c1032ecac0f"

  url "https://github.com/ptrinh/Notiful/releases/download/v#{version}/Notiful.zip"
  name "Notiful"
  desc "Menu-bar app that extracts OTPs from notifications and runs shell commands on them"
  homepage "https://github.com/ptrinh/Notiful"

  depends_on macos: ">= :ventura"

  app "Notiful.app"

  caveats <<~EOS
    Notiful is ad-hoc signed (not notarized), so install with quarantine disabled:
      brew install --cask --no-quarantine notiful
    If you already installed it and macOS blocks it, run:
      xattr -dr com.apple.quarantine "#{appdir}/Notiful.app"

    Notiful needs Full Disk Access to read the notification database:
      System Settings -> Privacy & Security -> Full Disk Access -> enable Notiful, then relaunch.
  EOS

  zap trash: [
    "~/Library/Application Support/Notiful",
    "~/Library/Preferences/com.notiful.app.plist",
  ]
end
