cask "whoa-stash" do
  version "1.0"
  sha256 "c4fcade1239bd4df46dbbdb4f04f2626541d18deaceaed98057671d5faea25ee"

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
