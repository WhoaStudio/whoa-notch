cask "whoa-notch" do
  version "1.1"
  sha256 "bab87f8f497e1f899d8737390f5449a9476dad6b5f224f16e3690b4b8f02211b"

  url "https://github.com/WhoaStudio/whoa-notch/releases/download/v#{version}/whoa-notch-#{version}.dmg"
  name "Whoa Notch"
  desc "Menu bar controls and panels at the edges of your screen"
  homepage "https://github.com/WhoaStudio/whoa-notch"

  depends_on macos: :tahoe

  app "whoa-notch.app"

  caveats do
    "Requires macOS 26.5 or later."
  end
end
