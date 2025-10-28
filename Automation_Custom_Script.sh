#!/bin/sh
set -eu

log() {
    echo "[dietpi-custom] $*"
}

# Location of the env file on the boot partition
ENV_FILE="/boot/firmware/env"

# Check if env file exists
if [ ! -f "$ENV_FILE" ]; then
    log "WARNING: No env file found at $ENV_FILE"
    log "Skipping user management. Continuing with remaining setup..."
else
    # Load environment variables
    log "Loading environment variables from $ENV_FILE..."
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    
    # User management (only if USER_NAME and USER_PASSWORD are set)
    if [ -n "${USER_NAME:-}" ] && [ -n "${USER_PASSWORD:-}" ]; then
        log "USER_NAME and USER_PASSWORD are set, proceeding with user management..."
        
        # Create user with sudo privileges
        log "Creating user '$USER_NAME' with sudo privileges..."
        if ! id "$USER_NAME" >/dev/null 2>&1; then
            # Create the user with a home directory
            useradd -m -s /bin/bash "$USER_NAME"
            
            # Set the password from environment variable
            echo "$USER_NAME:$USER_PASSWORD" | chpasswd
            
            # Add user to sudo group
            usermod -aG sudo "$USER_NAME"
            
            # Ensure sudo group has proper permissions
            if ! grep -q "^%sudo" /etc/sudoers; then
                echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers
            fi
            
            log "User '$USER_NAME' created successfully with sudo privileges"
        else
            log "User '$USER_NAME' already exists, ensuring sudo privileges..."
            usermod -aG sudo "$USER_NAME"
        fi
        
        # Configure bash aliases for the user
        log "Setting up bash aliases for user '$USER_NAME'..."
        USER_HOME="/home/$USER_NAME"
        if [ -f "$USER_HOME/.bashrc" ]; then
            # Check if aliases section already exists
            if ! grep -q "# Custom aliases added by DietPi automation" "$USER_HOME/.bashrc"; then
                cat >> "$USER_HOME/.bashrc" << 'EOF'

# Custom aliases added by DietPi automation
alias vi='vim'
alias ll='ls -altr'
alias docker='podman'
EOF
                log "Bash aliases added to $USER_HOME/.bashrc"
            else
                log "Bash aliases already present in $USER_HOME/.bashrc"
            fi
        else
            log "Warning: $USER_HOME/.bashrc not found"
        fi
        
        # Disable SSH login for 'dietpi' user if it exists
        if id "dietpi" >/dev/null 2>&1; then
            log "Disabling SSH login for 'dietpi' user..."
            
            # Set shell to nologin (prevents any interactive login)
            usermod -s $(which nologin) dietpi
            
            log "User 'dietpi' has been locked and cannot login via SSH"
        else
            log "User 'dietpi' does not exist, skipping"
        fi
    else
        log "WARNING: USER_NAME and/or USER_PASSWORD not set in $ENV_FILE"
        log "Skipping user management (user creation and dietpi user disabling)"
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


