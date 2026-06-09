cask "notiful" do
  version "1.0.4"
  sha256 "69667b4a57ad2103a684adaa5caca851d51bd759254bcba7179a0924eb56c0ae"

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
