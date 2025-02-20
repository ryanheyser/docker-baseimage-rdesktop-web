FROM ghcr.io/linuxserver/baseimage-ubuntu:noble AS builder

ARG GUACD_VERSION=1.5.5
ARG NODE_VERSION=18

COPY /buildroot /

RUN \
 export DEBIAN_FRONTEND="noninteractive" && \
 echo "**** install build deps ****" && \
 apt-get update && \
 apt-get install -qy --no-install-recommends \
	autoconf \
	automake \
	checkinstall \
	freerdp2-dev \
	g++ \
	gcc \
	git \
	libavcodec-dev \
	libavformat-dev \
	libavutil-dev \
	libcairo2-dev \
	libjpeg-turbo8-dev \
	libogg-dev \
	libossp-uuid-dev \
	libpango1.0-dev \
	libpng-dev \
	libpulse-dev \
	libssh2-1-dev \
	libssl-dev \
	libswscale-dev \
	libtool-bin \
	libvncserver-dev \
	libvorbis-dev \
	libwebsockets-dev \
	libwebp-dev \
	uuid-dev \
	make

RUN \
 echo "**** prep build ****" && \
 mkdir /tmp/guacd && \
 git clone https://github.com/apache/guacamole-server.git /tmp/guacd && \
 echo "**** build guacd ****" && \
 cd /tmp/guacd && \
 git checkout ${GUACD_VERSION} && \
 autoreconf -fi && \
 ./configure --prefix=/usr/local && \
 make -j4 && \
 mkdir -p /tmp/out && \
 /usr/local/bin/list-dependencies.sh \
	"/tmp/guacd/src/guacd/.libs/guacd" \
	$(find /tmp/guacd | grep "so$") \
	> /tmp/out/DEPENDENCIES && \
 export PREFIX=/usr/local && \
 checkinstall \
	-y \
	-D \
	--nodoc \
	--pkgname guacd \
	--pkgversion "${GUACD_VERSION}" \
	--pakdir /tmp \
	--exclude "/usr/share/man","/usr/include","/etc" && \
 mkdir -p /tmp/out && \
 mv \
	/tmp/guacd_${GUACD_VERSION}-*.deb \
	/tmp/out/guacd_${GUACD_VERSION}.deb

# nodejs builder
FROM ghcr.io/linuxserver/baseimage-ubuntu:noble AS nodebuilder
ARG GCLIENT_RELEASE
ARG GCLIENT_VERSION=1.2.0
ARG NODE_VERSION=18

RUN \
 export DEBIAN_FRONTEND="noninteractive" && \
 echo "**** install build deps ****" && \
 apt-get update && \
 apt-get install -y \
	gnupg && \
 curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
 apt-get update && \
 apt-get install -y \
	g++ \
	gcc \
	libpam0g-dev \
	make \
	nodejs

RUN \
 echo "**** grab source ****" && \
 mkdir -p /gclient && \
 curl -o \
 /tmp/gclient.tar.gz -L \
	"https://github.com/linuxserver/gclient/archive/${GCLIENT_VERSION}.tar.gz" && \
 tar xf \
 /tmp/gclient.tar.gz -C \
	/gclient/ --strip-components=1

RUN \
 echo "**** install node modules ****" && \
 cd /gclient && \
 npm install 

# runtime stage
FROM ghcr.io/linuxserver/baseimage-rdesktop:ubuntunoble

# set version label
ARG BUILD_DATE
ARG VERSION
ARG GUACD_VERSION=1.5.5
ARG NODE_VERSION=18
LABEL build_version="ryanheyser version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="ryanheyser"

# Copy build outputs
COPY --from=builder /tmp/out /tmp/out
COPY --from=nodebuilder /gclient /gclient

RUN \
 export DEBIAN_FRONTEND="noninteractive" && \
 echo "**** install guacd ****" && \
 dpkg --path-include=/usr/share/doc/${PKG_NAME}/* \
        -i /tmp/out/guacd_${GUACD_VERSION}.deb && \
 echo "**** install packages ****" && \
 apt-get update && \
 apt-get install -y \
	gnupg && \
 curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
 apt-get update && \
 DEBIAN_FRONTEND=noninteractive \
 apt-get install --no-install-recommends -y \
	ca-certificates \
	libfreerdp2-2 \
	libfreerdp-client2-2 \
	libossp-uuid16 \
	libterm-readline-gnu-perl \
	nodejs \
	obconf \
	openbox \
	python-is-python3 \
	python3 \
	xterm && \
 apt-get install -qy --no-install-recommends \
	$(cat /tmp/out/DEPENDENCIES) && \
 echo "**** grab websocat ****" && \
 WEBSOCAT_RELEASE=$(curl -sX GET "https://api.github.com/repos/vi/websocat/releases/latest" \
	| awk '/tag_name/{print $4;exit}' FS='[""]'); \
 curl -o \
 /usr/local/bin/websocat -fL \
	"https://github.com/vi/websocat/releases/download/${WEBSOCAT_RELEASE}/websocat_max.x86_64-unknown-linux-musl" && \
 chmod +x /usr/local/bin/websocat && \
 echo "**** cleanup ****" && \
 apt-get autoclean && \
 rm -rf \
        /var/lib/apt/lists/* \
        /var/tmp/* \
        /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
