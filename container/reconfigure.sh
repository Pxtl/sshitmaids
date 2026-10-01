#!/usr/bin/env bash
set -e

dest="$1"

# Split dest_user@rest_of_dest
dest_user="${dest%@*}"
rest_of_dest="${dest#*@}"

if [ -z $dest ] || [[ "$dest" != *@* ]]; then
    echo "Usage: reconfigure <username@host[:port]>"
    exit 1
fi

###############################################################################
echo "1. Parsing argument and env vars..."
###############################################################################

# Split rest_of_dest:dest_port if dest_port is provided.
if [[ "$rest_of_dest" == *:* ]]; then
    dest_host="${rest_of_dest%%:*}"
    dest_port="${rest_of_dest#*:}"
else
    dest_host="$rest_of_dest"
    dest_port="22"
fi

# initialize CLIENT_DEST if not set.
CLIENT_DEST="${CLIENT_DEST:-git@sshitmaids:22}"

mitm_dir="/root/sshitmaids"
client_dir="/root/ssh-client"
user_dir="/home/$dest_user"

# Validate port is numeric
if ! echo "$dest_port" | grep -Eq '^[0-9]+$'; then
    echo "Error: Port '$dest_port' is not a valid number"
    exit 1
fi

echo "  Parsed.\n"
echo "  Starting reconfigure container for '$dest_host:$dest_port'."
echo "  ========================================================================"

###############################################################################
echo ""
echo "2. Ensure volume directories exist..."
###############################################################################
mkdir -p "$mitm_dir" "$client_dir"

###############################################################################
echo "3. Creating keys where they do not exist..."
###############################################################################

# If the host SSH keys are not already stored in the persistant volume, 
# back them up to there.
if [ ! -f "$mitm_dir/ssh_host_ed25519_key" ]; then
    ssh-keygen -A
    cp /etc/ssh/ssh_host_* "$mitm_dir"
fi
# Next deploy those host SSH keys from the persistent volume back into the
# ephemeral /etc dir.
cp "$mitm_dir"/ssh_host_* /etc/ssh

# Generate keys for ssh clients (both the end-client and sshitmaids itself).
if [ ! -f "$mitm_dir/id_ed25519_upstream" ]; then
    ssh-keygen -t ed25519 -C "sshitmaids" -N '' -f "$mitm_dir/id_ed25519_upstream"
fi
if [ "$GENERATE_CLIENT_CONFIG" = "true" ] && [ ! -f "$client_dir/id_ed25519.pub" ]; then
    ssh-keygen -t ed25519 -C "sshitmaids-client" -N '' -f "$client_dir/id_ed25519"
fi

###############################################################################
echo ""
echo "4. Building mitm authorized_keys from all client and mitm .pub keys..."
###############################################################################
: > "$mitm_dir/authorized_keys" >&/dev/null #truncate file

