cask "whoa-stash" do
  version "1"
  sha256 "40b2ae652b36ca16f8b51c98e63a894d158d33383aa6592e29cf3cb9240ba904"

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
