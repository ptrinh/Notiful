cask "notiful" do
  version "1.0.3"
  sha256 "09a88af0eef633b390b9b195facf653de5da92844c4644b4c410eb9f92a6dfc6"

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
