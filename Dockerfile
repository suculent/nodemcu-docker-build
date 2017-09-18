FROM ubuntu
MAINTAINER suculent

RUN apt-get update && apt-get install -y wget unzip git make python-serial srecord bc xz-utils gcc git
RUN git clone https://github.com/davidm/lua-inspect
RUN mkdir /opt/nodemcu-firmware
WORKDIR /opt
RUN wget https://github.com/nodemcu/nodemcu-firmware/raw/master/tools/esp-open-sdk.tar.xz && tar -Jxvf esp-open-sdk.tar.xz && rm -rf esp-open-sdk.tar.xz
WORKDIR /opt/nodemcu-firmware

COPY cmd.sh /opt/

CMD /opt/cmd.sh
