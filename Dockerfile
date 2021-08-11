#FROM 899991151204.dkr.ecr.us-east-1.amazonaws.com/alpine:latest
# FROM ubuntu:latest
FROM 899991151204.dkr.ecr.us-east-1.amazonaws.com/alpine:latest
# The ubuntu:latest tag points to the "latest LTS"
# We use Ubuntu Linux (LTS releases) for our internal Looker hosting, and recommend it for customers who do not have a Linux preference.
USER root
RUN whoami
ENV LOOKER_VERSION="21.12.7"
ENV LOOKER_LICENSE_KEY="BE17-BCF6-CAB6-0F89-9D7B"
ENV LOOKER_LICENSE_EMAIL="deepak.kumar@coupa.com"

ENV PHANTOMJS_VERSION=2.1.1

RUN echo "[INFO]::p[installing]::[phantomjs" \
    && apk update \
    && apk add bash \
    && apk --update add ttf-ubuntu-font-family fontconfig \
    && apk add --no-cache curl && \
    cd /tmp && curl -Ls https://github.com/dustinblackman/phantomized/releases/download/${PHANTOMJS_VERSION}/dockerized-phantomjs.tar.gz | tar xz && \
    cp -R lib lib64 / && \
    cp -R usr/lib/x86_64-linux-gnu /usr/lib && \
    cp -R usr/share /usr/share && \
    cp -R etc/fonts /etc && \
    curl -k -Ls https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-${PHANTOMJS_VERSION}-linux-x86_64.tar.bz2 | tar -jxf - && \
    cp phantomjs-${PHANTOMJS_VERSION}-linux-x86_64/bin/phantomjs /usr/local/bin/phantomjs && \
    rm -fR phantomjs-${PHANTOMJS_VERSION}-linux-x86_64
    
RUN echo "[INFO]::[installing]::[base packages]" \
    && ln -snf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime && echo "America/Los_Angeles" > /etc/timezone \
    && apk update \
    && apk add --no-cache libressl-dev libmcrypt-dev ca-certificates \
    git git openntpd curl tzdata bzip2 libstdc++ libx11 libxrender libxext fontconfig freetype ttf-dejavu ttf-droid \
    chromium openjdk8 ttf-freefont ttf-ubuntu-font-family ttf-liberation libressl-dev  mysql-client jq \
    && alias chromium='chromium-browser' && sudo ln -s /usr/bin/chromium-browser /usr/bin/chromium

RUN echo "[INFO]::[configure]::[misc]" \
    && cp /etc/sysctl.conf /etc/sysctl.conf.dist \
    && echo "net.ipv4.tcp_keepalive_time=200" | tee -a /etc/sysctl.conf \
    && echo "net.ipv4.tcp_keepalive_intvl=200" | tee -a /etc/sysctl.conf \
    && echo "net.ipv4.tcp_keepalive_probes=5" | tee -a /etc/sysctl.conf \
    && addgroup -g 1002 "looker" ||  true \
    && adduser -u 1002 -S "looker" -G "looker" || true\
    && cp /etc/launchd.conf /etc/launchd.conf.dist || true \
    && echo "limit      maxfiles 8192 8192"     | tee -a /etc/launchd.conf \
    && echo "looker     soft     nofile     8192" | tee -a /etc/launchd.conf \
    && echo "looker     hard     nofile     8192" | tee -a /etc/launchd.conf \
    && echo '%looker ALL=(ALL) NOPASSWD:ALL' | tee -a /etc/sudoers

RUN echo "Looker License Email ${LOOKER_LICENSE_EMAIL}"

RUN echo "[INFO]::[download]::[looker]" \
    && mkdir -p /home/looker/looker \
    && curl -X POST -H 'Content-Type: application/json' \
    -d '{"lic": "'$LOOKER_LICENSE_KEY'", "email": "'$LOOKER_LICENSE_EMAIL'", "latest": "latest"}' \
    https://apidownload.looker.com/download | jq -r '.url' | xargs curl -o /home/looker/looker/looker.jar \
    && curl -X POST -H 'Content-Type: application/json' \
    -d '{"lic": "'$LOOKER_LICENSE_KEY'", "email": "'$LOOKER_LICENSE_EMAIL'", "latest": "latest"}' \
    https://apidownload.looker.com/download | jq -r '.depUrl' | xargs curl -o /home/looker/looker/looker-dependencies.jar

#COPY config/looker.jar /home/looker/looker/
#COPY config/looker-dependencies.jar /home/looker/looker/


RUN set -a && \
  curl https://raw.githubusercontent.com/looker/customer-scripts/master/startup_scripts/looker > /home/looker/looker/looker-service

COPY ./config /tmp/build-configs

RUN echo "[INFO]::[configure]::[looker]" \
    && chmod 0750 /home/looker/looker/looker-service \
    && mv /tmp/build-configs/lookerstart.cfg /home/looker/looker/lookerstart.cfg \
    && mv /tmp/build-configs/database.yml /home/looker/looker/database.yml \
    && mv /tmp/build-configs/provision.yml /home/looker/looker/provision.yml \
    && chown -R looker:looker /home/looker/looker

# Move in standard entrypoint script and configure to run through TINI for safety.
COPY bin/docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV TINI_VERSION v0.18.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

# /srv is owned by root:root out of the box. Add looker:looker /srv/data because Looker expects to write data to this volume
RUN mkdir /srv/data
RUN chown -R looker:looker /srv/data

USER looker

EXPOSE 9999


ENTRYPOINT ["/tini", "--"]

CMD ["/entrypoint.sh", "/home/looker/looker/looker-service", "start"]
