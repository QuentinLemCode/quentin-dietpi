#!/bin/sh
set -eu

# Location of the env file on the boot partition
ENV_FILE="/boot/.env"

log() {
    echo "[dietpi-custom] $*"
}

# Create 'pi' user with sudo privileges
log "Creating user 'pi' with sudo privileges..."
if ! id "pi" >/dev/null 2>&1; then
    # Create the user with a home directory
    useradd -m -s /bin/bash pi
    
    # Set the same password as the global password (from AUTO_SETUP_GLOBAL_PASSWORD in dietpi.txt)
    # The password will be 'dietpi' by default unless changed in dietpi.txt
    echo "pi:dietpi" | chpasswd
    
    # Add user to sudo group
    usermod -aG sudo pi
    
    # Ensure sudo group has proper permissions
    if ! grep -q "^%sudo" /etc/sudoers; then
        echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers
    fi
    
    log "User 'pi' created successfully with sudo privileges"
else
    log "User 'pi' already exists, ensuring sudo privileges..."
    usermod -aG sudo pi
fi

if [ ! -f "$ENV_FILE" ]; then
    log "No .env found at $ENV_FILE; skipping Tailscale setup."
    exit 0
fi

# shellcheck disable=SC1090
. "$ENV_FILE"

if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    log "TAILSCALE_AUTHKEY not set in $ENV_FILE; skipping Tailscale login."
    exit 0
fi

log "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

log "Enabling and starting tailscaled..."
systemctl enable --now tailscaled

# Login non-interactively with auth key; use hostname from DietPi config
HOSTNAME_VAL="$(hostname)"
log "Logging into Tailscale as $HOSTNAME_VAL..."
tailscale up --authkey "$TAILSCALE_AUTHKEY" --hostname "$HOSTNAME_VAL" --ssh --reset || tailscale up --authkey "$TAILSCALE_AUTHKEY" --hostname "$HOSTNAME_VAL" --ssh

log "Tailscale setup complete. IP: $(tailscale ip -4 2>/dev/null || true)"

exit 0


