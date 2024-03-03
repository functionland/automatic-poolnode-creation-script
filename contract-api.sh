#!/bin/bash

set -e

# Default Variables
NODE_SERVER_WS="" # Set with --node
RELEASE_FLAG="" # Set with --release for production build
DOMAIN="" # Set with --domain
VALIDATOR_SEED="" # Seed of main validator node, Set with --validator
API_URL="https://api.node3.functionyard.fula.network"
MINTER_ACCOUNT_SEED="" # Seed of an accountwith minter access to ocntract
USER="ubuntu"

# Function to show usage
usage() {
    echo "Usage: $0 --node=wss://example.com --release --domain=yourdomain.com --validator=0x2222 --minter=3b333 --api=http://127.0.0.1:4000 --user=ubuntu"
    exit 1
}

# Parse named parameters
while [ "$1" != "" ]; do
    case $1 in
        --node=*)
            NODE_SERVER_WS="${1#*=}"
            ;;
        --validator=*)
            VALIDATOR_SEED="${1#*=}"
            ;;
        --api=*)
            API_URL="${1#*=}"
            ;;
        --minter=*)
            MINTER_ACCOUNT_SEED="${1#*=}"
            ;;
        --release)
            RELEASE_FLAG="--release"
            ;;
        --user=*)
            USER="${1#*=}"
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

if [ -z "$VALIDATOR_SEED" ]; then
    echo "Error: validator seed is required."
    usage
fi

if [ -z "$MINTER_ACCOUNT_SEED" ]; then
    echo "Error: seed of minter is required."
    usage
fi

# Function to install necessary packages
install_packages() {
    echo "Installing necessary packages..."
    sudo apt-get update -qq
    sudo apt-get install -y git curl wget build-essential software-properties-common libssl-dev pkg-config
}

# Function to install Rust
install_rust() {
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "/home/${USER}/.cargo/env"
}

# Function to clone the fula-contract-api repository
clone_repository() {
    if [ ! -d "fula-contract-api" ] || [ -z "$(ls -A fula-contract-api)" ]; then
        echo "Cloning the fula-contract-api repository..."
        git clone https://github.com/functionland/fula-contract-api.git "/home/${USER}/fula-contract-api"
    fi
}

# Function to set up the .env file
setup_env_file() {
    echo "Setting up the .env file..."
    cp "/home/${USER}/fula-contract-api/.env.example" "/home/${USER}/fula-contract-api/.env"
}

# Function to build the project
build_project() {
    echo "Building the fula-contract-api project..."
    cd "/home/${USER}/fula-contract-api"
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
    sudo certbot --nginx -d $DOMAIN -m hi@fx.land --agree-tos -n --redirect
}

# Function to create and enable the service
setup_service() {
    BUILD_TYPE="debug"
    if [ "$RELEASE_FLAG" == "--release" ]; then
        BUILD_TYPE="release"
    fi

    sudo cp "/home/${USER}/fula-contract-api/.env.example" "/home/${USER}/fula-contract-api/.env"
    sed -i "s/^ACCOUNT_PRIVATE_KEY=\".*\"/ACCOUNT_PRIVATE_KEY=\"$MINTER_ACCOUNT_SEED\"/" "/home/${USER}/fula-contract-api/.env"

    SERVICE_FILE="/etc/systemd/system/fula-contract-api.service"
    echo "Creating the service file at $SERVICE_FILE..."

    sudo bash -c "cat > '$SERVICE_FILE'" << EOF
[Unit]
Description=Fula Contract API

# Load environment variables from the .env file
EnvironmentFile=/home/${USER}/fula-contract-api/.env

[Service]
TimeoutStartSec=0
Type=simple
User=root
EnvironmentFile=/home/${USER}/fula-contract-api/.env
ExecStart=/home/${USER}/fula-contract-api/target/$BUILD_TYPE/functionland-contract-api --node-server=$NODE_SERVER_WS --validator-seed $VALIDATOR_SEED --listen http://127.0.0.1:4001
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
    HTTP_RESPONSE=$(curl -o /dev/null -s -w "%{http_code}\n" -X POST http://127.0.0.1:4001/setup)

    if [ "$HTTP_RESPONSE" -eq 200 ]; then
        echo "Service is running correctly. HTTP Status: $HTTP_RESPONSE"
    else
        echo "Error: Service might not be running correctly. HTTP Status: $HTTP_RESPONSE"
    fi
}

createNeededAssetClasses() {
    echo "Creating asset classes $API_URL..."

    # Define the owner
    OWNER="5CcHZucP2u1FXQW9wuyC11vAVxB3c48pUhc5cc9b3oxbKPL2"

    # Create CLAIM_TOKEN_CLASS
    curl -X POST "$API_URL/asset/create_class" -H "Content-Type: application/json" -d '{
        "seed": "'$VALIDATOR_SEED'",
        "metadata": {
            "class_name": "CLAIM_TOKEN_CLASS"
        },
        "class_id": 120,
        "owner": "'$OWNER'"
    }'
    echo "Created CLAIM_TOKEN_CLASS"

    # Create CHALLENGE_TOKEN_CLASS
    curl -X POST "$API_URL/asset/create_class" -H "Content-Type: application/json" -d '{
        "seed": "'$VALIDATOR_SEED'",
        "metadata": {
            "class_name": "CHALLENGE_TOKEN_CLASS"
        },
        "class_id": 110,
        "owner": "'$OWNER'"
    }'
    echo "Created CHALLENGE_TOKEN_CLASS"

    # Create LABOR_TOKEN_CLASS
    curl -X POST "$API_URL/asset/create_class" -H "Content-Type: application/json" -d '{
        "seed": "'$VALIDATOR_SEED'",
        "metadata": {
            "class_name": "LABOR_TOKEN_CLASS"
        },
        "class_id": 100,
        "owner": "'$OWNER'"
    }'
    echo "Created LABOR_TOKEN_CLASS"

    # Create tokens for each class
    for class_id in 100 110 120; do
        # Define token name based on class_id
        token_name=""
        case $class_id in
            100) token_name="LABOR_TOKEN" ;;
            110) token_name="CHALLENGE_TOKEN" ;;
            120) token_name="CLAIM_TOKEN" ;;
        esac

        # Create token
        curl -X POST "$API_URL/asset/create" -H "Content-Type: application/json" -d '{
            "seed": "'$VALIDATOR_SEED'",
            "account": "'$OWNER'",
            "class_id": '$class_id',
            "asset_id": '$class_id',
            "metadata": {
                "token_name": "'$token_name'"
            }
        }'
        echo "Created $token_name token"
    done

    echo "Asset classes and tokens created."
}


# Main function
main() {
    echo "Setting up fula-contract-api with node: $NODE_SERVER_WS and Domain: $DOMAIN"

    install_packages
    install_rust
    clone_repository
    setup_env_file
    build_project
    configure_nginx_ssl
    setup_service
    createNeededAssetClasses
    check_service

    echo "Setup complete. Please review the logs and verify the service is running correctly."
}

main "$@"
