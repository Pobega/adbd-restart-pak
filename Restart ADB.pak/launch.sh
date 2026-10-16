#!/bin/sh
# Restart ADB: bring adb back without rebooting the device.
#
# Needs BaseOS, whose usb-gadget-adb sets up the adb USB gadget at boot (stock
# Anbernic firmware has no adbd). /bin/sh there is BusyBox ash, so keep this
# POSIX.

cd "$(dirname "$0")" || exit 1
PAK_NAME="$(basename "$PWD" .pak)"

LOG_DIR="${LOGS_PATH:-/tmp}"
mkdir -p "$LOG_DIR"
exec >"$LOG_DIR/$PAK_NAME.txt" 2>&1

# minui-presenter (the h700-nextui build) is bundled in bin/ by `make bin`.
export PATH="$PWD/bin:$PATH"

GADGET=/sys/kernel/config/usb_gadget/g1
GADGET_SETUP=/usr/sbin/usb-gadget-adb
# Reading otg_role is safe. Never write it (the writer hangs forever in D
# state), and never read usb_device/usb_host/usb_null next to it: reading
# those switches (or wedges) the USB port.
OTG_ROLE=/sys/devices/platform/soc/usbc0/otg_role

# Dump what we can see of adbd and the USB gadget, for debugging.
log_state() {
	echo "=== $1 ($(date))"
	pids="$(pidof adbd)"
	echo "adbd pids: ${pids:-none}"
	for pid in $pids; do
		echo "  $pid: $(tr '\0' ' ' <"/proc/$pid/cmdline")"
	done
	# An empty UDC with adbd still running means the gadget lost its binding.
	for gadget in /sys/kernel/config/usb_gadget/*; do
		[ -e "$gadget/UDC" ] && echo "gadget $(basename "$gadget") UDC: '$(cat "$gadget/UDC")'"
	done
	for udc in /sys/class/udc/*; do
		[ -e "$udc/state" ] && echo "udc $(basename "$udc"): $(cat "$udc/state")"
	done
	echo "otg_role: $(cat "$OTG_ROLE" 2>/dev/null)"
	[ -e /data/no-adb ] && echo "/data/no-adb exists (BaseOS ADB toggle is off)"
	echo "functionfs mounts:"
	grep -i functionfs /proc/mounts
	return 0
}

# BaseOS's gadget setup composes the gadget, starts adbd if it isn't running
# and binds the UDC (retrying ~10s); it's a no-op if already bound. Run it with
# the environment and cwd adbd gets at boot, so a fresh adbd doesn't hand
# NextUI's PATH/LD_LIBRARY_PATH, or a cwd on the SD card, to every adb shell.
gadget_setup() {
	(cd / && env -i HOME=/ PATH=/sbin:/usr/sbin:/bin:/usr/bin SHELL=/bin/sh \
		USER=root TERM=vt102 "$GADGET_SETUP" setup)
}

# Wait up to $1 seconds for the host to enumerate the gadget.
wait_configured() {
	n=0
	while [ "$n" -lt "$1" ]; do
		for udc in /sys/class/udc/*; do
			[ "$(cat "$udc/state" 2>/dev/null)" = configured ] && return 0
		done
		sleep 1
		n=$((n + 1))
	done
	return 1
}

# Sets SUCCESS or FAILURE to a short message for the screen.
restart_adbd() {
	SUCCESS="ADB restarted"
	if [ ! -x "$GADGET_SETUP" ]; then
		FAILURE="ADB restart needs BaseOS"
		return 1
	fi
	if [ -e /data/no-adb ]; then
		FAILURE="ADB is disabled (/data/no-adb)"
		return 1
	fi
	# Rebinding can't help once the port has picked another role, and forcing
	# it back hangs the writer. Only a replug or a reboot fixes that. With no
	# cable plugged in, the role reads "none".
	role="$(cat "$OTG_ROLE" 2>/dev/null)"
	case "$role" in
	"" | usb_device) ;;
	none)
		FAILURE="No USB cable detected"
		return 1
		;;
	usb_host)
		FAILURE="USB is in host mode, replug"
		return 1
		;;
	*)
		FAILURE="USB role is $role, replug"
		return 1
		;;
	esac

	# The usual failure: the OTG manager clears the UDC binding on disconnect
	# while adbd keeps running. The kernel also clears it if adbd dies. Re-running
	# setup rebinds, starting adbd first if it isn't running.
	if [ -z "$(cat "$GADGET/UDC" 2>/dev/null)" ]; then
		echo "restart_adbd: gadget unbound, rebinding"
		pidof adbd >/dev/null || SUCCESS="ADB restarted (adbd had stopped)"
		gadget_setup
		wait_configured 5 && return 0
	fi

	# Still bound, or the rebind didn't take: restart adbd itself.
	echo "restart_adbd: restarting adbd"
	echo "" >"$GADGET/UDC" 2>/dev/null
	for pid in $(pidof adbd); do
		kill "$pid"
	done
	n=0
	while pidof adbd >/dev/null && [ "$n" -lt 5 ]; do
		sleep 1
		n=$((n + 1))
	done
	for pid in $(pidof adbd); do
		kill -9 "$pid"
	done
	gadget_setup
	wait_configured 10 && return 0

	FAILURE="No USB host seen, check cable"
	return 1
}

minui-presenter --message "Restarting ADB..." --timeout -1 &
BUSY_PID=$!

log_state before
if restart_adbd; then
	RESULT="$SUCCESS"
else
	RESULT="$FAILURE"
fi
echo "result: $RESULT"
log_state after

# SIGKILL, not SIGTERM: minui-presenter only installs its SIGTERM handler after
# starting graphics, so an early SIGTERM can be swallowed by SDL and leave this
# script waiting forever. Its handler just calls exit(), so nothing is lost.
kill -9 "$BUSY_PID" 2>/dev/null
wait "$BUSY_PID" 2>/dev/null
# Closes after 3s, or on B.
minui-presenter --message "$RESULT" --timeout 3

# The log lives on the FAT SD card; flush it in case the user reboots next.
sync
