# I am pulling in my alpine-s6 image as the base here so I can reuse it for the common buildimage and later in the runtime. 
# Initially I used to pull this separately at each stage but that gave errors with docker buildx for the BASE_VERSION argument.
ARG BASE_VERSION=3.12-2.0.0.1
FROM rakheshster/alpine-s6:${BASE_VERSION} AS mybase

################################### COMMON BUILDIMAGE ####################################
# This image is to be a base where all the build dependencies are installed. 
# I can use this in the subsequent stages to build stuff (doesn't make much sense in this case as I am only building Stubby but I want to keep my Dockerfiles consistent)
FROM mybase AS alpinebuild

# I realized that the build process doesn't remove this intermediate image automatically so best to LABEL it here and then prune later
# Thanks to https://stackoverflow.com/a/55082473
LABEL stage="alpinebuild"
LABEL maintainer="Rakhesh Sasidharan"

# Get the build-dependencies for everything I plan on building later
# common stuff: git build-base libtool xz cmake
# stubby/ getdns: (https://github.com/getdnsapi/getdns#external-dependencies) openssl-dev yaml-dev unbound-dev
RUN apk add --update --no-cache \
    git build-base libtool xz cmake \
    openssl-dev unbound-dev yaml-dev libidn2-dev libuv-dev libev-dev check-dev
RUN rm -rf /var/cache/apk/*


################################### STUBBY ####################################
# This image is to only build Stubby
FROM alpinebuild as alpinestubby

ENV GETDNS_VERSION 1.6.0
ENV STUBBY_VERSION 0.3.0

LABEL stage="alpinestubby"
LABEL maintainer="Rakhesh Sasidharan"

# Download the source
# Official recommendation (for example: https://github.com/getdnsapi/getdns/releases/tag/v1.6.0) is to get the tarball from getdns than from GitHub
# Stubby is developed by the getdns team. When building getdns one can also build stubby alongwith
# libgetdns is a dependancy for Stubby, the getdns library provides all the core functionality for DNS resolution done by Stubby so it is important to build against the latest version of getdns.
ADD https://getdnsapi.net/dist/getdns-${GETDNS_VERSION}.tar.gz /tmp/

# Create a workdir called /src, extract the getdns source to that, build it
# Cmake steps from https://lektor.getdnsapi.net/quick-start/cmake-quick-start/ (v 1.6.0)
WORKDIR /src
RUN tar xzf /tmp/getdns-${GETDNS_VERSION}.tar.gz -C ./
WORKDIR /src/getdns-${GETDNS_VERSION}/build
RUN cmake -DBUILD_STUBBY=ON -DCMAKE_INSTALL_PREFIX:PATH=/ ..
RUN make && DESTDIR=/usr/local make install


################################### DNSMASQ ####################################
# This image installs dnsmasq and all my runtime deps. Yes, a bit convoluted because unlike my other images here I am just installing dnsmasq from the Alpine repo than building it from scratch.
# I will be basing my final image on this one as it has all the runtime deps. 
FROM mybase AS alpinednsmasq

LABEL stage="alpinednsmasq"
LABEL maintainer="Rakhesh Sasidharan"

# Install dnsmasq (first line) and run-time dependencies for Stubby (I found these by running stubby and what it complained about)
# Also create a user and group to run stubby as (thanks to https://stackoverflow.com/a/49955098 for syntax)
# addgroup / adduser -S creates a system group / user; the -D says don't assign a password
RUN apk add --update --no-cache dnsmasq ca-certificates tzdata \
    yaml libidn2 unbound-dev drill nano
RUN rm -rf /var/cache/apk/*
RUN addgroup -S stubby && adduser -D -S stubby -G stubby
RUN mkdir -p /var/cache/stubby
RUN chown stubby:stubby /var/cache/stubby

# Copy in Stubby from the previous build
COPY --from=alpinestubby /usr/local/ /


################################### FINALIZE ####################################
# This pulls in the previous image and copies some files over. This is my final image. 
FROM alpinednsmasq 

# Copy the config files & s6 service files to the correct location
COPY root/ /

# NOTE: s6 overlay doesn't support running as a different user, but I set the stubby service to run under user "stubby" in its service definition.
# Similarly dnsmasq runs under its own user & group via the config file. 

EXPOSE 8053/udp 53/udp 53/tcp

HEALTHCHECK --interval=5s --timeout=3s --start-period=5s \
    CMD drill @127.0.0.1 -p 8053 google.com || exit 1

ENTRYPOINT ["/init"]
