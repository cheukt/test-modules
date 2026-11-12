# test-modules

`test-module`: a registry module whose startup, first run and packages can be made slow or broken. It exercises module status in the app (APP-17645).

It provides one model, `<namespace>:test-module:noop`, which is a generic service that does nothing.

## Versions

| Version | Package | Use it for |
| --- | --- | --- |
| `0.1.0` | normal | baseline, new module, slow start, crashes |
| `0.2.0` | normal | upgrading from 0.1.0 |
| `0.3.0` | about 300 MB of padding | download progress |
| `0.4.0` | truncated tarball | package failed |
| `0.5.0` | only the other platform (amd64 when you target arm64) | unavailable version |
| `0.6.0`, `0.7.0` | include `first_run.sh` | first run; two copies give two fresh runs |

Pin an exact version in the machine config. `latest` resolves to the newest version, `0.7.0`, which has a first run.

## Env vars

Set these in the module config's `env`.

| Var | Effect |
| --- | --- |
| `START_DELAY_SEC=30` | sleep before serving (Starting) |
| `CRASH_ON_START=1` | exit 1 before serving (Failed, crash loop) |
| `CRASH_AFTER_SEC=60` | serve, then exit 1 after N seconds (Ready → Failed, crash loop with Ready gaps) |
| `LOG_ERROR_INTERVAL_SEC=5` | log a module error every N seconds, including while starting |
| `FIRST_RUN_DELAY_SEC=60` | `0.6.0`/`0.7.0`: first run sleeps first |
| `FIRST_RUN_FAIL=1` | `0.6.0`/`0.7.0`: first run exits 1 |

viam-server only re-runs a first run that failed. To repeat one that succeeded, switch to the other first-run version, or delete `~/.viam/packages/data/module/*test-module*<version>*.first_run_succeeded` on the machine.

## Resource attributes

| Attribute | Effect |
| --- | --- |
| `"fail_build": true` | the constructor returns an error; the module stays Ready |
| `"crash_on_build": true` | the constructor exits the module process (one bad resource crash-loops its module) |
| `"build_delay_sec": 30` | the constructor sleeps first |
| `"close_delay_sec": 30` | `Close` sleeps, so removing or upgrading the module shows Closing |
| `"error_log_interval_sec": 5` | log a resource error every N seconds while it runs |

Attribute changes rebuild the resource, so `close_delay_sec` also delays each save.

Durations can be fractions of a second. Some useful extremes:

- `build_delay_sec` over 120 times out the resource build (`VIAM_RESOURCE_CONFIGURATION_TIMEOUT`, default 2m) while the module stays Ready.
- `START_DELAY_SEC` over 300 times out module startup (`VIAM_MODULE_STARTUP_TIMEOUT`, default 5m) without a crash.
- `error_log_interval_sec: 0.1` floods errors, to test the "99+" count.

## DoCommand

`{"crash": true}` exits the module right away, so you can trigger Failed without saving config.

## Upload

Do this once: log in with a CLI profile for each environment. This uses OAuth and leaves your default login alone.

```sh
viam --profile staging --base-url https://app.viam.dev:443 login
viam --profile prod --base-url https://app.viam.com:443 login
```

API-key profiles also work: `viam profiles add --profile-name staging --key-id <id> --key <key>`.

Then build and upload. The script creates the module if it doesn't exist yet.

```sh
./upload.sh --namespace <org-namespace> --env staging
./upload.sh --namespace <org-namespace> --env prod --versions 1,3 --platform linux/amd64
```

The module is `public_unlisted` by default, so any org can use it by ID, but it doesn't show in search. Pass `--visibility private` to keep it to your org. Each upload reapplies the visibility.

Run `./upload.sh` with no arguments to see every option, including `--dry-run`. A version number can only be uploaded once. To upload the set again, use `--major 1` to get `1.x.0`.

## Machine config

```json
{
  "modules": [
    {
      "type": "registry",
      "name": "test-module",
      "module_id": "<namespace>:test-module",
      "version": "0.1.0",
      "env": { "START_DELAY_SEC": "30" }
    }
  ],
  "services": [
    {
      "name": "noop",
      "api": "rdk:service:generic",
      "model": "<namespace>:test-module:noop"
    }
  ]
}
```
