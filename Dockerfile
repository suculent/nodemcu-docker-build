FROM ubuntu
MAINTAINER suculent

RUN apt-get update && apt-get install -y wget unzip git make python-serial srecord bc xz-utils gcc
RUN mkdir /opt/nodemcu-firmware
WORKDIR /opt/nodemcu-firmware

COPY cmd.sh /opt/

CMD /opt/cmd.sh
