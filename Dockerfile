FROM debian:trixie-slim as build
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=UTC
ARG version=0.6.9-1
ENV CMAKE_INSTALL_PREFIX=/usr

# Debian trixie's own repo is frozen at XRootD 5.8.1 (built 2025-07-14, over
# a year stale by the time this comment was written). Upstream publishes a
# real, maintained apt repo for trixie specifically - use it instead to get
# a current release (6.1.1 as of this writing).
RUN apt-get update && apt-get install -y --no-install-recommends wget gnupg ca-certificates && \
    wget -qO /etc/apt/trusted.gpg.d/xrootd.asc https://xrootd.web.cern.ch/repo/RPM-GPG-KEY.txt && \
    echo "deb https://xrootd.web.cern.ch/debian trixie stable" > /etc/apt/sources.list.d/xrootd.list && \
    apt-get update

RUN apt-get install -y \
    build-essential \
    cmake \
    wget \
    patch \
    pkg-config \
    libssl-dev \
    libcurl4-openssl-dev \
    libxrdapputils6t64 \
    libxrootd-server-dev \
    libtinyxml2-dev

WORKDIR /opt/
RUN wget https://github.com/PelicanPlatform/xrootd-s3-http/archive/refs/tags/v${version}/xrootd-s3-http-${version}.tar.gz && \
    tar -xvf xrootd-s3-http-${version}.tar.gz && \
    mv xrootd-s3-http-${version} xrootd-s3-http && \
    cd xrootd-s3-http && \
    mkdir build

WORKDIR /opt/xrootd-s3-http/build
RUN cmake -DXROOTD_EXTERNAL_TINYXML2=ON .. 
RUN make

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends wget gnupg ca-certificates && \
    wget -qO /etc/apt/trusted.gpg.d/xrootd.asc https://xrootd.web.cern.ch/repo/RPM-GPG-KEY.txt && \
    echo "deb https://xrootd.web.cern.ch/debian trixie stable" > /etc/apt/sources.list.d/xrootd.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    xrootd-server xrootd-voms-plugins libc6 libcurl4t64 libgcc-s1 libssl3t64 libstdc++6 libtinyxml2-11 libxrdserver6t64 libxrdutils6t64
# CERN's package allocates the xrootd system user/group dynamically (100/101
# here), unlike Debian's own package (996/996) that all existing xrd* hosts'
# /opt/xrootd/admin on-disk ownership was set up against. Pin it back to
# 996/996 so a version bump doesn't silently break write access to
# already-deployed hosts' bind-mounted admin/log directories.
RUN groupmod -g 996 xrootd && usermod -u 996 xrootd && \
    chown -R xrootd:xrootd /var/log/xrootd /var/spool/xrootd
RUN mkdir -p /usr/local/share/ca-certificates/sunet
COPY Sunet-test.crt /usr/local/share/ca-certificates/sunet/Sunet_test_Root_CA.crt
RUN update-ca-certificates
COPY --from=build /opt/xrootd-s3-http/build/libXrdS3-6.so /usr/lib/x86_64-linux-gnu/
COPY --from=build /opt/xrootd-s3-http/build/libXrdHTTPServer-6.so /usr/lib/x86_64-linux-gnu/
# libXrdS3 and libXrdHTTPServer both link against this shared internal
# library, introduced since v0.4.1 - missing it fails osslib load with a
# misleading "No such file or directory" for libXrdS3 itself.
COPY --from=build /opt/xrootd-s3-http/build/libXrdPelicanHttpCore.so.0.0.0 /usr/lib/x86_64-linux-gnu/
RUN ln -s libXrdPelicanHttpCore.so.0.0.0 /usr/lib/x86_64-linux-gnu/libXrdPelicanHttpCore.so.0
COPY ./xrootd-s3-http.cfg /etc/xrootd/
USER xrootd
CMD ["xrootd", "-c", "/etc/xrootd/xrootd-s3-http.cfg"]
