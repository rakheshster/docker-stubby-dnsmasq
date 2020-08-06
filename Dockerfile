################################### STUBBY ####################################
# This image is to only build Stubby
FROM alpine:latest AS alpinestubby

ENV GETDNS_VERSION 1.6.0
ENV STUBBY_VERSION 0.3.0

# I realized that the build process doesn't remove this intermediate image automatically so best to LABEL it here and then prune later
# Thanks to https://stackoverflow.com/a/55082473
LABEL stage="alpinestubby"
LABEL maintainer="Rakhesh Sasidharan"

# I need the arch later on when downloading s6. Rather than doing the check at that later stage, I introduce the ARG here itself so I can quickly validate and fail if needed.
# Use the --build-arg ARCH=xxx to pass an argument
ARG ARCH=armhf
RUN if ! [[ ${ARCH} = "amd64" || ${ARCH} = "x86" || ${ARCH} = "armhf" || ${ARCH} = "arm" || ${ARCH} = "aarch64" ]]; then \
    echo "Incorrect architecture specified! Must be one of amd64, x86, armhf (for Pi), arm, aarch64"; exit 1; \
    fi

# Get the build-dependencies for stubby & getdns
# See for the official list: https://github.com/getdnsapi/getdns#external-dependencies
# https://pkgs.alpinelinux.org/packages is a good way to search for alpine packages. Note it uses wildcards
RUN apk add --update --no-cache git build-base \ 
    libtool openssl-dev \
    unbound-dev yaml-dev \
    cmake libidn2-dev libuv-dev libev-dev check-dev \
    && rm -rf /var/cache/apk/*

# Download the source
# Official recommendation (for example: https://github.com/getdnsapi/getdns/releases/tag/v1.6.0) is to get the tarball from getdns than from GitHub
# Stubby is developed by the getdns team. libgetdns is a dependancy for Stubby, the getdns library provides all the core functionality for DNS resolution done by Stubby so it is important to build against the latest version of getdns.
# When building getdns one can also build stubby alongwith
ADD https://getdnsapi.net/dist/getdns-${GETDNS_VERSION}.tar.gz /tmp/

# Create a workdir called /src, extract the getdns source to that, build it
# Cmake steps from https://lektor.getdnsapi.net/quick-start/cmake-quick-start/ (v 1.6.0)
WORKDIR /src
RUN tar xzf /tmp/getdns-${GETDNS_VERSION}.tar.gz -C ./
WORKDIR /src/getdns-${GETDNS_VERSION}/build
RUN cmake -DBUILD_STUBBY=ON -DCMAKE_INSTALL_PREFIX:PATH=/usr/local .. && \
    make && \
    make install

################################### DNSMASQ ####################################
# This image is to only install dnsmasq. I can reuse this image later without have to rebuild the whole image for any small changes. 
# Basically I am doing a multistage build. https://docs.docker.com/develop/develop-images/multistage-build/
FROM alpine:latest AS alpinednsmasq

LABEL stage="alpinednsmasq"
LABEL maintainer="Rakhesh Sasidharan"

# Install dnsmasq (first line) and run-time dependencies for Stubby (I found these by running stubby and what it complained about)
# Also create a user and group to run stubby as (thanks to https://stackoverflow.com/a/49955098 for syntax)
# addgroup / adduser -S creates a system group / user; the -D says don't assign a password
RUN apk add --update --no-cache dnsmasq ca-certificates \
    yaml libidn2 unbound-dev drill && \
    addgroup -S stubby && adduser -D -S stubby -G stubby && \
    mkdir -p /var/cache/stubby && \
    chown stubby:stubby /var/cache/stubby


################################### S6 & FINALIZE ####################################
# This pulls in dnsmasq & Stubby, adds s6 and copies some files over
# Create a new image based on alpinednsmasq ...
FROM alpinednsmasq 

# ... and copy the files from the alpinestubby image to the new image (so /usr/local/bin -> /bin etc.)
COPY --from=alpinestubby /usr/local/ /

# I take the arch (for s6) as an argument. Options are amd64, x86, armhf (for Pi), arm, aarch64. See https://github.com/just-containers/s6-overlay#releases
ARG ARCH=armhf 
LABEL maintainer="Rakhesh Sasidharan"
ENV S6_VERSION 2.0.0.1

# Copy the config files & s6 service files to the correct location
COPY root/ /

# Add s6 overlay. 
# NOTE: The default instructions give the impression one must do a 2-stage extract. That's only to target this issue - https://github.com/just-containers/s6-overlay#known-issues-and-workarounds
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-${ARCH}.tar.gz /tmp/
RUN tar xzf /tmp/s6-overlay-${ARCH}.tar.gz -C / && \
    rm  -f /tmp/s6-overlay-${ARCH}.tar.gz

# NOTE: s6 overlay doesn't support running as a different user, but I set the stubby service to run under user "stubby" in its service definition.
# Similarly dnsmasq runs under its own user & group via the config file. 

EXPOSE 8053/udp 53/udp 53/tcp

HEALTHCHECK --interval=5s --timeout=3s --start-period=5s \
    CMD drill @127.0.0.1 -p 8053 google.com || exit 1

ENTRYPOINT ["/init"]
