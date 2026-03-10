#!/bin/bash
set -e

echo "[*] Starting Remote Desktop System..."

mkdir -p /var/log/supervisor

# Fix dbus
rm -f /run/dbus/pid
mkdir -p /run/dbus
chown messagebus:messagebus /run/dbus
/usr/bin/dbus-daemon --system --fork --nopidfile 2>/dev/null || true
sleep 2
echo "[*] dbus started"

# Clean stale VNC locks
rm -f /tmp/.X1-lock
rm -f /tmp/.X11-unix/X1
su - Nouk -c "rm -f ~/.vnc/*.pid ~/.vnc/*:1* 2>/dev/null || true"

# Set VNC password — หา binary ให้เจอก่อน
VNC_PASS_BIN=""
for bin in /usr/bin/tigervncpasswd /usr/bin/vncpasswd /usr/lib/tigervnc/vncpasswd; do
    if [ -x "$bin" ]; then
        VNC_PASS_BIN="$bin"
        break
    fi
done

echo "[*] vncpasswd binary: $VNC_PASS_BIN"

if [ -n "$VNC_PASS_BIN" ]; then
    su - Nouk -c "
        mkdir -p ~/.vnc
        rm -f ~/.vnc/passwd
        printf 'nouk1234\nnouk1234\nn\n' | $VNC_PASS_BIN
        chmod 600 ~/.vnc/passwd
    "
else
    # fallback: สร้าง passwd file ด้วย python3
    echo "[!] vncpasswd not found, using python fallback"
    su - Nouk -c "
        mkdir -p ~/.vnc
        python3 -c \"
import struct, hashlib, os
password = b'nouk1234'[:8]
password = password.ljust(8, b'\x00')
DES_KEY = bytes([23,82,107,6,35,78,88,7])
def des_encrypt(key, data):
    from itertools import product
    # simple DES via d3des
    result = bytearray()
    for i in range(8):
        b = 0
        for j in range(8):
            b |= ((key[i] >> j) & 1) << (7-j)
        result.append(b)
    return bytes(result)
import subprocess
result = subprocess.run(['openssl', 'enc', '-des-ecb', '-nosalt', '-nopad', '-K', key.hex(), '-in', '/dev/stdin'], input=password, capture_output=True)
with open(os.path.expanduser('~/.vnc/passwd'), 'wb') as f:
    f.write(result.stdout[:8])
\" 2>/dev/null || echo 'nouk1234' > ~/.vnc/passwd
        chmod 600 ~/.vnc/passwd
    "
fi

chown -R Nouk:Nouk /home/Nouk/.vnc
echo "[*] VNC password set"

# Configure xrdp
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

cat > /etc/xrdp/startwm.sh << 'EOF'
#!/bin/sh
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi
exec startxfce4
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
