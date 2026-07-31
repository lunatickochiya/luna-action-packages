#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BINARY="$PROJECT_DIR/fancontrol/src/fancontrol"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fancontrol-test.XXXXXX")
SYSFS_ROOT="$TEST_ROOT/sys"
STATUS_FILE="$TEST_ROOT/fancontrol.status"
PWM_FILE="$SYSFS_ROOT/class/hwmon/hwmon7/pwm1"
ENABLE_FILE="$SYSFS_ROOT/class/hwmon/hwmon7/pwm1_enable"
TEMP_FILE="$SYSFS_ROOT/class/thermal/thermal_zone0/temp"
DAEMON_PID=""

cleanup() {
	if [ -n "$DAEMON_PID" ]; then
		kill "$DAEMON_PID" 2>/dev/null || true
		wait "$DAEMON_PID" 2>/dev/null || true
	fi
	rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_file_value() {
	file="$1"
	expected="$2"
	actual=$(tr -d '\r\n' < "$file")
	[ "$actual" = "$expected" ] ||
		fail "$file: expected $expected, got $actual"
}

run_once() {
	temperature="$1"
	expected="$2"
	printf '%s\n' "$temperature" > "$TEMP_FILE"
	printf '%s\n' 17 > "$PWM_FILE"
	printf '%s\n' 2 > "$ENABLE_FILE"
	FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" \
	FANCONTROL_STATUS_FILE="$STATUS_FILE" \
		"$BINARY" -1 -k 0 -K 0
	assert_file_value "$PWM_FILE" "$expected"
	assert_file_value "$ENABLE_FILE" 1
}

wait_for_value() {
	file="$1"
	expected="$2"
	attempt=0
	while [ "$attempt" -lt 30 ]; do
		[ -r "$file" ] && [ "$(tr -d '\r\n' < "$file")" = "$expected" ] && return 0
		attempt=$((attempt + 1))
		sleep 0.1
	done
	fail "$file did not become $expected"
}

[ -x "$BINARY" ] || fail "build fancontrol before running this test"

mkdir -p "$SYSFS_ROOT/class/thermal/thermal_zone0"
mkdir -p "$SYSFS_ROOT/class/hwmon/hwmon0"
mkdir -p "$SYSFS_ROOT/class/hwmon/hwmon7"
printf '%s\n' cpu-thermal > "$SYSFS_ROOT/class/thermal/thermal_zone0/type"
printf '%s\n' generic-controller > "$SYSFS_ROOT/class/hwmon/hwmon0/name"
printf '%s\n' 99 > "$SYSFS_ROOT/class/hwmon/hwmon0/pwm1"
printf '%s\n' pwmfan > "$SYSFS_ROOT/class/hwmon/hwmon7/name"
printf '%s\n' 0 > "$SYSFS_ROOT/class/hwmon/hwmon7/fan1_input"

run_once 44000 0
run_once 45000 64
run_once 65000 159
run_once 85000 255
assert_file_value "$SYSFS_ROOT/class/hwmon/hwmon0/pwm1" 99

printf '%s\n' invalid > "$TEMP_FILE"
printf '%s\n' 0 > "$PWM_FILE"
FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" \
FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -1 -k 0 -K 0
assert_file_value "$PWM_FILE" 255

printf '%s\n' 45000 > "$TEMP_FILE"
printf '%s\n' 0 > "$PWM_FILE"
FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" \
FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -k 0 -K 0 -i 1 -q 0 &
DAEMON_PID=$!
wait_for_value "$PWM_FILE" 64
printf '%s\n' 44000 > "$TEMP_FILE"
sleep 2
assert_file_value "$PWM_FILE" 64
printf '%s\n' 42000 > "$TEMP_FILE"
wait_for_value "$PWM_FILE" 0
kill "$DAEMON_PID"
wait "$DAEMON_PID"
DAEMON_PID=""

# Systems without thermal zones may expose temperatures through hwmon only.
rm -rf -- "$SYSFS_ROOT/class/thermal"
printf '%s\n' cpu_sensor > "$SYSFS_ROOT/class/hwmon/hwmon0/name"
printf '%s\n' 45000 > "$SYSFS_ROOT/class/hwmon/hwmon0/temp1_input"
printf '%s\n' 0 > "$PWM_FILE"
FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" \
FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -1 -k 0 -K 0
assert_file_value "$PWM_FILE" 64

# A thermal cooling state is an index, so accepting it would lose PWM resolution.
mkdir -p "$SYSFS_ROOT/class/thermal/cooling_device0"
printf '%s\n' 0 > "$SYSFS_ROOT/class/thermal/cooling_device0/cur_state"
if FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" \
	FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -1 -T "$SYSFS_ROOT/class/hwmon/hwmon0/temp1_input" \
	-F "$SYSFS_ROOT/class/thermal/cooling_device0/cur_state"; then
	fail "cooling_device cur_state was accepted as a PWM output"
fi

printf '%s\n' "All fancontrol tests passed"
