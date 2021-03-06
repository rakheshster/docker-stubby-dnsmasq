# I am pulling in my alpine-s6 image as the base here so I can reuse it for the common buildimage and later in the runtime. 
# Initially I used to pull this separately at each stage but that gave errors with docker buildx for the BASE_VERSION argument.
ARG BASE_VERSION=3.13-2.2.0.3
FROM rakheshster/alpine-s6:${BASE_VERSION} AS mybase

################################### COMMON BUILDIMAGE ####################################
# This image is to be a base where all the build dependencies are installed. 
# I can use this in the subsequent stages to build stuff (doesn't make much sense in this case as I am only building Stubby but I want to keep my Dockerfiles consistent)
FROM mybase AS builder1

# I realized that the build process doesn't remove this intermediate image automatically so best to LABEL it here and then prune later
# Thanks to https://stackoverflow.com/a/55082473
LABEL stage="builder1"
LABEL maintainer="Rakhesh Sasidharan"

ENV GETDNS_VERSION 1.6.0
ENV STUBBY_VERSION 0.3.0

# Get the build-dependencies for everything I plan on building later
# common stuff: git build-base libtool xz cmake gnupg (to verify)
# stubby/ getdns: (https://github.com/getdnsapi/getdns#external-dependencies) openssl-dev yaml-dev unbound-dev
RUN apk add --update --no-cache \
    git build-base libtool xz cmake gnupg \
    openssl-dev unbound-dev yaml-dev libidn2-dev libuv-dev libev-dev check-dev
RUN rm -rf /var/cache/apk/*

################################### STUBBY ####################################
# Download the source & build it
# Official recommendation (for example: https://github.com/getdnsapi/getdns/releases/tag/v1.6.0) is to get the tarball from getdns than from GitHub
# Stubby is developed by the getdns team. When building getdns one can also build stubby alongwith
# libgetdns is a dependancy for Stubby, the getdns library provides all the core functionality for DNS resolution done by Stubby so it is important to build against the latest version of getdns.
ADD https://getdnsapi.net/dist/getdns-${GETDNS_VERSION}.tar.gz /tmp/
ADD https://getdnsapi.net/dist/getdns-${GETDNS_VERSION}.tar.gz.asc /tmp/
# Import GetDNS's key (Willem Toorop <willem@nlnetlabs.nl>)
RUN gpg --recv-keys 0xE5F8F8212F77A498
# Verify the download (exit if it fails)
RUN gpg --status-fd 1 --verify /tmp/getdns-${GETDNS_VERSION}.tar.gz.asc /tmp/getdns-${GETDNS_VERSION}.tar.gz 2>/dev/null | grep -q "GOODSIG E5F8F8212F77A498" \
    || exit 1

# Create a workdir called /src, extract the getdns source to that, build it
# Cmake steps from https://lektor.getdnsapi.net/quick-start/cmake-quick-start/ (v 1.6.0)
WORKDIR /src
RUN tar xzf /tmp/getdns-${GETDNS_VERSION}.tar.gz -C ./
WORKDIR /src/getdns-${GETDNS_VERSION}/build
# Configure to expect everything in / (--prefix=/) but when installing put everything into /usr/local (via DESTDIR=) 
# In the final stage I copy the contents of this to / so that's why I do it this way. Just copy everything in /usr/local out of this stage 
RUN cmake -DBUILD_STUBBY=ON -DCMAKE_INSTALL_PREFIX:PATH=/ ..
RUN make && DESTDIR=/usr/local make install

################################### DNSMASQ ####################################
# Create a fresh stage and install dnsmasq in it. Then pull in stubby from the previous image. 
FROM mybase AS finalstage

LABEL maintainer="Rakhesh Sasidharan"
LABEL org.opencontainers.image.source=https://github.com/rakheshster/docker-stubby-dnsmasq

# Install dnsmasq (first line) and run-time dependencies for Stubby (I found these by running stubby and what it complained about)
# Also create a user and group to run stubby as (thanks to https://stackoverflow.com/a/49955098 for syntax)
# addgroup / adduser -S creates a system group / user; the -D says don't assign a password
RUN apk add --update --no-cache dnsmasq ca-certificates tzdata \
    yaml libidn2 unbound-dev drill nano openssl
RUN rm -rf /var/cache/apk/*
RUN addgroup -S stubby && adduser -D -S stubby -G stubby
RUN mkdir -p /var/cache/stubby
RUN chown stubby:stubby /var/cache/stubby

# Copy the Stubby files from the previous builds into this
# /usr/local/bin -> /bin etc.
COPY --from=builder1 /usr/local/ /
# Copy the config files & s6 service files to the correct location
COPY root/ /

# NOTE: s6 overlay doesn't support running as a different user, but I set the stubby service to run under user "stubby" in its service definition.
# Similarly dnsmasq runs under its own user & group via the config file. 

EXPOSE 8053/udp 53/udp 53/tcp

HEALTHCHECK --interval=5s --timeout=3s --start-period=5s \
    CMD drill @127.0.0.1 -p 8053 google.com || exit 1

ENTRYPOINT ["/init"]
