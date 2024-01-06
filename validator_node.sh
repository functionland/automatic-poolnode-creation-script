#!/bin/bash

set -e

# Parameters
VALIDATOR_NO=""
PASSWORD=""
NODE_DOMAIN=""

# Variables
USER="ubuntu"
EMAIL="hi@fx.land"  # <-- Modify this as needed

# Function to show usage
usage() {
    echo "Usage: $0 --password=PASSWORD --validator=VALIDATOR_NO --domain=NODE_DOMAIN"
    exit 1
}

# Parse named parameters
while [ "$1" != "" ]; do
    case $1 in
        --password=*)  PASSWORD="${1#*=}" ;;
        --validator=*) VALIDATOR_NO="${1#*=}" ;;
        --domain=*) NODE_DOMAIN="${1#*=}" ;;
        *)             usage ;;
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

KEYS_INFO_PATH="/home/$USER/keys$VALIDATOR_NO.info"
BASE_DIR="/home/$USER/.sugarfunge-node"
SECRET_DIR="$BASE_DIR/passwords$VALIDATOR_NO"
DATA_DIR="$BASE_DIR/data/node$VALIDATOR_NO"
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

    while IFS= read -r line; do
        case "$line" in
            "Secret phrase:"*) SECRET_PHRASE="${line#*: }" ;;
            "Secret seed:"*) SECRET_SEED="${line#*: }" ;;
            "Public key (SS58):"*) PUBLIC_KEY_SS58="${line#*: }" ;;
            "peerID:"*) PEER_ID="${line#*: }" ;;
            "nodeKey:"*) NODE_KEY="${line#*: }" ;;
        esac
    done < "$KEYS_INFO_PATH"

    # Save the extracted values to respective files for later use
    echo "$SECRET_SEED" > "$SECRET_DIR/secret_seed.txt"
    echo "$PUBLIC_KEY_SS58" > "$SECRET_DIR/account.txt"
    echo "$PEER_ID" > "$SECRET_DIR/node_peerid.txt"
    echo "$NODE_KEY" > "$SECRET_DIR/node_key.txt"
    echo "$PASSWORD" > "$SECRET_DIR/password.txt"
}

# Function to insert keys into the node (Aura and Grandpa accounts)
insert_keys() {
    echo "insert_keys"
    /home/$USER/sugarfunge-node/target/release/sugarfunge-node key insert --base-path="$DATA_DIR" --keystore-path="$KEYS_DIR" --chain "$HOME/sugarfunge-node/customSpecRaw.json" --scheme Sr25519 --suri "$SECRET_PHRASE" --password-filename "$SECRET_DIR/password.txt" --key-type aura
    /home/$USER/sugarfunge-node/target/release/sugarfunge-node key insert --base-path="$DATA_DIR" --keystore-path="$KEYS_DIR" --chain "$HOME/sugarfunge-node/customSpecRaw.json" --scheme Ed25519 --suri "$SECRET_PHRASE" --password-filename "$SECRET_DIR/password.txt" --key-type gran
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
    
    # Use the variables instead of hardcoded values
    sudo bash -c "cat > '$node_service_file_path'" << EOF
[Unit]
Description=Sugarfunge Node
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/docker run -u root --rm --name MyNode$VALIDATOR_NO --network host -v $SECRET_DIR/password.txt:/password.txt -v $KEYS_DIR:/keys -v $KEYS_DIR:/keys -v $DATA_DIR:/data functionland/sugarfunge-node:amd64-latest --chain /customSpecRaw.json --enable-offchain-indexing true --base-path=/data --keystore-path=/keys --port=30334 --rpc-port 9944 --rpc-cors=all --rpc-methods=Unsafe --rpc-external --validator --name Node$VALIDATOR_NO --password-filename="/password.txt" --node-key=$NODE_KEY
Restart=always
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4
StandardOutput=file:"$LOG_DIR/Node$VALIDATOR_NO.log"
StandardError=file:"$LOG_DIR/Node$VALIDATOR_NO.err"

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
    echo "Configuring NGINX for WSS..."

    # Create a backup of the original default config
    sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak

    # Write the new configuration
    sudo bash -c 'cat > /etc/nginx/sites-available/default' << EOF
server {
    listen 443 ssl;
    server_name $NODE_DOMAIN; # Replace with your domain name

    ssl_certificate /etc/letsencrypt/live/$NODE_DOMAIN/fullchain.pem; # Replace with your SSL certificate path
    ssl_certificate_key /etc/letsencrypt/live/$NODE_DOMAIN/privkey.pem; # Replace with your SSL certificate key path

    location / {
        proxy_pass http://127.0.0.1:9944;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

    # Test and reload NGINX
    sudo nginx -t
    sudo systemctl reload nginx
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
    if [ ! -d "sugarfunge-node" ] || [ -z "$(ls -A sugarfunge-node)" ]; then
        git clone https://github.com/functionland/sugarfunge-node.git
    fi
    cd sugarfunge-node
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

    echo "Setting up for Validator No: $VALIDATOR_NO with password:$PASSWORD"

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
    if [ "$NODE_DOMAIN" != "" ]; then
        # Obtain SSL certificates from Let's Encrypt
        obtain_ssl_certificates

        # Configure NGINX for WSS
        configure_nginx_for_wss
    else
        echo "NODE_DOMAIN is not set. Skipping SSL and NGINX configuration."
    fi

    # Check the status of the services
    echo "Check service status"
    check_services_status

    # Clean up after the script
    echo "Cleaning up"
    cleanup

    echo "Setup complete. Please review the logs and verify the services are running correctly."
}

# Run the main function with the provided arguments
main "$@"
