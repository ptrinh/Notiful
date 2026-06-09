cask "notiful" do
  version "1.0.6"
  sha256 "75b223cd3df7a29027caab800494b4b3a4e9646dffe69daa21310bba31034322"

  url "https://github.com/ptrinh/Notiful/releases/download/v#{version}/Notiful.zip"
  name "Notiful"
  desc "Menu-bar app that extracts OTPs from notifications and runs shell commands on them"
  homepage "https://github.com/ptrinh/Notiful"

  depends_on macos: ">= :ventura"

  app "Notiful.app"

  caveats <<~EOS
    Notiful needs Full Disk Access to read the notification database:
      System Settings -> Privacy & Security -> Full Disk Access -> enable Notiful, then relaunch.
  EOS

  zap trash: [
    "~/Library/Application Support/Notiful",
    "~/Library/Preferences/com.notiful.app.plist",
  ]
end
