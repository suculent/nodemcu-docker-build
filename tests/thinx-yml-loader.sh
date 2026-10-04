#!/bin/sh
#
# thinx.yml loader test: cmd.sh must read thinx.yml without eval.
#
# thinx.yml is repository content, and the THiNX API writes decrypted devsec
# credentials into it before a build. cmd.sh used to run
#   eval $(parse_yaml $WORKDIR/thinx.yml)
# which ran any $(...), backtick or quote break-out in a value as shell inside
# the build container. This test runs cmd.sh's own thinx.yml load step (its
# top-level functions, then the line that loads thinx.yml) on crafted files in
# a temp dir and checks that:
#  - a marker command in a value never runs ($(...), backticks, a quote
#    break-out with ;, list items, names cmd.sh does not read, multi-line);
#  - values reach the variables literally, and only the names cmd.sh reads;
#  - legit thinx.yml layouts give the same values as the old parse_yaml + eval;
#  - loading prints nothing (devsec values are Wi-Fi credentials and keys).
#
# Plain POSIX sh: runs under bash, dash or busybox sh, with any awk. No Docker.
#   sh tests/thinx-yml-loader.sh
# CMD_SH=/path/to/cmd.sh tests another copy.

# Names cmd.sh reads after loading thinx.yml.
# Both are lists: cmd.sh iterates ${name[@]}, so a list arrives as its items
# joined with a space.
NAMES="nodemcu_modules_c nodemcu_modules_lua"
# Names thinx.yml carries that cmd.sh does not read; they must stay unset.
# (cmd.sh compares the literal string "nodemcu_build_float", not the variable.)
UNREAD="devsec_ssid devsec_pass devsec_ckey nodemcu nodemcu_modules
nodemcu_build_float nodemcu_build_type"

HERE=$(cd "$(dirname "$0")" && pwd)
CMD_SH=${CMD_SH:-$HERE/../cmd.sh}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/thinx-yml-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
trap 'exit 1' INT TERM

n=0
failed=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
not_ok() {
	n=$((n + 1)); failed=$((failed + 1))
	echo "not ok $n - $1"
	[ -z "${2-}" ] || echo "#   $2"
}

[ -f "$CMD_SH" ] || { echo "Bail out! no cmd.sh at $CMD_SH"; exit 1; }

# cmd.sh's top-level functions, and the line that loads thinx.yml.
FUNCS=$WORK/functions.sh
awk '/^[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/ { f = 1 } f { print } f && /^}/ { f = 0 }' \
	"$CMD_SH" > "$FUNCS"
LOAD_LINE=$(grep -E '^[[:space:]]*(eval[[:space:]].*parse_yaml|thinx_yml_load[[:space:]])' \
	"$CMD_SH" | head -n 1)

# load DIR: runs the load step on DIR/thinx.yml with DIR as the working
# directory and set -e on. Writes "name=value" or "name unset" for every name
# in NAMES and UNREAD to DIR/vars, and whatever the load step printed to
# DIR/output. The names are this test's own, never read from a yml file.
load() {
	(
		cd "$1" || exit 1
		for name in $NAMES $UNREAD; do unset "$name"; done
		YMLFILE=$1/thinx.yml
		WORKDIR=$1
		. "$FUNCS"
		set -e
		eval "$LOAD_LINE"
		set +e
		for name in $NAMES $UNREAD; do
			if eval "[ -n \"\${$name+set}\" ]"; then
				eval "printf '%s=%s\n' \"\$name\" \"\$$name\""
			else
				printf '%s unset\n' "$name"
			fi
		done > "$1/vars"
	) > "$1/output" 2>&1
}

# newcase NAME: a case directory; thinx.yml comes from stdin. Feed it with a
# here-document or a file, never a pipe: a piped function runs in a subshell
# and CASE would not change.
newcase() {
	CASE=$WORK/$1
	mkdir -p "$CASE"
	cat > "$CASE/thinx.yml"
}

