FROM debian:trixie-slim as build
ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=UTC
ARG version=0.1.8
ENV CMAKE_INSTALL_PREFIX=/usr

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    wget \
    patch \
    pkg-config \
    libssl-dev \
    libcurl4-openssl-dev \
    libxrdapputils2t64 \
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
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    xrootd-server libc6 libcurl4t64 libgcc-s1 libssl3t64 libstdc++6 libtinyxml2-10 libxrdserver3t64 libxrdutils3t64 ca-certificates
COPY --from=build /opt/xrootd-s3-http/build/libXrdS3-5.so /usr/lib/
COPY --from=build /opt/xrootd-s3-http/build/libXrdHTTPServer-5.so /usr/lib/
COPY ./xrootd-s3-http.cfg /etc/xrootd/
USER xrootd
CMD ["xrootd", "-c", "/etc/xrootd/xrootd-s3-http.cfg"]
