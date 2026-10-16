#!/bin/sh
# Dry-run the pak in a container with the repo mounted at /repo; $1 is the
# shell to run launch.sh with. Run via `make test`.
SHELL_UNDER_TEST="$1"
set -u
SB=/tmp/sb
PAK="$SB/Tools/h700/Restart ADB.pak"
rm -rf "$SB"
mkdir -p "$SB/Tools/h700" "$SB/logs"
cp -r "/repo/Restart ADB.pak" "$SB/Tools/h700/"
export PRESENTER_LOG="$SB/presenter.log"

# Stand-in for the bundled aarch64 minui-presenter. It deliberately ignores
# SIGTERM/SIGINT (like show2.elf effectively did), so a script that waits on a
# polite kill hangs and trips the timeout below.
mkdir -p "$PAK/bin"
cat >"$PAK/bin/minui-presenter" <<'EOF'
#!/bin/sh
echo "$0 $*" >>"$PRESENTER_LOG"
trap '' TERM INT
case "$*" in
*"--timeout -1"*) while :; do sleep 0.1; done ;;
*) sleep 1 ;;
esac
EOF
chmod +x "$PAK/bin/minui-presenter"

# A fake adbd so the pid/cmdline path gets exercised.
if [ -x /bin/busybox ]; then
	# sleep is an applet here; a script keeps comm=adbd for busybox pidof.
	printf '#!/bin/sh\nsleep "$@"\n' >/tmp/adbd
	chmod +x /tmp/adbd
else
	cp "$(command -v sleep)" /tmp/adbd
fi
/tmp/adbd 30 &

fail=0
check() { if eval "$2"; then echo "  ok: $1"; else echo "  FAIL: $1"; fail=1; fi; }

echo "== syntax ($SHELL_UNDER_TEST -n)"
check "parses" "$SHELL_UNDER_TEST -n '$PAK/launch.sh'"

echo "== run from NextUI-style absolute path (PATH has no bin/ of its own)"
( cd / && LOGS_PATH="$SB/logs" SDCARD_PATH="$SB" PATH="/usr/sbin:/usr/bin:/sbin:/bin" \
	timeout 20 "$SHELL_UNDER_TEST" "$PAK/launch.sh" )
rc=$?
check "finished without hanging (rc=$rc)" "[ $rc -eq 0 ]"
LOG="$SB/logs/Restart ADB.txt"
check "log named after pak" "[ -f '$LOG' ]"
check "before+after dumps" "[ \$(grep -c '^=== ' '$LOG') -eq 2 ]"
check "fake adbd pid+cmdline logged" "grep -q 'adbd pids: [0-9]' '$LOG' && grep -q '/tmp/adbd 30' '$LOG'"
check "no-BaseOS result logged" "grep -q 'result: ADB restart needs BaseOS' '$LOG'"
check "presenter found via pak bin/" "head -n1 '$PRESENTER_LOG' | grep -q 'Restart ADB.pak/bin/minui-presenter '"
check "busy screen first, backgrounded" "head -n1 '$PRESENTER_LOG' | grep -q -- '--message Restarting ADB... --timeout -1$'"
check "result screen with 3s timeout" "tail -n1 '$PRESENTER_LOG' | grep -q -- '--message ADB restart needs BaseOS --timeout 3$'"
check "exactly two presenter runs" "[ \$(wc -l <'$PRESENTER_LOG') -eq 2 ]"
sleep 0.3
check "no presenter left running" "! grep -l 'bi[n]/minui-presenter' /proc/[0-9]*/cmdline 2>/dev/null | grep -q ."

echo "== run relative from inside the pak, LOGS_PATH unset"
rm -f "/tmp/Restart ADB.txt"
( cd "$PAK" && unset LOGS_PATH && SDCARD_PATH="$SB" timeout 20 "$SHELL_UNDER_TEST" ./launch.sh )
check "falls back to /tmp/Restart ADB.txt" "[ -f '/tmp/Restart ADB.txt' ]"

echo "== presenter log"
sed 's/^/  | /' "$PRESENTER_LOG"
exit $fail
