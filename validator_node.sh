#!/bin/bash

set -e

# Variables
EMAIL="hi@fx.land"  # <-- Modify this as needed
RPC_PORT="9944" # <-- This will be adjusted based on VALIDATOR_NO
PORT="30334" # <-- This will be adjusted based on VALIDATOR_NO

# Parameters
USER="ubuntu" # <-- set with --user or eliminate for ubuntu
VALIDATOR_NO="" # <-- set with --validator or eliminate for 01
PASSWORD="" # <-- set with --password  or eliminate for a random password
NODE_DOMAIN="" # <-- set with --domain or eliminate
BOOTSTRAP_NODE="" # <-- set with --bootnodes or eliminate

# Function to show usage
usage() {
    echo "Usage: $0 --user=ubuntu --password=12345 --validator=01 --domain=test.fx.land --bootnodes=/ip4/127.0.0.1/tcp/30334/p2p/12D3KooWBeXV65svCyknCvG1yLxXVFwRxzBLqvBJnUF6W84BLugv"
    exit 1
}

# Parse named parameters
while [ "$1" != "" ]; do
    case $1 in
        --password=*)
            PASSWORD="${1#*=}"
            ;;
        --validator=*)
            VALIDATOR_NO="${1#*=}"
            ;;
        --user=*)
            USER="${1#*=}"
            ;;
        --domain=*)
            NODE_DOMAIN="${1#*=}"
            ;;
        --bootnodes=*)
            BOOTSTRAP_NODE="${1#*=}"
            ;;
        *)
            usage
            ;;
    esac
    shift
done

if [ -z "$NODE_DOMAIN" ]; then
    echo "missing domain parameter. Skipping the domain handling"
fi

if [ -z "$VALIDATOR_NO" ]; then
    echo "missing VALIDATOR_NO parameter. using 01 as default"
    VALIDATOR_NO="01"
fi

# Function to calculate the RPC port based on the validator number
calculate_rpc_port() {
    local base_port=9944
    # Convert VALIDATOR_NO to a decimal number to handle leading zeros
    local num
    num=$(printf "%d" "$VALIDATOR_NO")
    # Calculate the offset (subtract 1 so VALIDATOR_NO "01" corresponds to offset 0)
    local offset=$((num - 1))
    # Calculate and echo the RPC port
    local rpc_port=$((base_port + offset))
    echo $rpc_port
}
# Function to calculate the port based on the validator number
calculate_port() {
    local base_port=30334
    # Convert VALIDATOR_NO to a decimal number to handle leading zeros
    local num
    num=$(printf "%d" "$VALIDATOR_NO")
    # Calculate the offset (subtract 1 so VALIDATOR_NO "01" corresponds to offset 0)
    local offset=$((num - 1))
    # Calculate and echo the RPC port
    local port=$((base_port + offset))
    echo $port
}

RPC_PORT=$(calculate_rpc_port)
PORT=$(calculate_port)
KEYS_INFO_PATH="/home/$USER/keys$VALIDATOR_NO.info"
BASE_DIR="/home/$USER/.sugarfunge-node"
SECRET_DIR="$BASE_DIR/passwords$VALIDATOR_NO"
DATA_DIR="/uniondrive/data$VALIDATOR_NO"
KEYS_DIR="$BASE_DIR/keys/node$VALIDATOR_NO"
LOG_DIR="/var/log"

# Check if all parameters are provided
if [ -z "$PASSWORD" ]; then
    if [ ! -f "$SECRET_DIR/password.txt" ]; then
        PASSWORD=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 25)
        echo "missing PASSWORD parameter. generating one: $PASSWORD"
    else
        echo "Password already exists"
    fi
fi

# Ensure required directories exist
mkdir -p "$SECRET_DIR" "$DATA_DIR" "$KEYS_DIR" "$LOG_DIR"
sudo chmod -R +r "$BASE_DIR"