has() { grep -Fqx -- "$1" "$CASE/vars" 2>/dev/null; }

# expect DESC LINE...: after load, every LINE ("name=value" / "name unset")
# is in vars, every other name in NAMES and UNREAD is unset, and nothing was
# printed.
expect() {
	desc=$1; shift
	load "$CASE"
	why=""
	if [ ! -f "$CASE/vars" ]; then
		not_ok "$desc" "the load step failed: $(head -c 300 "$CASE/output")"
		return
	fi
	for line in "$@"; do
		has "$line" || why="$why [missing: $line]"
	done
	for name in $NAMES $UNREAD; do
		listed=no
		for line in "$@"; do
			case "$line" in "$name="*|"$name unset") listed=yes ;; esac
		done
		[ $listed = yes ] || has "$name unset" || why="$why [$name should be unset]"
	done
	[ -s "$CASE/output" ] && why="$why [load printed output]"
	[ -e "$CASE/PWNED" ] && why="$why [MARKER CREATED: thinx.yml content ran as shell]"
	if [ -z "$why" ]; then ok "$desc"; else not_ok "$desc" "$why"; fi
}

# no_marker DESC: after load, no PWNED file exists in the case dir.
no_marker() {
	load "$CASE"
	if [ -e "$CASE/PWNED" ]; then
		not_ok "$1" "marker file created: thinx.yml content ran as shell"
	else
		ok "$1"
	fi
}

echo "# cmd.sh: $CMD_SH"

# --- wiring -------------------------------------------------------------------

code=$(grep -v '^[[:space:]]*#' "$CMD_SH")
if printf '%s\n' "$code" | grep -Eq '(^|[^A-Za-z0-9_])eval([^A-Za-z0-9_]|$)'; then
	not_ok "cmd.sh has no eval" "$(printf '%s\n' "$code" | grep -En '(^|[^A-Za-z0-9_])eval([^A-Za-z0-9_]|$)' | head -n 3)"
else
	ok "cmd.sh has no eval"
fi
if printf '%s\n' "$code" | grep -q 'parse_yaml'; then
	not_ok "cmd.sh has no parse_yaml"
else
	ok "cmd.sh has no parse_yaml"
fi
if printf '%s\n' "$code" | grep -Eq '(^|[;&|[:space:]])(source|\.)[[:space:]][^;&|]*(yml|YML)'; then
	not_ok "cmd.sh does not source thinx.yml"
else
	ok "cmd.sh does not source thinx.yml"
fi
if grep -q '^thinx_yml_load[[:space:]]*()' "$FUNCS" &&
	printf '%s\n' "$LOAD_LINE" | grep -Eq '^[[:space:]]*thinx_yml_load[[:space:]]'; then
	ok "cmd.sh loads thinx.yml with thinx_yml_load"
else
	not_ok "cmd.sh loads thinx.yml with thinx_yml_load" "load line: ${LOAD_LINE:-none}"
fi

# --- nothing in thinx.yml runs --------------------------------------------------

newcase marker-plain-subst <<'EOF'
nodemcu:
  modules:
    c: $(touch PWNED)
EOF
no_marker 'plain $(...) value does not run'
has 'nodemcu_modules_c=$(touch PWNED)' && ok 'plain $(...) value is kept literally' ||
	not_ok 'plain $(...) value is kept literally'

newcase marker-plain-backtick <<'EOF'
nodemcu:
  modules:
    lua: `touch PWNED`
EOF
no_marker 'plain backtick value does not run'
has 'nodemcu_modules_lua=`touch PWNED`' && ok 'plain backtick value is kept literally' ||
	not_ok 'plain backtick value is kept literally'

newcase marker-breakout <<'EOF'
nodemcu:
  modules:
    c: x"); touch PWNED; #
EOF
no_marker 'quote break-out with ; does not run'
has 'nodemcu_modules_c=x"); touch PWNED; #' && ok 'quote break-out is kept literally' ||
	not_ok 'quote break-out is kept literally'

