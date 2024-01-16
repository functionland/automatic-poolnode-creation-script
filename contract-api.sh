#!/bin/bash

set -e

# Default Variables
USER="ubuntu" # Modify as needed or set with --user
NODE_SERVER_WS="" # Set with --node
RELEASE_FLAG="" # Set with --release for production build
DOMAIN="" # Set with --domain

# Function to show usage
usage() {
    echo "Usage: $0 --user=ubuntu --node=wss://example.com --release --domain=yourdomain.com"
    exit 1
}

# Parse named parameters
while [ "$1" != "" ]; do
    case $1 in
        --user=*)
            USER="${1#*=}"
            ;;
        --node=*)
            NODE_SERVER_WS="${1#*=}"
            ;;
        --release)
            RELEASE_FLAG="--release"
            ;;
        --domain=*)
            DOMAIN="${1#*=}"
            ;;
        *)
            usage
            ;;
    esac
    shift
done

# Validate required parameters
if [ -z "$NODE_SERVER_WS" ]; then
    echo "Error: node parameter is required."
    usage
fi

if [ -z "$DOMAIN" ]; then
    echo "Error: Domain parameter is required."
    usage
fi

# Function to install necessary packages
install_packages() {
    echo "Installing necessary packages..."
    sudo apt-get update -qq
    sudo apt-get install -y git curl wget build-essential software-properties-common
}

# Function to install Rust
install_rust() {
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
}

# Function to clone the fula-contract-api repository
clone_repository() {
    echo "Cloning the fula-contract-api repository..."
    git clone https://github.com/functionland/fula-contract-api.git "/home/$USER/fula-contract-api"
}

# Function to set up the .env file
setup_env_file() {
    echo "Setting up the .env file..."
    cp "/home/$USER/fula-contract-api/.env.example" "/home/$USER/fula-contract-api/.env"
}

# Function to build the project
build_project() {
    echo "Building the fula-contract-api project..."
    cd "/home/$USER/fula-contract-api"
    if [ ! -z "$RELEASE_FLAG" ]; then
        cargo build --release
    else
        cargo build
    fi
}

# Function to configure NGINX and SSL
configure_nginx_ssl() {
    echo "Configuring NGINX and SSL for $DOMAIN..."

    # Install NGINX and Certbot
    sudo apt-get install -y nginx certbot python3-certbot-nginx

    # Configure NGINX for the domain
    sudo bash -c "cat > /etc/nginx/sites-available/default" << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:4001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

    # Enable the configuration and restart NGINX
    sudo systemctl reload nginx

    # Obtain SSL certificate
    sudo certbot --nginx -d $DOMAIN -m $USER@example.com --agree-tos -n --redirect
}

# Function to create and enable the service
setup_service() {
    BUILD_TYPE="debug"
    if [ "$RELEASE_FLAG" == "--release" ]; then
        BUILD_TYPE="release"
    fi

    SERVICE_FILE="/etc/systemd/system/fula-contract-api.service"
    echo "Creating the service file at $SERVICE_FILE..."

    sudo bash -c "cat > '$SERVICE_FILE'" << EOF
[Unit]
Description=Fula Contract API

[Service]
TimeoutStartSec=0
Type=simple
User=root
ExecStart=/home/$USER/fula-contract-api/target/$BUILD_TYPE/functionland-contract-api --node-server=$NODE_SERVER_WS --listen http://127.0.0.1:4001
Restart=always
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4
StandardOutput=file:/var/log/fula-contract-api.log
StandardError=file:/var/log/fula-contract-api.err

[Install]
WantedBy=multi-user.target
EOF

    echo "Enabling and starting the fula-contract-api service..."
    sudo systemctl daemon-reload
    sudo systemctl enable fula-contract-api.service
    sudo systemctl start fula-contract-api.service
}

# Function to check the service
check_service() {
    echo "Checking the fula-contract-api service status..."
    HTTP_RESPONSE=$(curl -o /dev/null -s -w "%{http_code}\n" -X POST http://127.0.0.1:4001/health)

    if [ "$HTTP_RESPONSE" -eq 200 ]; then
        echo "Service is running correctly. HTTP Status: $HTTP_RESPONSE"
    else
        echo "Error: Service might not be running correctly. HTTP Status: $HTTP_RESPONSE"
    fi
}

# Main function
main() {
    echo "User: $USER is setting up fula-contract-api with node: $NODE_SERVER_WS and Domain: $DOMAIN"

    install_packages
    install_rust
    clone_repository
    setup_env_file
    build_project
    configure_nginx_ssl
    setup_service
    check_service

    echo "Setup complete. Please review the logs and verify the service is running correctly."
}

main "$@"
