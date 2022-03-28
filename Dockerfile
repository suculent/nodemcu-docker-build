# see https://hub.docker.com/_/ubuntu/ for versions, should be the same as on Travis for NodeMCU CI
# 16.04 == xenial
FROM ubuntu:xenial
LABEL maintainer="marcelstoer"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends wget unzip git make srecord bc xz-utils gcc ccache tzdata vim-tiny

# additionally required for ESP32 builds as per https://nodemcu.readthedocs.io/en/dev-esp32/build/#ubuntu
RUN apt-get install -y --no-install-recommends git gperf python-pip python-dev flex bison build-essential libssl-dev libffi-dev libncurses5-dev libncursesw5-dev libreadline-dev

RUN pip install --upgrade pip
RUN pip install setuptools

RUN rm -rf /root
RUN ln -s /tmp /root
ENV PATH="/opt:${PATH}"

COPY cmd.sh /opt/
COPY build /opt/
COPY build-esp32 /opt/
COPY build-esp8266 /opt/
COPY configure-esp32 /opt/
COPY lfs-image /opt/

RUN git clone https://github.com/davidm/lua-inspect

# Release some space...
RUN apt-get clean \
 && rm -rf /var/lib/apt/lists/*

CMD ["/opt/cmd.sh"]