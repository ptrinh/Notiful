cask "notiful" do
  version "1.0.0"
  sha256 "0f22d2c7fbf4e7b8aa69b1c0771dc4df38867948a992d0c163df66e2a71a7a73"

  url "https://github.com/ptrinh/Notiful/releases/download/v#{version}/Notiful.zip"
  name "Notiful"
  desc "Menu-bar app that extracts OTPs from notifications and runs shell commands on them"
  homepage "https://github.com/ptrinh/Notiful"

  depends_on macos: ">= :ventura"
  depends_on arch: :arm64

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
