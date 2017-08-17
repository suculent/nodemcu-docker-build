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

# unpack esp-open-sdk.tar.gz in a directory that is NOT the bound mount directory (i.e. inside the Docker image)
cp tools/esp-open-sdk.tar.* ../
cd ..
# support older build chains (before we re-packaged it)
if [ -f ./esp-open-sdk.tar.xz ]; then
  tar -Jxvf esp-open-sdk.tar.xz
else
  tar -zxvf esp-open-sdk.tar.gz
fi

export PATH=$PATH:$PWD/esp-open-sdk/sdk:$PWD/esp-open-sdk/xtensa-lx106-elf/bin
cd nodemcu-firmware

# Parse thinx.yml config

if [[ -f "thinx.yml" ]]; then
  echo "Reading thinx.yml:"
  parse_yaml thinx.yml
  eval $(parse_yaml thinx.yml)

  pushd app
    C_MODULES=$(ls -l */)
    echo "- c-modules: ${nodemcu_modules_c[@]}"
    for module in ${nodemcu_modules_c[@]} do
      if [[ "module" == ".output" ]]; then
        break;
      fi
      if [[ $C_MODULES == "*${module}*"]]; then
        echo "Enabling C module ${module}"
      else
        echo "Disabling C module ${module}"
        rm -rf ${module}
      fi
    done
  popd

  pushd lua_modules
    LUA_MODULES=$(ls -l */)
    echo "- lua-modules: ${nodemcu_modules_lua[@]}"
    for module in ${nodemcu_modules_lua[@]} do
      if [[ $LUA_MODULES == "*${module}*"]]; then
        echo "Enabling LUA module ${module}"
      else
        echo "Disabling LUA module ${module}"
        rm -rf ${module}
      fi
    done
  popd

  done
fi

# make a float build if !only-integer
if [ -z "$INTEGER_ONLY" ]; then
  make clean all
  cd bin
  srec_cat -output nodemcu_float_"${IMAGE_NAME}".bin -binary 0x00000.bin -binary -fill 0xff 0x00000 0x10000 0x10000.bin -binary -offset 0x10000
  # copy and rename the mapfile to bin/
  cp ../app/mapfile nodemcu_float_"${IMAGE_NAME}".map
  cd ../
else
  true
fi

# make an integer build
if [ -z "$FLOAT_ONLY" ]; then
  make EXTRA_CCFLAGS="-DLUA_NUMBER_INTEGRAL" clean all
  cd bin
  srec_cat -output nodemcu_integer_"${IMAGE_NAME}".bin -binary 0x00000.bin -binary -fill 0xff 0x00000 0x10000 0x10000.bin -binary -offset 0x10000
  # copy and rename the mapfile to bin/
  cp ../app/mapfile nodemcu_integer_"${IMAGE_NAME}".map
else
  true
fi
