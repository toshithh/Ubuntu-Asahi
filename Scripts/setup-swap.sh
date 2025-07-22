#!/bin/bash

set -e

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SWAPFILE="/swapfile"
FSTAB="/etc/fstab"
ZRAMSERVICE="/etc/default/zramswap"
ZRAM_PERCENT="50"
ZRAM_ALGO="zstd"
ZRAM_PRIORITY="100"

echo "[*] Checking ZRAM configuration..."

# If zramswap config doesn't exist, create it with sane defaults
if [ ! -f "$ZRAMSERVICE" ]; then
    echo "[+] Creating $ZRAMSERVICE..."
    cat <<EOF > "$ZRAMSERVICE"
ENABLED=true
ALGO=$ZRAM_ALGO
PERCENT=$ZRAM_PERCENT
PRIORITY=$ZRAM_PRIORITY
ZRAM_MAX=0
EOF
else
    echo "[=] ZRAM config already exists."
fi

# Ensure zramswap.service is enabled and running
if ! systemctl is-active --quiet zramswap.service; then
    echo "[+] Enabling and starting zramswap.service..."
    systemctl enable --now zramswap.service
else
    echo "[=] ZRAM service is already active."
fi

# ------------------ Swapfile Setup ------------------

# Get available space in MB on root filesystem
AVAILABLE_MB=$(df --output=avail / | tail -n1)

# Decide swap size
if [ "$AVAILABLE_MB" -ge 10240 ]; then
    SWAPSIZE="8G"
elif [ "$AVAILABLE_MB" -ge 5120 ]; then
    SWAPSIZE="4G"
else
    echo "[!] Not enough disk space for swapfile. Skipping."
    exit 0
fi

echo "[*] Available disk: $((AVAILABLE_MB / 1024)) MB → Swapfile: $SWAPSIZE"
echo "[*] Checking for swapfile at $SWAPFILE..."

# Create swapfile if it doesn't exist
if [ ! -f "$SWAPFILE" ]; then
    echo "[+] Creating swapfile..."
    fallocate -l "$SWAPSIZE" "$SWAPFILE" || dd if=/dev/zero of="$SWAPFILE" bs=1M count=$(( $(echo "$SWAPSIZE" | sed 's/G/*1024/' | bc) ))
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE"
else
    echo "[=] Swapfile already exists."
fi

# Enable the swapfile if not active
if ! swapon --show | awk '{print $1}' | grep -Fxq "$SWAPFILE"; then
    echo "[+] Enabling swapfile..."
    swapon "$SWAPFILE"
else
    echo "[=] Swapfile is already active."
fi

# Ensure it's in /etc/fstab
if ! grep -q "$SWAPFILE" "$FSTAB"; then
    echo "[+] Adding swapfile to $FSTAB..."
    echo "$SWAPFILE none swap sw,pri=-2 0 0" >> "$FSTAB"
else
    echo "[=] Swapfile already in $FSTAB."
fi

echo "[✓] ZRAM and swapfile setup complete."
