# am_scanner

An on-device detector for iOS tracking libraries, intended for jailbroken
devices and privacy research on apps the operator owns a legitimate copy of.
It scans Objective-C class names and app metadata, then matches collected
evidence against a bundled signature list.

This repo is forked from [TrackerControl/trackerscan-ios](https://github.com/TrackerControl/trackerscan-ios)
It adheers to the same license from [TrackerControl/tracker-control-ios](https://github.com/TrackerControl/tracker-control-ios): [LICENSE](https://github.com/TrackerControl/tracker-control-ios/blob/main/LICENSE)

## Build

Requires [Theos](https://theos.dev) with a rootless toolchain:

```sh
make package
# → packages/com.sicksyg.am-scanner_*.deb
```

The package installs the executable at `/var/jb/usr/local/bin/am_scanner`
and signatures at `/var/jb/usr/share/am_scanner/signatures.json`.

## Deploy over USB SSH

The deploy script includes its own `scripts/ios-ssh.sh` helper, so AppMonitor
does not need to be installed first. The helper starts or reuses `iproxy` and
connects using an SSH host alias (default: `ios`):

```sh
scripts/deploy.sh
scripts/deploy.sh --run com.example.app
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

Use `AM_SCANNER_IOS_SSH_HOST` to select a different SSH alias,
`AM_SCANNER_IOS_SSH_SCRIPT` to use another helper, or `--no-build` to reuse
the newest package in `packages/`.

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
