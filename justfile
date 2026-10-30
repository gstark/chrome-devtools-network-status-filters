default:
    @just --list

# Build the release DevTools frontend into devtools/devtools-frontend/out/Release.
devtools:
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="$PWD/depot_tools:$PATH"
    cd devtools/devtools-frontend
    [[ -f out/Release/args.gn ]] || gn gen out/Release --args='is_debug=false'
    autoninja -C out/Release

# Build a signed "Helium Dev.app" into build/. It holds the release DevTools frontend.
helium-dev-build version="0.1-dev": devtools
    #!/usr/bin/env bash
    set -euo pipefail
    helium=/Applications/Helium.app
    frontend=devtools/devtools-frontend/out/Release/gen/front_end
    app="build/Helium Dev.app"

    if [[ ! -d "$helium" ]]; then
        echo "Helium Dev copies its file and URL associations from $helium. Install Helium first." >&2
        exit 1
    fi
    identity=$(/usr/bin/security find-identity -v -p codesigning \
        | /usr/bin/grep "Apple Development" | /usr/bin/grep -v CSSMERR | /usr/bin/awk '{ print $2; exit }')
    if [[ -z "$identity" ]]; then
        echo "No valid Apple Development certificate found. Add your Apple account in Xcode > Settings > Accounts." >&2
        exit 1
    fi

    /bin/rm -rf "$app"
    /bin/mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/devtools-frontend"
    /usr/bin/xcrun swiftc -O -swift-version 5 -target arm64-apple-macos26.0 \
        -o "$app/Contents/MacOS/Helium Dev" helium-dev/main.swift

    plist="$app/Contents/Info.plist"
    /bin/cp helium-dev/Info.plist "$plist"
    /usr/bin/plutil -replace CFBundleShortVersionString -string "{{version}}" "$plist"
    /usr/bin/plutil -replace CFBundleVersion -string "{{version}}" "$plist"
    # Declare every scheme and file type that Helium declares.
    for key in CFBundleURLTypes CFBundleDocumentTypes UTImportedTypeDeclarations; do
        /usr/bin/plutil -replace "$key" -json "$(/usr/bin/plutil -extract "$key" json -o - "$helium/Contents/Info.plist")" "$plist"
    done
    /bin/cp "$helium/Contents/Resources/app.icns" "$app/Contents/Resources/app.icns"

    # Copy only the files that Chromium packs into its DevTools resources.
    /usr/bin/sed -n 's/.* resource_path="\([^"]*\)".*/\1/p' "$frontend/devtools_resources.grd" \
        | /usr/bin/rsync -a --files-from=- "$frontend/" "$app/Contents/Resources/devtools-frontend/"

    /usr/bin/codesign --force --sign "$identity" "$app"
    echo "Built $app."

# Build Helium Dev, publish a GitHub release, and update the cask in the gstark/tap Homebrew tap.
homebrew:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "The working tree has changes. Commit them first." >&2
        exit 1
    fi

    version="0.1-$(/bin/date +%Y%m%d%H%M)"
    zip="build/Helium-Dev-$version.zip"
    devtools_commit=$(git -C devtools/devtools-frontend rev-parse --short HEAD)
    devtools_branch=$(git -C devtools/devtools-frontend branch --show-current)

    just helium-dev-build "$version"
    /bin/rm -f build/Helium-Dev-*.zip
    /usr/bin/ditto -c -k --keepParent "build/Helium Dev.app" "$zip"
    sha=$(/usr/bin/shasum -a 256 "$zip" | /usr/bin/cut -d' ' -f1)

    git push origin "$(git branch --show-current)"
    gh release create "v$version" "$zip" -R gstark/chrome-devtools-network-status-filters \
        --target "$(git rev-parse HEAD)" \
        --title "Helium Dev $version" \
        --notes "Build of $(git rev-parse --short HEAD), with devtools-frontend $devtools_commit ($devtools_branch)."

    tap_dir=$(brew --repository gstark/tap)
    git -C "$tap_dir" pull --ff-only
    cat > "$tap_dir/Casks/helium-dev.rb" <<EOF
    cask "helium-dev" do
      version "$version"
      sha256 "$sha"

      url "https://github.com/gstark/chrome-devtools-network-status-filters/releases/download/v#{version}/Helium-Dev-#{version}.zip"
      name "Helium Dev"
      desc "Default browser that opens Helium with a custom DevTools frontend"
      homepage "https://github.com/gstark/chrome-devtools-network-status-filters"

      depends_on arch: :arm64
      depends_on macos: :tahoe

      app "Helium Dev.app"

      postflight_steps do
        # The build is signed but not notarized, so remove the quarantine flag to let it open.
        run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{{{appdir}}/Helium Dev.app"]
        # Make Helium Dev the default browser. macOS asks for confirmation.
        run "/usr/bin/open", args: ["-a", "{{{{appdir}}/Helium Dev.app", "--args", "--make-default"]
      end
    end
    EOF
    git -C "$tap_dir" add Casks/helium-dev.rb
    git -C "$tap_dir" commit -m "helium-dev $version"
    git -C "$tap_dir" push

    echo "Released $version. Run 'brew install gstark/tap/helium-dev' to install it."
