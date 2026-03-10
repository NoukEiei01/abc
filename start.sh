#!/bin/bash

echo "[*] Starting Remote Desktop System..."
mkdir -p /var/log/supervisor

# Fix dbus
rm -f /run/dbus/pid
mkdir -p /run/dbus
chown messagebus:messagebus /run/dbus
/usr/bin/dbus-daemon --system --fork --nopidfile 2>/dev/null || true
sleep 1
echo "[*] dbus started"

# Clean stale X locks
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# รับ password จาก env var
VNC_PASS="${VNC_PASSWORD:-nouk1234}"
echo "[*] Setting VNC password..."

# สร้าง passwd ด้วย expect
mkdir -p /home/Nouk/.vnc
expect << EXPECTEOF
spawn su - Nouk -c "/usr/bin/tigervncserver -passwd /home/Nouk/.vnc/passwd"
expect "Password:"
send "${VNC_PASS}\r"
expect "Verify:"
send "${VNC_PASS}\r"
expect "view-only"
send "n\r"
expect eof
EXPECTEOF

# ถ้า expect ไม่ได้ผล fallback ใช้ python pyDes
if [ ! -s /home/Nouk/.vnc/passwd ]; then
    echo "[*] expect fallback to python..."
    python3 -c "
import pyDes, os
pwd = os.environ.get('VNC_PASSWORD', 'nouk1234')
def rbits(b): return int('{:08b}'.format(b)[::-1], 2)
key = bytes([rbits(ord(c)) for c in pwd[:8].ljust(8)])
d = pyDes.des(key, pyDes.ECB)
data = d.encrypt(b'\x00'*8)[:8]
open('/home/Nouk/.vnc/passwd','wb').write(data)
print('passwd:', data.hex())
"
fi

chmod 600 /home/Nouk/.vnc/passwd
chown -R Nouk:Nouk /home/Nouk/.vnc
touch /home/Nouk/.Xauthority
chown Nouk:Nouk /home/Nouk/.Xauthority
echo "[*] VNC passwd: $(stat -c%s /home/Nouk/.vnc/passwd) bytes"

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
    echo "[!] TAILSCALE_AUTHKEY not set"
fi

echo "[*] Starting supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