# Append each .pub file from both volumes, so the server can accept connetions
# from others and, theoretically, itself.
for pub in "$mitm_dir"/*.pub; do
    [ -e "$pub" ] || continue
    cat "$pub" >> "$mitm_dir/authorized_keys"
done
for pub in "$client_dir"/*.pub; do
    [ -e "$pub" ] || continue
    cat "$pub" >> "$mitm_dir/authorized_keys"
done

echo "   mitm's .ssh/authorized_keys built"

###############################################################################
echo ""
echo "5. Writing SSH config for MITM ($dest_user user)..."
###############################################################################
cat > "$mitm_dir/config" <<EOF
Host dest
    HostName $dest_host
    Port $dest_port
    User $dest_user
    IdentityFile "$user_dir/.ssh/id_ed25519_upstream"
    UserKnownHostsFile "$user_dir/.ssh/known_hosts"
    StrictHostKeyChecking yes
EOF

###############################################################################
echo ""
echo "6. Writing known_hosts for MITM..."
###############################################################################
if [ "$DO_KEYSCAN" = "true" ]; then
    ssh-keyscan -p "$dest_port" "$dest_host" > /tmp/known_hosts_tmp 2>/dev/null || true
    if [ ! -s /tmp/known_hosts_tmp ]; then
        rm -f /tmp/known_hosts_tmp
        echo "   WARNING: Keyscan returned empty file. Probably rate-limited." >&2
    else
        mv /tmp/known_hosts_tmp "$mitm_dir/known_hosts"
        echo "   $dest_host keyscanned and saved to known_hosts."
    fi
else
    touch "$mitm_dir/known_hosts"
    echo "   Skipping keyscan to prevent rate limiting."
fi

###############################################################################
echo ""
echo "7. Ensuring root user ephemeral .ssh dir..."
###############################################################################
# NOTE: .ssh dirs inside /home/$dest_user and /root are ephemeral The
# "master" copies of SSH keys and config live in the bound volume dirs:
#   - /root/sshitmaids/ 
#   - /root/ssh-client/
#
# This is intentional so secrets/config are managed externally and persist
# across containers.

# Setup root .ssh (if not exists)
if [ ! -d /root/.ssh ]; then
    mkdir -p /root/.ssh
fi

# Copy MITM keys to root's .ssh (if not already copied)
if [ -d "$mitm_dir" ]; then
    cp -f "$mitm_dir"/* /root/.ssh/ 2>/dev/null || true
fi

###############################################################################
echo ""
echo "8. Ensuring $dest_user & ephemeral .ssh dir..."
###############################################################################

if [ ! -d "$user_dir" ]; then
    echo "  Creating home directory for $dest_user user..."
    mkdir -p "$user_dir" 2>/dev/null
else
    echo "  $dest_user home directory exists."
fi
if [ -z "$(id $dest_user 2>/dev/null)" ]; then
    echo "   Creating $dest_user user..."
    useradd -m -G $dest_user -s /bin/bash $dest_user 2>/dev/null || true
fi

# Setup $dest_user .ssh directory
mkdir -p "$user_dir/.ssh"
rm -rf "$user_dir/.ssh"/*

user_ssh_files=(
  "$mitm_dir/config"
  "$mitm_dir/known_hosts"
  "$mitm_dir/authorized_keys"
  "$mitm_dir/id_ed25519_upstream"
)
cp "${user_ssh_files[@]}" "$user_dir/.ssh/"

###############################################################################
echo ""
echo "9. Fixing SSH permissions..."
###############################################################################
echo "   for root..."
chown -R root:root /root/.ssh
chmod 700 /root/.ssh
# Ideally use find so empty globs don't need || true, which can hide real errors.
# Keep the glob form here for legibility.
chmod 600 /root/.ssh/* 2>/dev/null || true

echo "   and $dest_user..."
chown -R "$dest_user:$dest_user" "$user_dir/.ssh"
chmod 700 "$user_dir/.ssh"
chmod 600 "$user_dir/.ssh"/* 2>/dev/null || true

###############################################################################
echo ""
echo "10. Configure sshd for $dest_user user..."
###############################################################################
if ! grep -q "Match User $dest_user" /etc/ssh/sshd_config; then
    echo "  Adding Match User $dest_user block to /etc/ssh/sshd_config..."
    printf "\nMatch User $dest_user\n    ForceCommand /usr/local/bin/dest-mitm\n" >> /etc/ssh/sshd_config
    echo "   Match User $dest_user block added to sshd_config."
else
    echo "   Match User $dest_user block already exists in sshd_config."
fi

###############################################################################
echo ""
echo "11. Client configuration (SSH config and known_hosts)..."
###############################################################################
if [ "$GENERATE_CLIENT_CONFIG" = "true" ]; then   
    # Split client_dest_user@rest_of_dest
    client_dest_user="${CLIENT_DEST%@*}"
    rest_of_client_dest="${CLIENT_DEST#*@}"

    # Split rest_of_dest:dest_port if dest_port is provided.
    if [[ "$rest_of_client_dest" == *:* ]]; then
        client_dest_host="${rest_of_client_dest%%:*}"
        client_dest_port="${rest_of_client_dest#*:}"
    else
        client_dest_host="$rest_of_client_dest"
        client_dest_port="22"
    fi
    cat > "$client_dir/config" <<EOF
Host $dest_host
    HostName $client_dest_host
    Port $client_dest_port
    User $client_dest_user
    IdentityFile ~/.ssh/id_ed25519
EOF
    echo "   client ssh config generated."

    # Client known_hosts
    : > "$client_dir/known_hosts" #wipe
    for key in /etc/ssh/ssh_host_*_key.pub; do
        echo "# $CLIENT_DEST ($(basename $key))" >> $client_dir/known_hosts
        echo "$client_dest_host $(cat "$key")" >> $client_dir/known_hosts
    done
else
    echo "   Skipping client config (SSHITMAIDS_GENERATE_CLIENT_CONFIG not 'true')."
    # Create client known_hosts even if config not generated
    touch "$client_dir/known_hosts"
fi

###############################################################################
echo ""
echo "12. Starting SSHD to listen for client connections..."
###############################################################################
# sshd will start in background mode, logging to '/var/log/sshd.log'.
# This is re-runnable.
/usr/sbin/sshd -E /var/log/sshd.log
echo "   SSHD started (running in background)."

###############################################################################
echo ""
echo "13. Done reconfiguring for $dest_host:$dest_port"
###############################################################################