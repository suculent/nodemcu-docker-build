#!/usr/bin/env bash

set -e

parse_yaml() {
    local prefix=$2
    local s
    local w
    local fs
    s='[[:space:]]*'
    w='[a-zA-Z0-9_]*'
    fs="$(echo @|tr @ '\034')"
    sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$1" |
    awk -F"$fs" '{
    indent = length($1)/2;
    vname[indent] = $2;
    for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            printf("%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, $3);
        }
    }' | sed 's/_=/+=/g'
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
  eval $(parse_yaml $WORKDIR/thinx.yml)
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
