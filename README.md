# Restart ADB

A NextUI Tool Pak that brings adb back on Anbernic H700 devices (RG35XX SP and
friends, NextUI platform `h700`) without a reboot.

Needs [BaseOS](https://github.com/pvaibhav/BaseOS). Stock Anbernic firmware doesn't
ship adbd.

## Why adb "dies"

Usually it doesn't. On disconnect, the sunxi OTG manager clears the adb USB gadget's
UDC binding (`/sys/kernel/config/usb_gadget/g1/UDC`). adbd keeps running, but nothing
binds the gadget again. If adbd itself dies, the kernel clears the binding too. BaseOS
deliberately ships no reconnect helper, so its documented fix is a reboot.

Tested on an RG SP (BaseOS 1.4.0, NextUI 2026-10-13): a real unplug/replug, a cleared
binding and a killed adbd are all fixed by the pak. Sleep/wake with the cable attached
doesn't break adb.

## What it does

1. Checks for BaseOS's `/usr/sbin/usb-gadget-adb`, that `/data/no-adb` isn't set, and
   that `otg_role` reads `usb_device`. Rebinding can't help in host mode, and writing
   `otg_role` hangs the writer, so the pak asks for a replug instead.
2. If the gadget is unbound, re-runs `usb-gadget-adb setup` to rebind it (starting
   adbd first if it died), and waits for the host to enumerate it.
3. If it was still bound, or the rebind didn't take, unbinds, stops adbd and re-runs
   setup, which starts a fresh adbd. The fresh adbd gets the same clean environment
   and `/` cwd as at boot, so adb shells don't inherit NextUI's `PATH` or
   `LD_LIBRARY_PATH`.

The result shows on screen for 3 seconds (B dismisses it): `ADB restarted`,
`ADB restarted (adbd had stopped)` when adbd had died, or a short reason such as
`No USB cable detected` or `No USB host seen, check cable`. Messages use a bundled
[minui-presenter](https://github.com/josegonzalez/minui-presenter) (`h700-nextui`
build, MIT), so they follow the NextUI theme.

## Install

Download `Restart.ADB.pak.zip` from the
[latest release](https://github.com/Pobega/adbd-restart-pak/releases/latest) and unzip it
into `Tools/h700/Restart ADB.pak/` on the NextUI SD card, so you end up with:

```
Tools/h700/Restart ADB.pak/launch.sh
```

It then shows up as **Restart ADB** under Tools.

## Logs

Each run overwrites `.userdata/h700/logs/Restart ADB.txt` on the SD card. It records
adbd's PID and command line, each configfs gadget's UDC binding, UDC state,
`otg_role` and functionfs mounts, before and after the restart, plus which path it
took and the result.

## Development

```sh
make lint   # shellcheck (sh mode) via podman; SHELLCHECK=shellcheck for a local one
make test   # dry-run launch.sh under dash and BusyBox ash (podman)
make bin    # download the pinned minui-presenter into Restart ADB.pak/bin/
make zip    # dist/Restart ADB.pak.zip (runs `make bin`)
make push   # adb push into /mnt/SDCARD/Tools/h700 (runs `make bin`; needs adbd alive)
```

`/bin/sh` on BaseOS is BusyBox ash, so `launch.sh` must stay POSIX.

## Releasing

1. Bump `version` in `pak.json` and add a matching `changelog` entry.
2. Commit, then tag with exactly that version and push the tag:
   ```sh
   git tag v0.1.1 && git push origin v0.1.1
   ```

CI checks that the tag matches `pak.json`, builds the zip, and publishes a release with
`Restart.ADB.pak.zip` attached and the changelog entry as notes. The Pak Store downloads
`{repo_url}/releases/download/{version}/{release_filename}`, so those must line up.

## License

MIT. The bundled minui-presenter is MIT too; its license ships as
`bin/minui-presenter.LICENSE`.