# Function to read keys from file and save to variables
read_keys_from_file() {
    if [ ! -f "$KEYS_INFO_PATH" ]; then
        echo "Error: keys file does not exist at $KEYS_INFO_PATH."
        exit 1
    fi

    SECRET_PHRASE=$(awk -F': ' '/Secret phrase:/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' "$KEYS_INFO_PATH")
    SECRET_SEED=$(awk -F': ' '/Secret seed:/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' "$KEYS_INFO_PATH")
    PUBLIC_KEY_SS58=$(awk -F': ' '/Public key \(SS58\):/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' "$KEYS_INFO_PATH")
    PEER_ID=$(awk -F': ' '/peerID:/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' "$KEYS_INFO_PATH")
    NODE_KEY=$(awk -F': ' '/nodeKey:/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' "$KEYS_INFO_PATH")
    echo "Secret Phrase: $SECRET_PHRASE"
    echo "Secret Seed: $SECRET_SEED"
    echo "Public Key (SS58): $PUBLIC_KEY_SS58"
    echo "Peer ID: $PEER_ID"
    echo "Node Key: $NODE_KEY"


    # Save the extracted values to respective files for later use
    echo -n "${SECRET_PHRASE##*( )}" | sed 's/ *$//' > "$SECRET_DIR/secret_phrase.txt"
    echo -n "${SECRET_SEED##*( )}" | sed 's/ *$//' > "$SECRET_DIR/secret_seed.txt"
    echo -n "${PUBLIC_KEY_SS58##*( )}" | sed 's/ *$//' > "$SECRET_DIR/account.txt"
    echo -n "${PASSWORD##*( )}" | sed 's/ *$//' > "$SECRET_DIR/password.txt"
    echo -n "${PEER_ID##*( )}" | sed 's/ *$//' > "$SECRET_DIR/node_peerid.txt"
    echo -n "${NODE_KEY##*( )}" | sed 's/ *$//' > "$SECRET_DIR/node_key.txt"
}

# Function to insert keys into the node (Aura and Grandpa accounts)
insert_keys() {
    echo "insert_keys"
    # Clear the keys directory
    sudo rm -rf "$KEYS_DIR"

    # Insert the keys
    suri=$(cat "${SECRET_DIR}/secret_phrase.txt" | tr -d '\r\n')
    password=$(cat "${SECRET_DIR}/password.txt" | tr -d '\r\n')

    /home/$USER/sugarfunge-node/target/release/sugarfunge-node key insert --base-path="$DATA_DIR" --keystore-path="$KEYS_DIR" --chain "/home/${USER}/sugarfunge-node/customSpecRaw.json" --scheme Sr25519 --suri "$suri" --password "$password" --key-type aura
    /home/$USER/sugarfunge-node/target/release/sugarfunge-node key insert --base-path="$DATA_DIR" --keystore-path="$KEYS_DIR" --chain "/home/${USER}/sugarfunge-node/customSpecRaw.json" --scheme Ed25519 --suri "$suri" --password "$password" --key-type gran
}

# Function to setup and start node service (modify the existing function)
setup_node_service() {
    node_service_file_path="/etc/systemd/system/sugarfunge-node$VALIDATOR_NO.service"
    echo "Setting up node service at $node_service_file_path"
    
    # Check if the file exists and then remove it
    if [ -f "$node_service_file_path" ]; then
        sudo systemctl stop sugarfunge-node$VALIDATOR_NO.service
        sudo systemctl disable sugarfunge-node$VALIDATOR_NO.service
        sudo rm "$node_service_file_path"
        sudo systemctl daemon-reload
        echo "Removed $node_service_file_path."
    else
        echo "$node_service_file_path does not exist."
    fi

    # Construct the ExecStart command
    NODE_KEY=$(cat "$SECRET_DIR/node_key.txt")
    EXEC_START="/usr/bin/docker run -u root --rm --name MyNode$VALIDATOR_NO \
--network host \
--log-driver=json-file \
--log-opt max-size=10m \
--log-opt max-file=5 \
-v $SECRET_DIR/password.txt:/password.txt \
-v $KEYS_DIR:/keys \
-v $DATA_DIR:/data \
functionland/sugarfunge-node:amd64-latest \
--chain /customSpecRaw.json \
--enable-offchain-indexing true \
--base-path=/data \
--keystore-path=/keys \
--port=$PORT \
--rpc-port $RPC_PORT \
--rpc-cors=all \
--rpc-methods=Unsafe \
--rpc-external \
--validator \
--name Node$VALIDATOR_NO \
--password-filename=\"/password.txt\" \
--node-key=$NODE_KEY \
--pruning archive"

    # Add bootnodes parameter if provided
    if [ ! -z "$BOOTSTRAP_NODE" ]; then
        EXEC_START="$EXEC_START --bootnodes $BOOTSTRAP_NODE"
    fi
    
    # Use the variables instead of hardcoded values
    sudo bash -c "cat > '$node_service_file_path'" << EOF
[Unit]
Description=Sugarfunge Node
After=network.target

[Service]
Type=simple
User=root
ExecStart=$EXEC_START
Restart=always
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4
StandardOutput=file:${LOG_DIR}/Node${VALIDATOR_NO}.log
StandardError=file:${LOG_DIR}/Node${VALIDATOR_NO}.err

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable sugarfunge-node$VALIDATOR_NO.service
    sudo systemctl start sugarfunge-node$VALIDATOR_NO.service
    echo "Node service has been set up and started."
}

