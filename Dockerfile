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
    procps \
    sudo \
    tzdata \
    locales \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*
# Debug: หา vncpasswd binary
RUN find / -name "vncpasswd" 2>/dev/null || echo "vncpasswd not found at build time"
RUN find / -name "tigervncpasswd" 2>/dev/null || echo "tigervncpasswd not found"

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Create user Nouk
RUN useradd -m -s /bin/bash Nouk \
    && echo "Nouk:nouk1234" | chpasswd \
    && usermod -aG sudo Nouk \
    && echo "Nouk ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Setup directories
RUN mkdir -p /home/Nouk/.vnc \
    && mkdir -p /home/Nouk/.config \
    && chown -R Nouk:Nouk /home/Nouk

# xstartup (VNC password จะ set ใน start.sh แทน)
COPY xstartup /home/Nouk/.vnc/xstartup
RUN chmod +x /home/Nouk/.vnc/xstartup \
    && chown Nouk:Nouk /home/Nouk/.vnc/xstartup

# Configure xrdp
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
