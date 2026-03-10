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
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
su - Nouk -c "rm -f ~/.vnc/*.pid ~/.vnc/*:1* 2>/dev/null || true"

# สร้าง VNC passwd (8 bytes DES encrypted)
mkdir -p /home/Nouk/.vnc
python3 << 'PYEOF'
import struct, os, subprocess

def reverse_bits(b):
    result = 0
    for i in range(8):
        result |= ((b >> i) & 1) << (7 - i)
    return result

password = "nouk1234"
key = bytes([reverse_bits(ord(c)) for c in password[:8].ljust(8)])

result = subprocess.run(
    ['openssl', 'enc', '-des-ecb', '-nosalt', '-nopad', '-K', key.hex()],
    input=b'\x00' * 8,
    capture_output=True,
    timeout=5
)

if len(result.stdout) >= 8:
    passwd_data = result.stdout[:8]
else:
    passwd_data = bytes([0x68, 0x8d, 0x0b, 0x15, 0x1c, 0x93, 0x97, 0x63])

with open('/home/Nouk/.vnc/passwd', 'wb') as f:
    f.write(passwd_data)

print(f'VNC passwd: {len(passwd_data)} bytes → {passwd_data.hex()}')
PYEOF

chmod 600 /home/Nouk/.vnc/passwd
chown -R Nouk:Nouk /home/Nouk/.vnc
echo "[*] VNC passwd ready: $(ls -la /home/Nouk/.vnc/passwd)"

# สร้าง Xauthority
su - Nouk -c "touch ~/.Xauthority && chmod 600 ~/.Xauthority" 2>/dev/null || true

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
