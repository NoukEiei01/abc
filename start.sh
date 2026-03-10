#!/bin/bash
set -e

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

# Install pyDes แล้วสร้าง VNC passwd
pip3 install pyDes -q 2>/dev/null || true

mkdir -p /home/Nouk/.vnc
python3 << 'PYEOF'
import os

def vncEncryptPasswd(password):
    # VNC flips bits in each byte of the key
    flipped = []
    for c in password[:8].ljust(8):
        b = ord(c) if isinstance(c, str) else c
        flipped.append(int('{:08b}'.format(b)[::-1], 2))
    key = bytes(flipped)

    try:
        import pyDes
        d = pyDes.des(key, pyDes.ECB)
        encrypted = d.encrypt(b'\x00' * 8)
        return encrypted[:8]
    except ImportError:
        pass

    # fallback: openssl
    import subprocess
    r = subprocess.run(
        ['openssl', 'enc', '-des-ecb', '-nosalt', '-nopad', '-K', key.hex()],
        input=b'\x00' * 8, capture_output=True
    )
    if len(r.stdout) >= 8:
        return r.stdout[:8]

    return None

passwd = vncEncryptPasswd('nouk1234')
if passwd and len(passwd) == 8:
    with open('/home/Nouk/.vnc/passwd', 'wb') as f:
        f.write(passwd)
    print(f'VNC passwd OK: {passwd.hex()}')
else:
    print('ERROR: failed to generate passwd')
    exit(1)
PYEOF

chmod 600 /home/Nouk/.vnc/passwd
chown -R Nouk:Nouk /home/Nouk/.vnc
touch /home/Nouk/.Xauthority
chown Nouk:Nouk /home/Nouk/.Xauthority
echo "[*] VNC passwd: $(stat -c%s /home/Nouk/.vnc/passwd) bytes → $(xxd -p /home/Nouk/.vnc/passwd)"

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
