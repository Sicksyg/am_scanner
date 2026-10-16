# am_scanner

An on-device detector for iOS tracking libraries, intended for jailbroken
devices and privacy research on apps the operator owns a legitimate copy of.
It scans Objective-C class names and app metadata, then matches collected
evidence against a bundled signature list.

This repo is forked from [TrackerControl/trackerscan-ios](https://github.com/TrackerControl/trackerscan-ios)
It adheers to the same license from [TrackerControl/tracker-control-ios](https://github.com/TrackerControl/tracker-control-ios): [LICENSE](https://github.com/TrackerControl/tracker-control-ios/blob/main/LICENSE)

## Install

Pick the path that fits you. All produce the same package,
`am_scanner_<version>_iphoneos-arm64.deb` (Debian package id `am-scanner`,
rootless jailbreaks only).

### 1. Install a release (no tools needed)

Download the `.deb` and `SHA256SUMS` from the
[GitHub releases](https://github.com/Sicksyg/am_scanner/releases), verify, and
install on the device (or open the `.deb` in Sileo/Zebra):

```sh
shasum -a 256 -c SHA256SUMS
dpkg -i am_scanner_*_iphoneos-arm64.deb     # on the device, as root
```

Or push it over USB SSH with `scripts/deploy.sh --deb <file>` (see below).

### 2. Build from source

Requires [Theos](https://theos.dev/docs/installation) (`THEOS` defaults to
`~/theos`) with an iOS 15+ SDK:

```sh
scripts/build.sh                 # → dist/am_scanner_<version>_iphoneos-arm64.deb
scripts/deploy.sh --build        # build, then install over USB SSH
```

### 3. Maintainers: build a GitHub release

```sh
scripts/build.sh --release       # clean tree only; checksum written
# → dist/am_scanner_<version>_iphoneos-arm64.deb and dist/SHA256SUMS
```

Release checklist: bump `Version` in `control`, commit, tag
(`git tag v<version>`), run the release build, test it on a device, then upload
both files from `dist/` to the GitHub release for that tag (for example with
`gh release create v<version> dist/*`).

The binary is signed with powerful entitlements (`task_for_pid-allow`,
no-sandbox, etc., see `src/entitlements.plist`), so only publish builds you
produced yourself from a tagged commit, and always publish the checksum.

The package installs the executable at `/var/jb/usr/local/bin/am_scanner`
and signatures at `/var/jb/usr/share/am_scanner/signatures.json`.

| Script | Purpose |
| --- | --- |
| `scripts/build.sh [--release]` | Build the `.deb` into `dist/` (never touches a device) |
| `scripts/deploy.sh [--build] [--deb <file>] [--run <id>]` | Install a `.deb` on the device over USB SSH (never builds unless `--build`) |

## Deploy over USB SSH

`scripts/deploy.sh` installs the newest `dist/am_scanner_*.deb` (or the file
given with `--deb`) and verifies it against an adjacent `SHA256SUMS` if
present. It includes its own `scripts/ios-ssh.sh` helper, so AppMonitor
does not need to be installed first. The helper starts or reuses `iproxy` and
connects using an SSH host alias (default: `ios`):

```sh
scripts/deploy.sh
scripts/deploy.sh --build --run com.example.app
scripts/deploy.sh --deb ~/Downloads/am_scanner_0.1.0_iphoneos-arm64.deb
```

Configure that alias in `~/.ssh/config` to point to the phone's SSH service
through `127.0.0.1:2222`, with the appropriate username and authentication.
For example:

```sshconfig
Host ios
    HostName 127.0.0.1
    Port 2222
    User mobile
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

Use the identity and username configured for your device. The first SSH
connection must verify and accept the phone's host key. On macOS, install
`iproxy` with Homebrew's `libusbmuxd` formula:

```sh
brew install libusbmuxd
command -v iproxy
```

The deploy helper looks for `iproxy` on `PATH`; if it is installed elsewhere,
set `AM_SCANNER_IPROXY_PATH` to the full executable path.

Use `AM_SCANNER_IOS_SSH_HOST` to select a different SSH alias or
`AM_SCANNER_IOS_SSH_SCRIPT` to use another helper.

## Usage

```sh
am_scanner --list                       # bundleID<TAB>name<TAB>version
am_scanner --list --json                # app metadata and available icons
am_scanner com.example.app              # matched JSON report
am_scanner --dump com.example.app       # raw evidence, no signature matching
am_scanner --verbose --dump com.example.app
```

The `--list --json` response has an `apps` array. Each entry includes
`bundleID`, `name`, and `version`; when LaunchServices provides a decodable
icon, it also includes base64 `iconData` and `iconFormat` (`png`). Icon fields
are omitted when no usable image is available. The existing tab-separated
`--list` output is unchanged and does not retrieve icons.

```json
{
  "apps": [
    {
      "bundleID": "com.example.app",
      "name": "Example",
      "version": "1.2.3",
      "iconData": "iVBORw0KGgo...",
      "iconFormat": "png"
    }
  ]
}
```

`--dump` returns the raw evidence collected on-device without signature
matching, including class names with their evidence source, framework names,
Info.plist tokens, permissions, bundle metadata, and privacy-manifest
information. JSON is written to stdout. Errors are written to stderr and
return a non-zero exit status. `--verbose` sends diagnostic output to stderr
so JSON stdout can be captured separately.

When the runtime process cannot be spawned, the dump may include a
`runtimeError`. Treat runtime evidence as unavailable or incomplete rather
than interpreting missing runtime classes as evidence that the app contains
no matching SDKs.
