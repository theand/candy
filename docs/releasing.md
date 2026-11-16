# Releasing Candy

## Local fork DMG

The `theand-fork` branch builds `Candy-theand-fork.app` with its own bundle ID.
Use the shared project-local `ciao-package-macos-dmg` skill for DMG creation
and installation; no separate project skill is needed. Its packaging script
can be run from this repository after a fresh Release build:

```sh
build_version="$(date +%Y%m%d.%H%M)"
CANDY_BUILD_VERSION="$build_version" scripts/build-app.sh
bash .agents/skills/ciao-package-macos-dmg/scripts/package_dmg.sh \
  --app dist/Candy-theand-fork.app
```

Add `--overwrite` only to intentionally replace the same versioned DMG.
Install that exact DMG once with the shared installer:

```sh
bash .agents/skills/ciao-package-macos-dmg/scripts/install_from_dmg.sh \
  --dmg "<generated-dmg>" --dest /Applications/Candy-theand-fork.app
```

The installer verifies the mounted image, safely replaces the previous app via
Trash, compares the complete installed bundle, and launches the exact path.
Reuse those results; no extra mount, signature/hash pass, or source rebuild.
Never use `/Applications/Candy.app`, the upstream Homebrew destination.
Local builds are ad-hoc signed; DMG packaging does not notarize them.

### Build dependencies and routine checks

`scripts/build-app.sh` runs one Cargo build for the CLI and FFI library, then
SwiftPM, then bundle assembly and signing. Cargo already builds independent
crates in parallel. Swift links `target/<profile>/libcandy_ffi.a` (or the
`CARGO_TARGET_DIR` equivalent); keep Rust → Swift linking in that order. Do not
start a second Cargo build for the CLI or split Swift compilation/linking just
for packaging. SwiftPM handles its own compilation jobs.

The local fork flow uses the build script's plist/signature checks and the
shared packager/installer checks once each. Rust/Swift tests, clippy, dependency
audits, GUI checks and `scripts/release.sh` belong to implementation or explicit
public-release work; do not add them to a routine personal DMG run. Skip
Gatekeeper assessment for this known unnotarized build unless requested.

Finish the shared skill's copy/hash and eligible tag steps, then run its
project-scoped cache cleanup last. Keep caches throughout build, packaging and
installation; cleanup may remove `target/` and `macos/.build/` after the verified
shared DMG exists. The public distribution procedure below is a separate flow.

## Public distribution

Releases currently target **Apple Silicon on macOS 14+**. Build on an Apple
Silicon Mac with Rust 1.100+ and Xcode 16+ (Swift 6). The fork's exact Rust
toolchain is pinned in `rust-toolchain.toml`. CI checks source builds;
the maintainer's Mac signs and notarizes public release artifacts.

## One-time authentication

Install a Developer ID Application certificate and its private key in the login
keychain. `security find-identity -v -p codesigning` should list it. A development
or App Store distribution certificate is not a substitute.

Reuse an existing notarytool profile for the same Apple developer team. The
maintainer currently uses `vimdow-notary`, shared with Vimdow. Profile names
are local references, not passwords, and need not match the application name.

To set up a new profile, create an app-specific password at account.apple.com
and run this interactively in your own terminal:

```sh
xcrun notarytool store-credentials candy-notary
```

Enter the Apple ID, developer Team ID, and app-specific password when prompted.
Do not commit credentials or put passwords in command arguments or chat.
Check the stored profile with:

```sh
xcrun notarytool history --keychain-profile candy-notary
```

## Build and verify

1. Update `workspace.package.version` in `Cargo.toml` and refresh `Cargo.lock`.
   The app's marketing and build versions derive from the CLI package version.
2. Write `docs/releases/<version>.md` and commit all release changes.
3. Run from a clean working tree:

   ```sh
   NOTARY_PROFILE=vimdow-notary scripts/release.sh
   ```

   If multiple Developer ID certificates exist, also set `SIGNING_IDENTITY`
   to the chosen certificate hash. The script runs Rust and Swift checks, builds
   the app, signs the CLI and GUI with hardened runtime and secure timestamps,
   submits to Apple, staples the accepted ticket, and verifies Gatekeeper.
   Keychain and native Vision access require a normal macOS session.
   If a newer Xcode's Swift Build engine stalls while generating its SDK stat
   cache, prefix the command with `CANDY_SWIFT_BUILD_SYSTEM=native` to select
   SwiftPM's native build engine for this release process. The same builds and
   tests still run; this does not change the system's Xcode settings.
4. Outputs are in `dist/releases/<version>/`: the signed `Candy-theand-fork.app`,
   `Candy-theand-fork-<version>-macos-arm64.zip`, `SHA256SUMS`, and Apple's submission result.
   Only the ZIP and checksum file are published. The ordinary `dist/Candy-theand-fork.app`
   remains an ad-hoc signed development build.
5. Unzip the final ZIP into a temporary directory and verify its signature and
   ticket. Test launch, CLI version, an image edit, and text detection. Check
   `otool -L` on both executables for dependencies outside system libraries.
   `scripts/release.sh` also refuses to ship a binary carrying an rpath outside the
   system libraries and the bundle itself; such a load command path does not exist
   on a user's Mac and makes Gatekeeper report the app as unverifiable malware on
   first launch.
6. Note the ZIP size (`ls -l`), the app size (`du -sh`) and an empty window's
   memory (`footprint -p <pid>`, the `phys_footprint` line) for the release
   notes if they changed meaningfully. The website and social cards state no
   figures on purpose, so nothing there needs syncing with a build.

## Publish

Tag the exact commit used to build the verified artifact. Never replace assets
of an already published version; ship a new patch version instead.

```sh
git tag -a v0.1.0 -m "Candy 0.1.0"
git push origin main v0.1.0
gh release create v0.1.0 --verify-tag --title "Candy 0.1.0" \
  --notes-file docs/releases/0.1.0.md \
  dist/releases/0.1.0/Candy-theand-fork-0.1.0-macos-arm64.zip \
  dist/releases/0.1.0/SHA256SUMS
```

The following Homebrew and website steps describe upstream publication, not
local fork installation.

In `rath/homebrew-tap`, update `Casks/candy.rb` with the version and ZIP's SHA-256.
The Cask installs `Candy.app` and links `Contents/Helpers/candy` into Homebrew's
bin directory. Keep the ARM architecture and macOS Sonoma requirements.
Run Cask style/audit and installation checks, commit, and push. Its CI verifies
the packaged version, architecture, signature, notarization and a CLI edit.

Once the release is public, point the website's download links at the new ZIP:
the hero button, the installation link and the JSON-LD `downloadUrl` in
`site/index.html`, `site/ko/index.html` and `site/ja/index.html` use
`https://github.com/rath/candy/releases/download/v<version>/Candy-<version>-macos-arm64.zip`
so the button downloads directly. Change them only after `gh release create`;
an earlier push would publish a link to a missing asset.

Update all three website languages and README installation instructions when needed.
Pushing `main` publishes committed website changes (see
[website maintenance](website.md)). Finally verify the public release assets, tap
installation, and https://candy.told.me/ in all three languages.