# Function to install required packages
install_packages() {
    sudo apt-get update -qq
    sudo apt-get install -y docker.io nginx software-properties-common certbot python3-certbot-nginx
    sudo apt-get install -y wget git curl build-essential jq pkg-config libssl-dev protobuf-compiler llvm libclang-dev clang plocate cmake
    sudo systemctl start docker
    sudo systemctl enable docker
}


# Function to pull the required Docker image and verify
pull_docker_images() {
    echo "Pulling the required Docker images..."
    sudo docker pull functionland/sugarfunge-node:amd64-latest

    # Check if the image was pulled successfully
    if sudo docker images | grep -q 'functionland/sugarfunge-node'; then
        echo "Docker image pulled successfully."
    else
        echo "Error: Docker image pull failed."
        exit 1
    fi
}

# Function to configure NGINX for WSS
configure_nginx_for_wss() {
    echo "Configuring NGINX for WS..."

    # Variables
    NGINX_CONF="/etc/nginx/sites-available/default"

    # Create a backup of the original default config
    sudo cp "$NGINX_CONF" "$NGINX_CONF.bak"

    # Check if the domain is already in the NGINX configuration
    if ! grep -q "$NODE_DOMAIN" "$NGINX_CONF"; then
        echo "Adding new WSS server configuration to NGINX..."

        # Define the new server block configuration
        NEW_WSS_SERVER_BLOCK=$(cat <<EOF

server {
    listen 80;
    server_name $NODE_DOMAIN; # Replace with your domain name

    location / {
        proxy_pass http://127.0.0.1:$RPC_PORT; # Replace with the port number of your WebSocket service
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;

        # WebSocket specific settings
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400; # 24 hours timeout
    }
}
EOF
        )

        # Append the new WSS server block to the NGINX configuration
        echo "$NEW_WSS_SERVER_BLOCK" | sudo tee -a "$NGINX_CONF"

        # Test and reload NGINX
        sudo nginx -t && sudo systemctl reload nginx
        echo "New WSS server configuration added and NGINX reloaded."
    else
        echo "The server name $NODE_DOMAIN already exists in the NGINX configuration."
    fi
}


# Function to obtain SSL certificates from Let's Encrypt
obtain_ssl_certificates() {
    echo "Obtaining SSL certificates from Let's Encrypt for $NODE_DOMAIN..."

    # Obtain the certificate (this also modifies the Nginx config for you)
    sudo certbot --nginx -m "$EMAIL" --agree-tos --no-eff-email -d "$NODE_DOMAIN" --redirect --keep-until-expiring --non-interactive
}

# Function to set LIBCLANG_PATH for the user
set_libclang_path() {
    if ! grep -q 'export LIBCLANG_PATH=/usr/lib/llvm-14/lib/' ~/.profile; then
        echo "export LIBCLANG_PATH=/usr/lib/llvm-14/lib/" >> ~/.profile
    fi

    source ~/.profile
}

# Function to configure automatic SSL certificate renewal
configure_auto_ssl_renewal() {
    # Unique identifier for the cron job
    CRON_IDENTIFIER="#AUTO_SSL_RENEWAL"

    # Write out the current crontab for the root user
    sudo crontab -l > mycron || true  # The 'true' ensures that the script doesn't exit if crontab is empty

    # Check if the cron job already exists
    if ! grep -q "$CRON_IDENTIFIER" mycron; then
        # Echo new cron into cron file. Schedule the job to run at 2:30 AM daily. Adjust the timing as needed.
        echo "30 2 * * * sudo certbot renew --post-hook 'systemctl reload nginx' $CRON_IDENTIFIER" >> mycron

        # Install new cron file for the root user
        sudo crontab mycron
        echo "Cron job for SSL certificate renewal has been set up."
    else
        echo "Cron job for SSL certificate renewal already exists."
    fi

    # Clean up
    rm mycron
}

