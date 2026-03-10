#!/bin/bash
set -e

echo "[*] Starting Remote Desktop System..."

# Create log directory
mkdir -p /var/log/supervisor

# Fix dbus socket directory
mkdir -p /run/dbus
chown messagebus:messagebus /run/dbus 2>/dev/null || true
dbus-daemon --system --fork 2>/dev/null || true

# Clean up stale VNC locks
rm -f /tmp/.X1-lock
rm -f /tmp/.X11-unix/X1
su - Nouk -c "rm -f ~/.vnc/*.pid 2>/dev/null || true"

# Reset VNC password ทุกครั้งที่ start (แก้แล้ว)
su - Nouk -c "
    mkdir -p ~/.vnc
    rm -f ~/.vnc/passwd
    printf 'nouk1234\nnouk1234\nn\n' | vncpasswd
    chmod 600 ~/.vnc/passwd
"

# Set correct permissions
chown -R Nouk:Nouk /home/Nouk/.vnc

# Configure xrdp to connect to VNC on :1
cat > /etc/xrdp/xrdp.ini << 'EOF'
[globals]
bitmap_cache=true
bitmap_compression=true
port=3389
crypt_level=low
channel_code=1
max_bpp=24
fork=true

[xrdp1]
name=sesman-vnc
lib=libvnc.so
username=Nouk
password=ask
ip=127.0.0.1
port=5901
EOF

# Configure sesman for XFCE
cat > /etc/xrdp/sesman.ini << 'EOF'
[Globals]
ListenAddress=127.0.0.1
ListenPort=3350
EnableUserWindowManager=true
UserWindowManager=startwm.sh
DefaultWindowManager=startwm.sh

[Security]
AllowRootLogin=true
MaxLoginRetry=4
TerminalServerUsers=tsusers
TerminalServerAdmins=tsadmins

[Sessions]
MaxSessions=10
KillDisconnected=false
IdleTimeLimit=0
DisconnectedTimeLimit=0

[Logging]
LogFile=/var/log/xrdp-sesman.log
LogLevel=DEBUG
EnableSyslog=true
SyslogLevel=DEBUG

[Xvnc]
param=-bs
param=-nolisten
param=tcp
param=-localhost
param=-dpi
param=96
EOF

# Set startwm.sh for XFCE
cat > /etc/xrdp/startwm.sh << 'EOF'
#!/bin/sh
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi
exec /usr/bin/xfce4-session
EOF
chmod +x /etc/xrdp/startwm.sh

# Start Tailscale
if [ -n "${TAILSCALE_AUTHKEY}" ]; then
    echo "[*] Starting Tailscale..."
    tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
    sleep 3
    tailscale up --authkey="${TAILSCALE_AUTHKEY}" --accept-routes 2>/dev/null || true
    echo "[*] Tailscale started"
else
    echo "[!] TAILSCALE_AUTHKEY not set, skipping Tailscale"
fi

echo "[*] Starting supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
