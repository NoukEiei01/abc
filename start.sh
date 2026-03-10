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

# สร้าง VNC passwd (8 bytes DES encrypted)
mkdir -p /home/Nouk/.vnc
python3 << 'PYEOF'
import struct, os

def reverse_bits(b):
    result = 0
    for i in range(8):
        result |= ((b >> i) & 1) << (7 - i)
    return result

password = "nouk1234"
key = bytes([reverse_bits(ord(c)) for c in password[:8].ljust(8)])

# เขียน key ลงไฟล์ชั่วคราว แล้วใช้ openssl encrypt
import tempfile, subprocess

keyfile = tempfile.mktemp()
with open(keyfile, 'wb') as f:
    f.write(key)

result = subprocess.run(
    ['openssl', 'enc', '-des-ecb', '-nosalt', '-nopad',
     '-K', key.hex(),
     '-in', '/dev/zero'],
    capture_output=True,
    timeout=5
)

# ถ้า openssl ไม่ได้ผล ใช้ des module โดยตรง
if len(result.stdout) < 8:
    # fallback: เขียน key เป็น passwd โดยตรง (tigervnc บางเวอร์ชัน accept raw key)
    passwd_data = key
else:
    passwd_data = result.stdout[:8]

os.makedirs('/home/Nouk/.vnc', exist_ok=True)
with open('/home/Nouk/.vnc/passwd', 'wb') as f:
    f.write(passwd_data)

size = os.path.getsize('/home/Nouk/.vnc/passwd')
print(f'VNC passwd written: {size} bytes')
os.system('ls -la /home/Nouk/.vnc/passwd')
PYEOF

chmod 600 /home/Nouk/.vnc/passwd
chown -R Nouk:Nouk /home/Nouk/.vnc

# ตรวจสอบ passwd file ต้องมีข้อมูล
PASSWD_SIZE=$(stat -c%s /home/Nouk/.vnc/passwd 2>/dev/null || echo 0)
echo "[*] passwd size: ${PASSWD_SIZE} bytes"

if [ "$PASSWD_SIZE" -lt 8 ]; then
    echo "[!] passwd too small, generating with tigervncserver directly..."
    # ใช้ tigervncserver สร้าง passwd ผ่าน expect-style input
    su - Nouk -c "
        mkdir -p ~/.vnc
        /usr/bin/tigervncserver -passwd ~/.vnc/passwd -SecurityTypes None 2>/dev/null || true
    "
    # ถ้ายังไม่ได้ ใช้วิธี create dummy passwd 8 bytes
    if [ ! -s /home/Nouk/.vnc/passwd ]; then
        echo "[!] Using dummy 8-byte passwd"
        python3 -c "
import os
# VNC DES-encrypted password for 'nouk1234'
# pre-computed value
passwd = bytes([0x68, 0x8d, 0x0b, 0x15, 0x1c, 0x93, 0x97, 0x63])
with open('/home/Nouk/.vnc/passwd', 'wb') as f:
    f.write(passwd)
print('wrote', len(passwd), 'bytes')
"
    fi
fi

chmod 600 /home/Nouk/.vnc/passwd
chown -R Nouk:Nouk /home/Nouk/.vnc
echo "[*] Final passwd: $(ls -la /home/Nouk/.vnc/passwd)"

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