# Function to install Rust and Cargo
install_rust() {
	echo "Installing rust"
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
	
	rustup default stable
	rustup update nightly
	rustup update stable
	rustup target add wasm32-unknown-unknown --toolchain nightly
	rustup target add wasm32-unknown-unknown
}

# Function to clone and build repositories
clone_and_build() {
	echo "Installing sugarfunge-node"
    if [ ! -d "/home/${USER}/sugarfunge-node" ] || [ -z "$(ls -A /home/${USER}/sugarfunge-node)" ]; then
        sudo git clone https://github.com/functionland/sugarfunge-node.git /home/${USER}/sugarfunge-node
    fi
    sudo chown -R ubuntu:ubuntu /home/${USER}/sugarfunge-node
    sudo chmod -R 777 /home/${USER}/sugarfunge-node
    cd /home/${USER}/sugarfunge-node
    cargo build --release
    cd ..
}

# Function to clean up after the script
cleanup() {
    echo "Cleaning up..."

    # Remove keys file
    if [ -f "$KEYS_INFO_PATH" ]; then
        echo "Removing $KEYS_INFO_PATH..."
        sudo rm "$KEYS_INFO_PATH"
    fi

    # Add other cleanup tasks here
}

# Function to check the status of services
check_services_status() {
    echo "Checking status of services..."

    # Define your services
    declare -a services=("sugarfunge-node$VALIDATOR_NO.service")

    # Initialize a flag to keep track of service status
    all_services_running=true

    for service in "${services[@]}"; do
        # Check the status of each service
        if ! sudo systemctl is-active --quiet "$service"; then
            echo "Error: Service $service is not running."
            all_services_running=false
        else
            echo "Service $service is running."
        fi
    done

    # Final check to see if any service wasn't running
    if [ "$all_services_running" = false ]; then
        echo "ERROR: One or more services are not running. Please check the logs for more details."
    else
        echo "OK All services are running as expected."
    fi
}

# Main script execution
main() {
    # Set the non-interactive frontend for APT
    # Set DEBIAN_FRONTEND to noninteractive to avoid interactive prompts
    export DEBIAN_FRONTEND=noninteractive
	echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/needrestart.conf

    echo "User: $USER is setting up Validator No: $VALIDATOR_NO on RPC PORT:$RPC_PORT with password:$PASSWORD"

    # Install required packages
    echo "Installing required packages"
    install_packages

    # Pull the required Docker image and verify
    echo "Pulling required docker images"
    pull_docker_images

    # Set LIBCLANG_PATH for the user
    echo "Setting required env paths"
    set_libclang_path

    # Install Rust and Cargo
    echo "Installing rust"
    install_rust

    # Clone and build the necessary repositories
    echo "Cloning and building libraries"
    clone_and_build

    # Read the keys from the file
    echo "Reading secret keys from the file"
    read_keys_from_file

    # Insert keys into the node
    echo "Inserting keys into node"
    insert_keys

    # Setup and start node service
    echo "Setting up node service"
    setup_node_service

    # Check if NODE_DOMAIN is not empty
    local NODE_ADDRESS
    if [ "$NODE_DOMAIN" != "" ]; then
        # Configure NGINX for WSS
        echo "Configuring wss"
        configure_nginx_for_wss

        # Obtain SSL certificates from Let's Encrypt
        echo "Obtaining SSL certificate"
        obtain_ssl_certificates

        # Configure automatic SSL certificate renewal
        echo "Configuring cronjob for auto SSL renewal"
        configure_auto_ssl_renewal
        NODE_ADDRESS="/dns4/node.functionyard.fula.network/tcp/$PORT/p2p/$PEER_ID"
    else
        echo "NODE_DOMAIN is not set. Skipping SSL and NGINX configuration."
        NODE_ADDRESS="/ip4/127.0.0.1/tcp/$PORT/p2p/$PEER_ID"
    fi

    # Check the status of the services
    echo "Check service status"
    check_services_status

    # Clean up after the script
    echo "Cleaning up"
    cleanup

    echo "Setup complete. Please review the logs and verify the services are running correctly."
    echo "Node address is: $NODE_ADDRESS"
    echo -n "Account is: "
    cat "$SECRET_DIR/account.txt"
    echo -n "Secret Key is: "
    cat "$SECRET_DIR/secret_seed.txt"
}

# Run the main function with the provided arguments
main "$@"