newcase marker-dq <<'EOF'
nodemcu:
  modules:
    c: "$(touch PWNED)"
    lua: "x"); touch PWNED; #"
EOF
no_marker 'double-quoted $(...) and break-out values do not run'
has 'nodemcu_modules_c=$(touch PWNED)' && has 'nodemcu_modules_lua=x"); touch PWNED; #' &&
	ok 'double-quoted values are kept literally' ||
	not_ok 'double-quoted values are kept literally'

newcase marker-list <<'EOF'
nodemcu:
  modules:
    c:
      - file
      - $(touch PWNED)
      - `touch PWNED`
    lua:
      - x"); touch PWNED; #
EOF
no_marker 'list items do not run'
has 'nodemcu_modules_c=file $(touch PWNED) `touch PWNED`' &&
	has 'nodemcu_modules_lua=x"); touch PWNED; #' &&
	ok 'list items are kept literally' ||
	not_ok 'list items are kept literally'

newcase marker-unread <<'EOF'
devsec:
  ssid: "$(touch PWNED)"
  pass: `touch PWNED`
  ckey: x"); touch PWNED; #
nodemcu:
  build_float: $(touch PWNED)
  build_type: `touch PWNED`
EOF
expect 'names cmd.sh does not read neither run nor get set'

newcase marker-multiline <<'EOF'
nodemcu:
  modules:
    c: "x
$(touch PWNED)"
    lua: |
      $(touch PWNED)
EOF
expect 'multi-line values do not run and are rejected'

newcase marker-control < /dev/null
printf 'nodemcu:\n  modules:\n    c: a\001$(touch PWNED)\n    lua:\n      - a\000b\n      - "a\033b"\n' \
	> "$CASE/thinx.yml"
expect 'values with control characters (NUL, ESC, ^A) are rejected'

# --- legit layouts: same values as the old parse_yaml + eval --------------------

# The format in README.md, shortened.
newcase readme <<'EOF'
nodemcu:
  modules:
    c:
      - coap
      - crypto
      - dhtlib
      - esp-gdbstub
      - swTimer
    lua:
      - bh1750
      - ds18b20
      - thinx
EOF
expect 'README.md format: each list joined with a space, as ${name[@]} gave' \
	'nodemcu_modules_c=coap crypto dhtlib esp-gdbstub swTimer' \
	'nodemcu_modules_lua=bh1750 ds18b20 thinx'

newcase devsec <<'EOF'
# Those lines MUST be masked out in ENV prints!
devsec:
  ckey: "fake-ckey-0123456789abcdef"
  ssid: "fake ssid"
  pass: "fake \"pass\" \\ word"
nodemcu:
  build_float: true
  modules:
    c:
      - "file"
      - 'gpio'
    lua: "ds18b20 http"
EOF
expect 'devsec ignored, quoted items, a list as one string' \
	"nodemcu_modules_c=file 'gpio'" 'nodemcu_modules_lua=ds18b20 http'

newcase last-wins <<'EOF'
nodemcu:
  modules:
    lua: first
    lua: second
EOF
expect 'a repeated key: the last one wins' nodemcu_modules_lua=second

newcase crlf < /dev/null
printf 'nodemcu:\r\n  modules:\r\n    c:\r\n      - file\r\n      - gpio\r\n    lua: "a\tb"' \
	> "$CASE/thinx.yml"
expect 'CRLF line ends are dropped, tab is kept, no final newline' \
	'nodemcu_modules_c=file gpio' "$(printf 'nodemcu_modules_lua=a\tb')"

newcase missing-file < /dev/null
rm -f "$CASE/thinx.yml"
expect 'a missing thinx.yml sets nothing'

echo "1..$n"
if [ "$failed" -gt 0 ]; then
	echo "# $failed of $n failed"
	exit 1
fi
echo "# all $n passed"
