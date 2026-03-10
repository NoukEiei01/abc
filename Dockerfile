FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV USER=Nouk
ENV PASSWORD=nouk1234
ENV HOME=/home/Nouk
ENV DISPLAY=:1

# Install all packages
RUN apt-get update && apt-get install -y \
    xfce4 \
    xfce4-goodies \
    tightvncserver \
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
    expect \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Create user Nouk
RUN useradd -m -s /bin/bash ${USER} \
    && echo "${USER}:${PASSWORD}" | chpasswd \
    && usermod -aG sudo ${USER} \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Setup VNC directory
RUN mkdir -p ${HOME}/.vnc \
    && mkdir -p ${HOME}/.config \
    && chown -R ${USER}:${USER} ${HOME}

# Set VNC password (แก้แล้ว)
RUN su - Nouk -c "\
    mkdir -p ~/.vnc && \
    printf 'nouk1234\nnouk1234\nn\n' | vncpasswd && \
    chmod 600 ~/.vnc/passwd"

# Copy xstartup for VNC (XFCE4)
COPY xstartup ${HOME}/.vnc/xstartup
RUN chmod +x ${HOME}/.vnc/xstartup \
    && chown ${USER}:${USER} ${HOME}/.vnc/xstartup

# Configure xrdp to use VNC
RUN sed -i 's/^port=3389/port=3389/' /etc/xrdp/xrdp.ini \
    && sed -i 's/^#.*security_layer=.*/security_layer=rdp/' /etc/xrdp/xrdp.ini \
    && sed -i 's/^crypt_level=high/crypt_level=low/' /etc/xrdp/xrdp.ini \
    && sed -i 's/^bitmap_compression=true/bitmap_compression=true/' /etc/xrdp/xrdp.ini \
    && echo "exec /usr/bin/xfce4-session" > /etc/skel/.xsession \
    && echo "exec /usr/bin/xfce4-session" > ${HOME}/.xsession \
    && chown ${USER}:${USER} ${HOME}/.xsession

# Add xrdp user to ssl-cert group
RUN adduser xrdp ssl-cert || true

# Copy supervisor config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy start script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Set noVNC symlink
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html || true

# Fix dbus
RUN mkdir -p /run/dbus && chown messagebus:messagebus /run/dbus || true

EXPOSE 5901 3389 6080

CMD ["/start.sh"]
