# syntax=docker/dockerfile:1.6
FROM quay.io/centos/centos:stream10

LABEL org.opencontainers.image.title="vortice" \
      org.opencontainers.image.description="Hosts a FreeRDP Proxy with a ad-hoc VDI Broker module" \
      org.opencontainers.image.source="https://github.com/marcomartini97/VORTICE" \
      org.opencontainers.image.vendor="vortice"

WORKDIR /opt

RUN dnf -y update && \
    dnf -y install dnf-plugins-core && \
    dnf config-manager --set-enabled crb && \
    dnf -y install epel-release && \
    dnf -y install --nogpgcheck https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm && \
    dnf -y install --nogpgcheck https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm && \
    /usr/bin/crb enable && \
    dnf -y install \
        git \
        cmake \
        ninja-build \
        gcc \
        gcc-c++ \
        make \
        pkgconfig \
        openssl \
        openssl-devel \
	ffmpeg-devel \
        libcurl-devel \
        jsoncpp-devel \
        pam-devel \
        cups-devel \
        alsa-lib-devel \
        pulseaudio-libs-devel \
        systemd-devel \
        wayland-devel \
        mesa-libEGL-devel \
        mesa-libGL-devel \
        libjpeg-turbo-devel \
        libpng-devel \
        libusb1-devel \
        zlib-devel \
        fuse3-devel \
	libicu-devel \
        podman \
        which \
        ca-certificates \
        tar \
        xz && \
    dnf clean all && \
    rm -rf /var/cache/dnf

COPY VDI_Broker /opt/freerdp

WORKDIR /opt/freerdp

RUN rm -rf server/proxy/modules/bitmap-filter \
           server/proxy/modules/demo \
           server/proxy/modules/dyn-channel-dump

RUN mkdir -p build

RUN cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DWITH_CLIENT=OFF \
        -DWITH_SERVER=ON \
	-DWITH_SHADOW=OFF \
        -DWITH_PROXY=ON \
        -DWITH_PROXY_MODULES=ON \
        -DWITH_PROXY_MODULES_AUTOLOAD=OFF \
        -DWITH_MANPAGES=OFF \
        -DWITH_IPP=OFF \
        -DWITH_CUPS=ON \
        -DWITH_PULSE=ON \
        -DWITH_WINPR_TOOLS=OFF \
        -DWITH_RDTK=OFF \
        -DWITH_SAMPLE=OFF \
        -DWITH_VERBOSE_WINPR_ASSERT=OFF && \
    cmake --build build --target freerdp-proxy proxy-vdi-broker-plugin && \
    cmake --install build && \
    echo "/usr/local/lib64" > /etc/ld.so.conf.d/freerdp.conf && \
    ldconfig && \
    rm -rf /opt/freerdp

# Remove Kerberos config (Default config segfaults)
RUN rm -rf /etc/krb5.conf

COPY config /etc/vdi

# Provide a default PAM service so the broker can authenticate against /etc/shadow
COPY config/pam.d/vdi-broker /etc/pam.d/vdi-broker

COPY VORTICE-vdi /etc/vdi/VORTICE-vdi

COPY keys/ /tmp/keys/

# Copy TLS assets from the build context when present; otherwise create a self-signed pair.
RUN KEYS_PATH=$(find /tmp/keys -maxdepth 1 -type f -name '*.pem' -print -quit) && \
    mkdir -p /etc/vdi && \
    if [ -n "$KEYS_PATH" ]; then \
        cp /tmp/keys/* /etc/vdi/; \
    else \
	openssl req -x509 -nodes -newkey rsa:4096 \
            -keyout /etc/vdi/key.pem \
            -out /etc/vdi/cert.pem \
            -days 365 \
            -subj "/C=US/ST=VDI/L=Proxy/O=Vortice/OU=VDI/CN=freerdp-proxy"; \
    fi

EXPOSE 3389

ENV FREERDP_PROXY_CONFIG=/etc/vdi/config.ini

CMD ["/usr/local/bin/freerdp-proxy", "/etc/vdi/config.ini"]
