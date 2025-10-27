#!/bin/sh
set -eu

log() {
    echo "[dietpi-custom] $*"
}

# Location of the env file on the boot partition
ENV_FILE="/boot/env"

# Check if env file exists
if [ ! -f "$ENV_FILE" ]; then
    log "WARNING: No env file found at $ENV_FILE"
    log "Skipping user management. Continuing with remaining setup..."
else
    # Load environment variables
    log "Loading environment variables from $ENV_FILE..."
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    
    # User management (only if PI_PASSWORD is set)
    if [ -n "${PI_PASSWORD:-}" ]; then
        log "PI_PASSWORD is set, proceeding with user management..."
        
        # Create 'pi' user with sudo privileges
        log "Creating user 'pi' with sudo privileges..."
        if ! id "pi" >/dev/null 2>&1; then
            # Create the user with a home directory
            useradd -m -s /bin/bash pi
            
            # Set the password from environment variable
            echo "pi:$PI_PASSWORD" | chpasswd
            
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
        
        # Configure bash aliases for 'pi' user
        log "Setting up bash aliases for user 'pi'..."
        if [ -f /home/pi/.bashrc ]; then
            # Check if aliases section already exists
            if ! grep -q "# Custom aliases added by DietPi automation" /home/pi/.bashrc; then
                cat >> /home/pi/.bashrc << 'EOF'

# Custom aliases added by DietPi automation
alias vi='vim'
alias ll='ls -altr'
alias docker='podman'
EOF
                log "Bash aliases added to /home/pi/.bashrc"
            else
                log "Bash aliases already present in /home/pi/.bashrc"
            fi
        else
            log "Warning: /home/pi/.bashrc not found"
        fi
        
        # Delete the 'dietpi' user if it exists
        if id "dietpi" >/dev/null 2>&1; then
            log "Deleting 'dietpi' user..."
            
            # Kill any processes owned by dietpi user
            pkill -u dietpi || true
            
            # Remove the user and their home directory
            userdel -r dietpi 2>/dev/null || userdel dietpi 2>/dev/null || true
            
            log "User 'dietpi' has been deleted"
        else
            log "User 'dietpi' does not exist, skipping deletion"
        fi
    else
        log "WARNING: PI_PASSWORD not set in $ENV_FILE"
        log "Skipping user management (pi user creation and dietpi user deletion)"
    fi
fi

# Tailscale setup
# Load env file if not already loaded (in case it was missing earlier)
if [ -f "$ENV_FILE" ] && [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    log "Loading environment variables for Tailscale setup..."
    # shellcheck disable=SC1090
    . "$ENV_FILE"
fi

if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    log "TAILSCALE_AUTHKEY not set; skipping Tailscale setup."
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


