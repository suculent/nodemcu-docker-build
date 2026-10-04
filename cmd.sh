#!/usr/bin/env bash

set -e

# --- thinx.yml ----------------------------------------------------------------
#
# thinx.yml is repository content, and the THiNX API writes decrypted devsec
# credentials into it before a build. It is read here and never eval'd or
# sourced: the old `eval $(parse_yaml ...)` ran any $(...), backtick or quote
# break-out in a value as shell, in a container that may hold docker.sock.
#
# thinx_yml_load FILE assigns, with plain `name=$value` assignments, only the
# names this script reads:
#   nodemcu_modules_c nodemcu_modules_lua
# Any other name is ignored. Nothing is exported and nothing is printed.
#
# Names follow the old parse_yaml: the parent keys joined with "_" (two spaces
# of indent per level), e.g. nodemcu: / modules: / c: -> nodemcu_modules_c.
# Values:
#  - key: "..."  quotes dropped; \" and \\ decoded (the escapes eval used to
#    decode the same way); any other backslash stays as it is;
#  - - "..."     a double-quoted list item: the same;
#  - key: ...    taken as written: $, `, ;, \ and quotes stay literal;
#  - a trailing CR (CRLF files) is dropped;
#  - a value that continues on the next line (block scalar |/>, folded plain
#    or multi-line quoted scalar) or holds a control character other than
#    tab (NUL included) is rejected; its variable is left as it was.
# A list item (`- item` under a key) used to append to a bash array, and this
# script expands ${name[@]}. A list item now appends to the value after a
# space, so c: with the items "- A" and "- B" gives nodemcu_modules_c="A B";
# ${name[@]} of that string expands to the same words the array did, both
# unquoted in the for loops and quoted in the echo lines. A plain key value
# replaces the list so far, as `name=(...)` did.
#
# Same awk as thinx_yml_load in the THiNX worker (services/worker/builder-lib.sh)
# and the arduino, platformio and micropython builder images; keep them in step.
# A missing FILE sets nothing. Returns 0.
thinx_yml_load()
{
	[ -f "$1" ] || return 0

	thinx_yml_pairs=$(tr '\000' '\001' < "$1" | awk '
		function unescape_dq(s,    out, i, n, c, d) {
			out = ""
			n = length(s)
			for (i = 1; i <= n; i++) {
				c = substr(s, i, 1)
				if (c == "\\" && i < n) {
					d = substr(s, i + 1, 1)
					if (d == "\\" || d == "\"") {
						out = out d
						i++
						continue
					}
				}
				out = out c
			}
			return out
		}
		function flush() {
			if (pending != "") print pending
			pending = ""
		}
		{
			line = $0
			sub(/\r$/, "", line)
			match(line, /^[ \t]*/)
			ind = substr(line, 1, RLENGTH)
			rest = substr(line, RLENGTH + 1)
			match(rest, /^[A-Za-z0-9_]*/)
			key = substr(rest, 1, RLENGTH)
			rest = substr(rest, RLENGTH + 1)

			if (rest ~ /^[ \t]*:[ \t]*".*"[ \t]*$/) {
				style = "dq"
			} else if (rest ~ /^[ \t]*[:-]/) {
				style = "plain"
			} else {
				# Not a key line. Blank lines and comments are skipped;
				# anything else continues the previous value, which is
				# then multi-line and rejected.
				if (line !~ /^[ \t]*(#.*)?$/) pending = ""
				next
			}

			flush()

			indent = length(ind) / 2
			vname[indent] = key
			for (i in vname) { if (i > indent) { delete vname[i] } }

			value = rest
			if (style == "dq") {
				sub(/^[ \t]*:[ \t]*"/, "", value)
				sub(/"[ \t]*$/, "", value)
				value = unescape_dq(value)
			} else {
				sub(/^[ \t]*[:-][ \t]*/, "", value)
				if (value ~ /^".*"[ \t]*$/) {
					# - "item": eval dropped these quotes too.
					sub(/[ \t]*$/, "", value)
					value = unescape_dq(substr(value, 2, length(value) - 2))
				}
			}

			if (length(value) == 0) next
			if (style == "plain" && value ~ /^[|>][-+0-9]*[ \t]*$/) next

			tabless = value
			gsub(/\t/, "", tabless)
			if (tabless ~ /[[:cntrl:]]/) next

			vn = ""
			for (i = 0; i < indent; i++) { vn = (vn)(vname[i])("_") }
			name = vn key
			# A trailing "_" is a list item: the old parse_yaml made it "+=".
			op = "="
			if (sub(/_$/, "", name)) op = "+="
			if (name !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next

			pending = name op value
		}
		END { flush() }
	')

	# The here-document expands $thinx_yml_pairs once; its text is not
	# expanded again, and each value is assigned, never evaluated.
	# A list item appends after a space; any other value replaces (see above).
	while IFS= read -r thinx_yml_line
	do
		thinx_yml_name=${thinx_yml_line%%=*}
		thinx_yml_value=${thinx_yml_line#*=}
		thinx_yml_append=
		case "$thinx_yml_name" in
			*+) thinx_yml_append=1; thinx_yml_name=${thinx_yml_name%+} ;;
		esac
		case "$thinx_yml_name" in
			nodemcu_modules_c)
				[ -n "$thinx_yml_append" ] || nodemcu_modules_c=
				nodemcu_modules_c=${nodemcu_modules_c:+$nodemcu_modules_c }$thinx_yml_value ;;
			nodemcu_modules_lua)
				[ -n "$thinx_yml_append" ] || nodemcu_modules_lua=
				nodemcu_modules_lua=${nodemcu_modules_lua:+$nodemcu_modules_lua }$thinx_yml_value ;;
		esac
	done <<THINX_YML_PAIRS
$thinx_yml_pairs
THINX_YML_PAIRS

	unset thinx_yml_pairs thinx_yml_line thinx_yml_name thinx_yml_value thinx_yml_append
	return 0
}

# Config options you may pass via Docker like so 'docker run -e "<option>=<value>"':
# - IMAGE_NAME=<name>, define a static name for your .bin files
# - INTEGER_ONLY=1, if you want the integer firmware
# - FLOAT_ONLY=1, if you want the floating point firmware

# use the Git branch and the current time stamp to define image name if IMAGE_NAME not set
if [ -z "$IMAGE_NAME" ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD | sed -r 's/[\/\\]+/_/g')"
  BUILD_DATE="$(date +%Y%m%d-%H%M)"
  IMAGE_NAME=${BRANCH}_${BUILD_DATE}
else
  true
fi

export WORKDIR=$(pwd)
echo "Workdir: ${WORKDIR}"

export PATH=/home/nodemcu/esp-open-sdk/xtensa-lx106-elf/bin:$PATH

echo "Changing directory to pre-build /opt/nodemcu-firmware folder:"
cd /opt/nodemcu-firmware
pwd
ls

# Parse thinx.yml config

if [[ -f "$WORKDIR/thinx.yml" ]]; then
  thinx_yml_load "$WORKDIR/thinx.yml"
  pushd /opt/nodemcu-firmware/app

  C_MODULES=$(ls -l */)
  echo "- c-modules: ${nodemcu_modules_c[@]}"

  for module in ${nodemcu_modules_c[@]}; do
    if [[ "module" == ".output" ]]; then
      break;
    fi
    if [[ $C_MODULES == "*${module}*" ]]; then
      echo "Enabling C module ${module}"
    else
      echo "SHOULD Disable C module ${module} but ALSO EDIT MAKEFILE!"
      # rm -rf ${module}
    fi
  done

  if [[ nodemcu_build_float == true ]]; then
    FLOAT_ONLY=true
  fi
  if [[ nodemcu_build_float == false ]]; then
    INTEGER_ONLY=true
  fi

  popd

  echo "Entering modules.."
  pwd
  ls

  pushd /opt/nodemcu-firmware/lua_modules

  MODULES=$(ls -l */)
  echo "- lua-modules: ${nodemcu_modules_lua[@]}"

  for module in ${nodemcu_modules_lua[@]}; do
    if [[ $MODULES == "*${module}*" ]]; then
      echo "Enabling Lua module ${module}"
    else
      echo "SHOULD Disable Lua module ${module} but ALSO EDIT MAKEFILE!"
      # rm -rf ${module}
    fi
  done

  popd

fi

# make a float build if !only-integer
if [ -z "$INTEGER_ONLY" ]; then
  make clean all
  RESULT=$?
  cd bin
  srec_cat -output nodemcu_float_"${IMAGE_NAME}".bin -binary 0x00000.bin -binary -fill 0xff 0x00000 0x10000 0x10000.bin -binary -offset 0x10000
  RESULT=$?
  # copy and rename the mapfile to bin/
  cp ../app/mapfile nodemcu_float_"${IMAGE_NAME}".map
  cd ../
else
  true
fi

# make an integer build
if [ -z "$FLOAT_ONLY" ]; then
  make EXTRA_CCFLAGS="-DLUA_NUMBER_INTEGRAL" clean all
  RESULT=$?
  cd bin
  srec_cat -output nodemcu_integer_"${IMAGE_NAME}".bin -binary 0x00000.bin -binary -fill 0xff 0x00000 0x10000 0x10000.bin -binary -offset 0x10000
  RESULT=$?
  # copy and rename the mapfile to bin/
  cp ../app/mapfile nodemcu_integer_"${IMAGE_NAME}".map
else
  true
fi

echo ""

# Report build status using logfile
if [[ $RESULT == 0 ]]; then
  echo "THiNX BUILD SUCCESSFUL."
else
  echo "THiNX BUILD FAILED: $?"
fi
