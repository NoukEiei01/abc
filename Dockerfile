FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV USER=Nouk
ENV PASSWORD=nouk1234
ENV HOME=/home/Nouk
ENV DISPLAY=:1

RUN apt-get update && apt-get install -y \
    xfce4 \
    xfce4-goodies \
    tigervnc-standalone-server \
    tigervnc-common \
    xrdp \
    novnc \
    websockify \
    chromium-browser \
    dbus-x11 \
    x11-xserver-utils \
    xfonts-base \
    xfonts-75dpi \
    xfonts-100dpi \
    supervisor \
    curl \
    wget \
    gnupg \
    lsb-release \
    ca-certificates \
    apt-transport-https \
    net-tools \
    python3-pip \
    xxd \
    procps \
    sudo \
    tzdata \
    locales \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# DEBUG: หา vnc binaries ทั้งหมด
RUN echo "=== VNC binaries ===" \
    && find /usr -name "*vnc*" 2>/dev/null \
    && find /usr -name "*Xvnc*" 2>/dev/null \
    && echo "=== dpkg tigervnc ===" \
    && dpkg -L tigervnc-standalone-server 2>/dev/null || true

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Create user Nouk
RUN useradd -m -s /bin/bash Nouk \
    && echo "Nouk:nouk1234" | chpasswd \
    && usermod -aG sudo Nouk \
    && echo "Nouk ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /home/Nouk/.vnc \
    && mkdir -p /home/Nouk/.config \
    && chown -R Nouk:Nouk /home/Nouk

COPY xstartup /home/Nouk/.vnc/xstartup
RUN chmod +x /home/Nouk/.vnc/xstartup \
    && chown Nouk:Nouk /home/Nouk/.vnc/xstartup

RUN sed -i 's/^crypt_level=high/crypt_level=low/' /etc/xrdp/xrdp.ini \
    && echo "exec startxfce4" > /home/Nouk/.xsession \
    && chown Nouk:Nouk /home/Nouk/.xsession

RUN adduser xrdp ssl-cert || true

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html || true
RUN mkdir -p /run/dbus && chown messagebus:messagebus /run/dbus || true

EXPOSE 5901 3389 6080

CMD ["/start.sh"]
