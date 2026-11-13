cask "whoa-stash" do
  version "1.0.1"
  sha256 "82c9b5d371cb1afa0be826173f8d1fbee9e01de51eccbbbe5e083f4e61279c39"

  url "https://github.com/WhoaStudio/whoa-stash/releases/download/v#{version}/whoa-stash-#{version}.dmg"
  name "Whoa Stash"
  desc "Menu bar controls and panels at the edges of your screen"
  homepage "https://github.com/WhoaStudio/whoa-stash"

  depends_on macos: :tahoe

  app "whoa-stash.app"

  caveats do
    "Requires macOS 26.5 or later."
  end
end
