# do not upgrade, causes issues with crosstool-ng
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y -qq \
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
&& apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN git clone https://github.com/davidm/lua-inspect

RUN adduser --system --disabled-password --shell /bin/bash nodemcu

USER nodemcu

WORKDIR /home/nodemcu
RUN git clone --recursive https://github.com/ChrisMacGregor/esp-open-sdk.git --branch fix-ubuntu-21.10-build
RUN cd /home/nodemcu/esp-open-sdk/ && make

RUN mkdir /home/nodemcu/nodemcu-firmware
WORKDIR /home/nodemcu/nodemcu-firmware
COPY cmd.sh /home/nodemcu/
CMD /home/nodemcu/cmd.sh
