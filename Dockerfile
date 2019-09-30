FROM ubuntu
MAINTAINER suculent@me.com

RUN apt-get update -qq && apt-get install -qq -y wget unzip git make python-serial srecord bc xz-utils gcc git \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
 && git clone https://github.com/davidm/lua-inspect

WORKDIR /opt
RUN wget https://github.com/nodemcu/nodemcu-firmware/raw/master/tools/esp-open-sdk.tar.xz && tar -Jxvf esp-open-sdk.tar.xz && rm -rf esp-open-sdk.tar.xz

RUN mkdir /opt/nodemcu-firmware
WORKDIR /opt/nodemcu-firmware
COPY cmd.sh /opt/
CMD /opt/cmd.sh
