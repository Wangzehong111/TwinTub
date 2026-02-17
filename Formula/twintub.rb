# TwinTub Homebrew Formula
#
# RELEASE CHECKLIST:
# 1. Update `version` to match the new release version
# 2. Update `sha256` with the actual checksum from the release
# 3. Replace `YOUR_USERNAME` with the actual GitHub username/org
#
# To get SHA256 for a release:
#   curl -sL https://github.com/YOUR_USERNAME/TwinTub/releases/download/v1.0.0/TwinTub-1.0.0.zip | shasum -a 256

class Twintub < Formula
  desc "macOS Menu Bar app for monitoring Claude Code CLI multi-session status"
  homepage "https://github.com/YOUR_USERNAME/TwinTub"
  version "1.0.0"
  license "MIT"
  head "https://github.com/YOUR_USERNAME/TwinTub.git", branch: "main"

  depends_on :macos => :sonoma

  on_macos do
    url "https://github.com/YOUR_USERNAME/TwinTub/releases/download/v#{version}/TwinTub-#{version}.zip"
    # UPDATE THIS SHA256 BEFORE RELEASE!
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  end

  def install
    prefix.install "TwinTub.app"

    # Install hook scripts
    (prefix/"hooks").install Dir["hooks/*"] if Dir.exist?("hooks")

    # Create a wrapper script for easy access
    (bin/"twintub").write <<~EOS
      #!/bin/bash
      # TwinTub launcher script

      APP_PATH="#{prefix}/TwinTub.app"

      if [ ! -d "$APP_PATH" ]; then
        echo "Error: TwinTub.app not found at $APP_PATH" >&2
        exit 1
      fi

      # Check if already running
      if pgrep -f "TwinTub.app" >/dev/null 2>&1; then
        echo "TwinTub is already running"
        exit 0
      fi

      open "$APP_PATH"
      echo "TwinTub started"
    EOS

    chmod 0755, bin/"twintub"
  end

  def caveats
    <<~EOS
      TwinTub has been installed to:
        #{prefix}/TwinTub.app

      To start TwinTub:
        twintub
      Or open the app directly from your Applications folder.

      First Launch:
        Right-click the app and select "Open" to bypass Gatekeeper.

      Setup Hooks (required for monitoring):
        Run the following command to install Claude Code hooks:
        #{prefix}/hooks/install_hooks.sh

      For more information, visit:
        https://github.com/YOUR_USERNAME/TwinTub
    EOS
  end

  test do
    # Check that the app bundle exists
    assert_predicate prefix/"TwinTub.app", :exist?
    assert_predicate bin/"twintub", :exist?
  end
end
