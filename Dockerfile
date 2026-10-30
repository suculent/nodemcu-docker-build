# Base image: ubuntu:22.04.
# Do NOT bump past 22.04. esp-open-sdk's bundled crosstool-NG (1.22, gcc 4.8.5)
# fails to build against the 26.04 host toolchain:
#   configure: error: could not find a working compiler
# Verified working on 22.04 (amd64) 2026-09-17; the old 20.04 pin is no longer needed.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# `apt-get upgrade` pulls in Ubuntu security updates for packages the base image
# already carries; without it they wait for the next ubuntu:22.04 tag refresh.
# The dpkg checks fail the build if libbrotli1 (pulled in by git via libcurl)
# is below the fix for CVE-2026-111497, or if ca-certificates predates the
# 2026-10-20 release that blacklists "emSign ECC Root CA - G3" after the
# eMudhra intermediate compromise (LP: #2171507; Aikido reports it as Certifi).
RUN apt-get update -qq && apt-get upgrade -y -qq && apt-get install -y -qq \
autoconf \
automake \
bash \
bc \
bison \
bzip2 \
flex \
g++ \
gawk \
gcc \
git \
gperf \
help2man \
libexpat-dev \
libtool \
libtool-bin \
make \
ncurses-dev \
python3 \
python3-dev \
sed \
srecord \
texinfo \
unrar-free \
unzip \
wget \
xz-utils \
&& dpkg --compare-versions "$(dpkg-query -W -f='${Version}' libbrotli1)" ge 1.0.9-2ubuntu0.1 \
&& dpkg --compare-versions "$(dpkg-query -W -f='${Version}' ca-certificates)" ge 20260816ubuntu0.22.04.1 \
&& ! test -e /usr/share/ca-certificates/mozilla/emSign_ECC_Root_CA_-_G3.crt \
&& ! test -e /etc/ssl/certs/emSign_ECC_Root_CA_-_G3.pem \
&& apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN ln -s /usr/bin/python3 /usr/bin/python && python -v

RUN git clone https://github.com/davidm/lua-inspect

RUN adduser --system --disabled-password --shell /bin/bash nodemcu

USER nodemcu

WORKDIR /home/nodemcu
RUN git clone --recursive https://github.com/ChrisMacGregor/esp-open-sdk.git

# Pre-seed the newlib tarball and widen crosstool-NG's download timeout.
#
# crosstool-NG 1.22 lists three newlib mirrors in scripts/build/libc/newlib.sh, but
# two of them are unreachable: the {a,b} mirror list is stored in a shell variable,
# and bash performs brace expansion before parameter expansion, so they expand to the
# literal words "{http://mirrors.kernel.org/sourceware/newlib," and
# "ftp://sourceware.org/pub/newlib}". That leaves a single usable mirror, fetched for
# a 15 MB file under a 10s CT_CONNECT_TIMEOUT -- one hiccup fails the whole toolchain
# build (seen on CircleCI 2026-09-17, do_libc_get[newlib.sh@26]).
#
# The version tracks CT_LIBC_NEWLIB_V_2_0_0 in the upstream sample config
# crosstool-NG/samples/xtensa-lx106-elf/crosstool.config; bump both together.
# crosstool-config-overrides is appended to .config after `ct-ng xtensa-lx106-elf`
# and .config is sourced by ct-ng, so these values win over the stock ones.
RUN mkdir -p /home/nodemcu/tarballs && \
    ( wget -q -T 60 -t 5 -O /home/nodemcu/tarballs/newlib-2.0.0.tar.gz \
        https://sourceware.org/pub/newlib/newlib-2.0.0.tar.gz || \
      wget -q -T 60 -t 5 -O /home/nodemcu/tarballs/newlib-2.0.0.tar.gz \
        https://mirrors.kernel.org/sourceware/newlib/newlib-2.0.0.tar.gz ) && \
    echo "49c29e9129325e7c3b221aa829743ddcd796d024440e47c80fc0d6769af72d8a  /home/nodemcu/tarballs/newlib-2.0.0.tar.gz" \
      | sha256sum -c - && \
    printf 'CT_LOCAL_TARBALLS_DIR="/home/nodemcu/tarballs"\nCT_CONNECT_TIMEOUT=60\n' \
      >> /home/nodemcu/esp-open-sdk/crosstool-config-overrides

RUN cd /home/nodemcu/esp-open-sdk/ && make

RUN mkdir /home/nodemcu/nodemcu-firmware
WORKDIR /home/nodemcu/nodemcu-firmware
COPY cmd.sh /home/nodemcu/
CMD /home/nodemcu/cmd.sh
