FROM ubuntu
MAINTAINER suculent@me.com

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y srecord bc xz-utils \
    make unrar-free autoconf automake libtool libtool-bin gcc g++ gperf \
    flex bison texinfo gawk ncurses-dev libexpat-dev python-dev python python-serial \
    sed git unzip bash help2man wget bzip2 \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
 && git clone https://github.com/davidm/lua-inspect

RUN adduser --system --disabled-password --shell /bin/bash nodemcu

USER nodemcu

WORKDIR /home/nodemcu
RUN git clone --recursive https://github.com/pfalcon/esp-open-sdk.git
RUN cd esp-open-sdk && make

RUN mkdir /opt/nodemcu-firmware
WORKDIR /opt/nodemcu-firmware
COPY cmd.sh /opt/
CMD /opt/cmd.sh
