# dist/: ready-to-use app

| File | Platform | Version |
|---|---|---|
| `HealthBench-Evals-macOS-v0.1.0.zip` | macOS 12 or later, Apple Silicon and Intel (universal) | 0.1.0 |

> **The executables have only been tested on macOS.** Windows and Linux
> builds are checked in CI, but no ready-to-use executables are provided for
> them, and they haven't been tried by hand. Build them from source (see the
> main README).

## Open the app

1. Double-click the zip. Finder unpacks **HealthBench Evals.app** next to it.
2. Optionally, drag it into **Applications**.
3. Double-click **HealthBench Evals.app**.

**If macOS says it can't verify the app:** the app is signed locally, not
with a paid Apple Developer ID, so macOS warns when the zip was downloaded
with a web browser. If you got it with `git clone`, there's no warning. To
open it anyway:
- open **System Settings → Privacy & Security**, scroll down, and click
  **Open Anyway** next to "HealthBench Evals" (macOS 15 and later), or
  Control-click the app → **Open** (macOS 14 and earlier);
- or, in Terminal: `xattr -dr com.apple.quarantine "/path/to/HealthBench Evals.app"`.

The app only connects to the endpoint you enter. Your runs are stored in
`~/Library/Containers/io.github.carlos-dev-research.healthbench/`.

## Make a new zip (maintainers)

```sh
./tool/package_macos.sh
```

The script builds the release app, checks its signature and architectures,
and writes `dist/HealthBench-Evals-macOS-v<version>.zip`, with the version
taken from `pubspec.yaml`. It then checks that the zip unpacks to a valid
app. Commit the new zip, and update the table above.
