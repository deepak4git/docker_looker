FROM 899991151204.dkr.ecr.us-east-1.amazonaws.com/alpine:latest
RUN whoami

ARG LOOKER_VERSION=""
ARG LOOKER_LICENSE_KEY=""
ARG LOOKER_LICENSE_EMAIL=""

ENV LOOKER_VERSION=${LOOKER_VERSION}
ENV LOOKER_LICENSE_KEY=${LOOKER_LICENSE_KEY}
ENV LOOKER_LICENSE_EMAIL=${LOOKER_LICENSE_EMAIL}

ENV PHANTOMJS_VERSION=2.1.1

RUN echo "[INFO]::p[installing]::[phantomjs]" \
    && sudo apk update \
    && sudo apk add bash \
    && sudo apk --update add ttf-ubuntu-font-family fontconfig \
    && sudo apk add --no-cache curl && \
    cd /tmp && curl -Ls https://github.com/dustinblackman/phantomized/releases/download/${PHANTOMJS_VERSION}/dockerized-phantomjs.tar.gz | tar xz && \
    sudo cp -R lib lib64 / && \
    sudo cp -R usr/lib/x86_64-linux-gnu /usr/lib && \
    sudo cp -R usr/share /usr/share && \
    sudo cp -R etc/fonts /etc && \
    sudo curl -k -Ls https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-${PHANTOMJS_VERSION}-linux-x86_64.tar.bz2 | tar -jxf - && \
    sudo cp phantomjs-${PHANTOMJS_VERSION}-linux-x86_64/bin/phantomjs /usr/local/bin/phantomjs && \
    rm -fR phantomjs-${PHANTOMJS_VERSION}-linux-x86_64
    
RUN echo "[INFO]::[installing]::[base packages]" \
    && sudo ln -snf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime \
    && echo "America/Los_Angeles" | sudo tee -a /etc/timezone \
    && sudo apk update \
    && sudo apk add --no-cache libressl-dev libmcrypt-dev ca-certificates \
    git git openntpd curl tzdata bzip2 libstdc++ libx11 libxrender libxext fontconfig freetype ttf-dejavu ttf-droid \
    chromium openjdk8 ttf-freefont ttf-ubuntu-font-family ttf-liberation libressl-dev  mysql-client jq \
    && alias chromium='chromium-browser' && sudo ln -s /usr/bin/chromium-browser /usr/bin/chromium

RUN echo "[INFO]::[configure]::[misc]" \
    && sudo cp /etc/sysctl.conf /etc/sysctl.conf.dist \
    && echo "net.ipv4.tcp_keepalive_time=200" | sudo tee -a /etc/sysctl.conf \
    && echo "net.ipv4.tcp_keepalive_intvl=200" | sudo tee -a /etc/sysctl.conf \
    && echo "net.ipv4.tcp_keepalive_probes=5" | sudo tee -a /etc/sysctl.conf \
    && sudo addgroup -g 1002 "looker" ||  true \
    && sudo adduser -u 1002 -S "looker" -G "looker" || true\
    && sudo cp /etc/launchd.conf /etc/launchd.conf.dist || true \
    && echo "limit      maxfiles 8192 8192"     | sudo tee -a /etc/launchd.conf \
    && echo "looker     soft     nofile     8192" | sudo tee -a /etc/launchd.conf \
    && echo "looker     hard     nofile     8192" | sudo tee -a /etc/launchd.conf \
    && echo '%looker ALL=(ALL) NOPASSWD:ALL' | sudo tee -a /etc/sudoers

RUN echo "Looker License Email ${LOOKER_LICENSE_EMAIL}"

RUN echo "[INFO]::[download]::[looker]" \
    && sudo mkdir -p /home/looker/looker \
    && curl -X POST -H 'Content-Type: application/json' \
    -d '{"lic": "'$LOOKER_LICENSE_KEY'", "email": "'$LOOKER_LICENSE_EMAIL'", "latest": "latest"}' \
    https://apidownload.looker.com/download | jq -r '.url' | sudo xargs curl -o /home/looker/looker/looker.jar \
    && curl -X POST -H 'Content-Type: application/json' \
    -d '{"lic": "'$LOOKER_LICENSE_KEY'", "email": "'$LOOKER_LICENSE_EMAIL'", "latest": "latest"}' \
    https://apidownload.looker.com/download | jq -r '.depUrl' | sudo xargs curl -o /home/looker/looker/looker-dependencies.jar


RUN set -a && \
  curl https://raw.githubusercontent.com/looker/customer-scripts/master/startup_scripts/looker | sudo tee -a /home/looker/looker/looker-service

COPY ./config /tmp/build-configs

RUN echo "[INFO]::[configure]::[looker]" \
    && sudo chmod 0750 /home/looker/looker/looker-service \
    && sudo mv /tmp/build-configs/lookerstart.cfg /home/looker/looker/lookerstart.cfg \
    && sudo chown -R looker:looker /home/looker/looker

# Move in standard entrypoint script and configure to run through TINI for safety.
COPY bin/entrypoint.sh /entrypoint.sh
RUN sudo chmod +x /entrypoint.sh

ENV TINI_VERSION v0.18.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN sudo chmod +x /tini

# /srv is owned by root:root out of the box. Add looker:looker /srv/data because Looker expects to write data to this volume
RUN sudo mkdir /srv/data
RUN sudo chown -R looker:looker /srv/data

USER looker

EXPOSE 9999
EXPOSE 19999

ENTRYPOINT ["/tini", "--"]

CMD ["/entrypoint.sh", "/home/looker/looker/looker-service", "start"]
