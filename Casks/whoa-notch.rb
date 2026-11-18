cask "whoa-notch" do
  version "1.2"
  sha256 "fdd19790be792fb5bafb3cbec3926377da383db73139e28e1efb34e653ae55c0"

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
