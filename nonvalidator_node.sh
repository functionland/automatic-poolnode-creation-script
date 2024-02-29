#!/bin/bash
//TODO: Also add setup for wss://node3 as it is not right now here
set -e

# Variables
EMAIL="hi@fx.land"  # <-- Modify this as needed
RPC_PORT="9944" # <-- This will be adjusted based on NODE_NO
PORT="30334" # <-- This will be adjusted based on NODE_NO
HTTP_PORT="4000" # <-- This will be adjusted based on NODE_NO

# Parameters
USER="ubuntu" # <-- set with --user or eliminate for ubuntu
NODE_NO="" # <-- set with --node or eliminate for 03
PASSWORD="" # <-- set with --password  or eliminate for a random password
NODE_DOMAIN="" # <-- set with --domain or eliminate
NODE_API_DOMAIN=""
BOOTSTRAP_NODE="" # <-- set with --bootnodes or eliminate
POOL_ID="" # <-- set with --pool or eliminate
RELEASE_FLAG="" # Set with --release for production build
ENVIRONMENT="debug"

# Function to show usage
usage() {
    echo "Usage: $0 --user=ubuntu --release --pool=1 --password=12345 --node=03 --domain=test.fx.land --bootnodes=/ip4/127.0.0.1/tcp/30334/p2p/12D3KooWBeXV65svCyknCvG1yLxXVFwRxzBLqvBJnUF6W84BLugv"
    exit 1
}

# Parse named parameters
while [ "$1" != "" ]; do
    case $1 in
        --password=*)
            PASSWORD="${1#*=}"
            ;;
        --node=*)
            NODE_NO="${1#*=}"
            ;;
        --pool=*)
            POOL_ID="${1#*=}"
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
        --release)
            RELEASE_FLAG="release"
            ENVIRONMENT="release"
            ;;
        *)
            echo "$1 i not supported"
            usage
            ;;
    esac
    shift
done

if [ -z "$NODE_DOMAIN" ]; then
    echo "missing domain parameter. Skipping the domain handling"
else
    NODE_API_DOMAIN="api.${NODE_DOMAIN}"
fi

if [ -z "$NODE_NO" ]; then
    echo "missing NODE_NO parameter. using 03 as default"
    NODE_NO="03"
fi

# Function to calculate the RPC port based on the validator number
calculate_rpc_port() {
    local base_port=9944
    # Convert NODE_NO to a decimal number to handle leading zeros
    local num
    num=$(printf "%d" "$NODE_NO")
    # Calculate the offset (subtract 1 so NODE_NO "01" corresponds to offset 0)
    local offset=$((num - 1))
    # Calculate and echo the RPC port
    local rpc_port=$((base_port + offset))
    echo $rpc_port
}
# Function to calculate the port based on the validator number
calculate_port() {
    local base_port=30334
    # Convert NODE_NO to a decimal number to handle leading zeros
    local num
    num=$(printf "%d" "$NODE_NO")
    # Calculate the offset (subtract 1 so NODE_NO "01" corresponds to offset 0)
    local offset=$((num - 1))
    # Calculate and echo the RPC port
    local port=$((base_port + offset))
    echo $port
}

# Function to calculate the port based on the validator number
calculate_http_port() {
    local base_port=4000
    # Convert NODE_NO to a decimal number to handle leading zeros
    local num
    num=$(printf "%d" "$NODE_NO")
    # Calculate the offset (subtract 1 so NODE_NO "01" corresponds to offset 0)
    local offset=$((num - 3))
    # Calculate and echo the RPC port
    local port=$((base_port + offset))
    echo $port
}

RPC_PORT=$(calculate_rpc_port)
PORT=$(calculate_port)
HTTP_PORT=$(calculate_http_port)
KEYS_INFO_PATH="/home/$USER/keys$NODE_NO.info"
BASE_DIR="/home/$USER/.sugarfunge-node"
SECRET_DIR="$BASE_DIR/passwords$NODE_NO"
DATA_DIR="/uniondrive/data$NODE_NO"
KEYS_DIR="$BASE_DIR/keys/node$NODE_NO"
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

    echo "Secret Phrase: $SECRET_PHRASE"
    echo "Secret Seed: $SECRET_SEED"
    echo "Public Key (SS58): $PUBLIC_KEY_SS58"

    # Save the extracted values to respective files for later use
    echo -n "${SECRET_PHRASE##*( )}" | sed 's/ *$//' > "$SECRET_DIR/secret_phrase.txt"
    echo -n "${SECRET_SEED##*( )}" | sed 's/ *$//' > "$SECRET_DIR/secret_seed.txt"
    echo -n "${PUBLIC_KEY_SS58##*( )}" | sed 's/ *$//' > "$SECRET_DIR/account.txt"
    echo -n "${PASSWORD##*( )}" | sed 's/ *$//' > "$SECRET_DIR/password.txt"
}

# Function to insert keys into the node (Aura and Grandpa accounts)
insert_keys() {
    echo "insert_keys"
    # Clear the keys directory
    sudo rm -rf "$KEYS_DIR"
    suri=$(tr -d '\r\n' < "${SECRET_DIR}/secret_phrase.txt")
    password=$(tr -d '\r\n' < "${SECRET_DIR}/password.txt")


    # Insert the keys
    /home/$USER/sugarfunge-node/target/$ENVIRONMENT/sugarfunge-node key insert --base-path="$DATA_DIR" --keystore-path="$KEYS_DIR" --chain "/home/$USER/sugarfunge-node/customSpecRaw.json" --scheme Sr25519 --suri "$suri" --password "$password" --key-type aura
    /home/$USER/sugarfunge-node/target/$ENVIRONMENT/sugarfunge-node key insert --base-path="$DATA_DIR" --keystore-path="$KEYS_DIR" --chain "/home/$USER/sugarfunge-node/customSpecRaw.json" --scheme Ed25519 --suri "$suri" --password "$password" --key-type gran
}

# Function to setup and start node service
setup_node_service() {
    node_service_file_path="/etc/systemd/system/sugarfunge-node$NODE_NO.service"
    echo "Setting up node service at $node_service_file_path"

    local USER_NODE
    USER_NODE=$USER
    NODE_KEY=$(cat "$SECRET_DIR/node_key.txt")
    BOOTNODES_PARAM=""
    if [ -n "$BOOTSTRAP_NODE" ]; then
        BOOTNODES_PARAM="--bootnodes $BOOTSTRAP_NODE"
    fi

    if [ -z "$RELEASE_FLAG" ]; then
        # Debug mode service configuration
        EXEC_START="/home/$USER/sugarfunge-node/target/debug/sugarfunge-node --chain /home/$USER/sugarfunge-node/customSpecRaw.json --enable-offchain-indexing true --base-path=$DATA_DIR --keystore-path=$KEYS_DIR --port=$PORT --rpc-port $RPC_PORT --rpc-cors=all --rpc-methods=Unsafe --rpc-external --name Node$NODE_NO --node-key=$NODE_KEY --pruning archive --password-filename=\"/password.txt\" $BOOTNODES_PARAM"
        USER_NODE=$USER
        ENVIRONMENT="RUST_LOG=debug,proof_engine=debug,fula-pallet=debug"
    else
        # Release mode service configuration
        EXEC_START="/usr/bin/docker run -u root --rm --name MyNode$NODE_NO --network host -v $SECRET_DIR/password.txt:/password.txt -v $KEYS_DIR:/keys -v $DATA_DIR:/data functionland/sugarfunge-node:amd64-latest --chain /customSpecRaw.json --enable-offchain-indexing true --base-path=/data --keystore-path=/keys --port=$PORT --rpc-port $RPC_PORT --rpc-cors=all --rpc-methods=Unsafe --rpc-external --name Node$NODE_NO --password-filename=\"/password.txt\" --node-key=$NODE_KEY --pruning archive $BOOTNODES_PARAM"
        USER_NODE="root"
        ENVIRONMENT=""
    fi

    sudo bash -c "cat > '$node_service_file_path'" << EOF
[Unit]
Description=Sugarfunge Node
After=network.target

[Service]
Type=simple
User=$USER_NODE
Environment=$ENVIRONMENT
ExecStart=$EXEC_START
Restart=always
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4
StandardOutput=file:"$LOG_DIR/Node$NODE_NO.log"
StandardError=file:"$LOG_DIR/Node$NODE_NO.err"

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable sugarfunge-node$NODE_NO.service
    sudo systemctl start sugarfunge-node$NODE_NO.service
    echo "Node service has been set up and started."
}

# Function to set up and start API service
setup_api_service() {
    api_service_file_path="/etc/systemd/system/sugarfunge-api$NODE_NO.service"
    echo "Setting up API service at $api_service_file_path"
    local USER_API
    USER_API=$USER
    sudo cp /home/$USER/sugarfunge-api/.env.example /home/$USER/sugarfunge-api/.env
    if [ -z "$RELEASE_FLAG" ]; then
        # Debug mode service configuration
        EXEC_START="/home/$USER/sugarfunge-api/target/debug/sugarfunge-api --db-uri=/data --node-server ws://127.0.0.1:$RPC_PORT"
        USER_API=$USER
        ENVIRONMENT="RUST_LOG=debug,proof_engine=debug,fula-pallet=debug \
,FULA_SUGARFUNGE_API_HOST=http://127.0.0.1:$HTTP_PORT \
,FULA_CONTRACT_API_HOST=https://contract-api.functionyard.fula.network \
,LABOR_TOKEN_CLASS_ID=100 \
,LABOR_TOKEN_ASSET_ID=100 \
,CHALLENGE_TOKEN_CLASS_ID=110 \
,CHALLENGE_TOKEN_ASSET_ID=100 \
,LABOR_TOKEN_VALUE=1 \
,CHALLENGE_TOKEN_VALUE=1 \
,CLAIMED_TOKEN_CLASS_ID=120 \
,CLAIMED_TOKEN_ASSET_ID=100"
    else
        # Release mode service configuration
        EXEC_START="/usr/bin/docker run -u root --rm --name NodeAPI$NODE_NO --network host \
-e FULA_SUGARFUNGE_API_HOST=http://127.0.0.1:$HTTP_PORT \
-e FULA_CONTRACT_API_HOST=https://contract-api.functionyard.fula.network \
-e LABOR_TOKEN_CLASS_ID=100 \
-e LABOR_TOKEN_ASSET_ID=100 \
-e CHALLENGE_TOKEN_CLASS_ID=110 \
-e CHALLENGE_TOKEN_ASSET_ID=100 \
-e LABOR_TOKEN_VALUE=1 \
-e CHALLENGE_TOKEN_VALUE=1 \
-e CLAIMED_TOKEN_CLASS_ID=120 \
-e CLAIMED_TOKEN_ASSET_ID=100 \
-v /home/$USER/sugarfunge-api/.env:/.env \
-v $DATA_DIR:/data \
functionland/sugarfunge-api:amd64-latest --db-uri=/data --node-server ws://127.0.0.1:$RPC_PORT"
        USER_API="root"
        ENVIRONMENT=""
    fi

    sudo bash -c "cat > '$api_service_file_path'" << EOF
[Unit]
Description=Sugarfunge API$NODE_NO
After=sugarfunge-node$NODE_NO.service
Requires=sugarfunge-node$NODE_NO.service

[Service]
Type=simple
User=$USER_API
Environment=$ENVIRONMENT
ExecStart=$EXEC_START
Restart=always
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4
StandardOutput=file:"$LOG_DIR/NodeAPI$NODE_NO.log"
StandardError=file:"$LOG_DIR/NodeAPI$NODE_NO.err"

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable sugarfunge-api$NODE_NO.service
    sudo systemctl start sugarfunge-api$NODE_NO.service
    echo "API service has been set up and started."
}

# Function to install required packages
install_packages() {
    sudo apt-get update -qq
    sudo apt-get install -y docker.io nginx software-properties-common certbot python3-certbot-nginx
    sudo apt-get install -y wget git curl build-essential jq pkg-config libssl-dev protobuf-compiler llvm libclang-dev clang plocate cmake
    sudo apt-get install -y g++ libx11-dev libasound2-dev libudev-dev libxkbcommon-x11-0
    sudo systemctl start docker
    sudo systemctl enable docker
}


# Function to pull the required Docker image and verify
pull_docker_image_node() {
    echo "Pulling the required Docker image node..."
    sudo docker pull functionland/sugarfunge-node:amd64-latest

    # Check if the image was pulled successfully
    if sudo docker images | grep -q 'functionland/sugarfunge-node'; then
        echo "Docker image node pulled successfully."
    else
        echo "Error: Docker image node pull failed."
        exit 1
    fi
}

# Function to pull the required Docker image and verify
pull_docker_image_api() {
    echo "Pulling the required Docker image api..."
    sudo docker pull functionland/sugarfunge-api:amd64-latest

    # Check if the image was pulled successfully
    if sudo docker images | grep -q 'functionland/sugarfunge-api'; then
        echo "Docker image api pulled successfully."
    else
        echo "Error: Docker image api pull failed."
        exit 1
    fi
}

# Function to configure NGINX for HTTP
configure_nginx() {
    echo "Configuring NGINX for HTTP..."
    NGINX_CONF="/etc/nginx/sites-available/default"

    # Create a backup of the original default config
    sudo cp $NGINX_CONF $NGINX_CONF.bak

    # Check if the domain is already in the NGINX configuration
    if ! grep -q "$NODE_API_DOMAIN" "$NGINX_CONF"; then
        echo "Adding new server configuration to NGINX..."

        # Define the new server block configuration
        NEW_SERVER_BLOCK=$(cat <<EOF

server {
    listen 80;
    server_name $NODE_API_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$HTTP_PORT;
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

        # Append the new server block to the NGINX configuration
        echo "$NEW_SERVER_BLOCK" | sudo tee -a "$NGINX_CONF"

        # Test and reload NGINX
        sudo nginx -t && sudo systemctl reload nginx
        echo "New server configuration added and NGINX reloaded."
    else
        echo "The server name $NODE_API_DOMAIN already exists in the NGINX configuration."
    fi
}

# Function to obtain SSL certificates from Let's Encrypt
obtain_ssl_certificates() {
    echo "Obtaining SSL certificates from Let's Encrypt for $NODE_API_DOMAIN..."

    # Obtain the certificate (this also modifies the Nginx config for you)
    sudo certbot --nginx -m "$EMAIL" --agree-tos --no-eff-email -d "$NODE_API_DOMAIN" --redirect --keep-until-expiring --non-interactive
}

# Function to configure NGINX for WSS
configure_nginx_wss() {
    echo "Configuring NGINX for WSS..."
    NGINX_CONF="/etc/nginx/sites-available/default"

    # Create a backup of the original default config
    sudo cp $NGINX_CONF $NGINX_CONF.bak

    # Check if the domain is already in the NGINX configuration
    if ! grep -q "$NODE_DOMAIN" "$NGINX_CONF"; then
        echo "Adding new server configuration to NGINX..."

        # Define the new server block configuration
        NEW_SERVER_BLOCK=$(cat <<EOF

server {
    listen 80;
    server_name $NODE_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$RPC_PORT;
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

        # Append the new server block to the NGINX configuration
        echo "$NEW_SERVER_BLOCK" | sudo tee -a "$NGINX_CONF"

        # Test and reload NGINX
        sudo nginx -t && sudo systemctl reload nginx
        echo "New server configuration added and NGINX reloaded."
    else
        echo "The server name $NODE_DOMAIN already exists in the NGINX configuration."
    fi
}

# Function to obtain SSL certificates from Let's Encrypt
obtain_ssl_certificates_wss() {
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
    sudo crontab -l | sudo tee mycron > /dev/null 

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

# Function to install Go 1.21 from source
install_go() {
	echo "Installing go"
    # Check if Go is already installed
    if ! command -v go &> /dev/null && [ ! -d "/usr/local/go" ]; then
        echo "Go is not installed. Installing Go..."

        # Download the pre-compiled binary of Go 1.21
        sudo wget https://golang.org/dl/go1.21.0.linux-amd64.tar.gz
        sudo tar -xvf go1.21.0.linux-amd64.tar.gz
        sudo mv go /usr/local

        ### Set environment variables so the system knows where to find Go
        # echo "export GOROOT=/usr/local/go" | sudo tee /etc/profile.d/goenv.sh
        # echo "export PATH=\$PATH:\$GOROOT/bin" | sudo tee -a /etc/profile.d/goenv.sh
		
		# source /etc/profile.d/goenv.sh
		
		# sudo ln -s /usr/local/go/bin/go /usr/local/bin/go
		echo "export GOROOT=/usr/local/go" >> ~/.profile
		echo "export PATH=\$PATH:\$GOROOT/bin" >> ~/.profile
		source ~/.profile
    else
        echo "Go is already installed. Skipping installation."
    fi
}

# Function to clone and build repositories
clone_and_build_node() {
	echo "Installing sugarfunge-node"
    if [ ! -d "/home/${USER}/sugarfunge-node" ] || [ -z "$(ls -A /home/${USER}/sugarfunge-node)" ]; then
        sudo git clone https://github.com/functionland/sugarfunge-node.git /home/${USER}/sugarfunge-node
    fi
    sudo chown -R ubuntu:ubuntu /home/${USER}/sugarfunge-node
    sudo chmod -R 777 /home/${USER}/sugarfunge-node
    cd /home/${USER}/sugarfunge-node
    if [ -n "$RELEASE_FLAG" ]; then
        cargo build --release
    else
        cargo build
    fi
    cd ..
}

# Function to clone and build repositories
clone_and_build_fula() {
	echo "Installing go-fula"
    if [ ! -d "/home/${USER}/go-fula" ] || [ -z "$(ls -A /home/${USER}/go-fula)" ]; then
        sudo git clone https://github.com/functionland/go-fula.git /home/${USER}/go-fula
    fi
    sudo chown -R ubuntu:ubuntu /home/${USER}/go-fula
    sudo chmod -R 777 /home/${USER}/go-fula
    cd /home/${USER}/go-fula
    go build -o go-fula ./cmd/blox
    cd ..
}

# Function to clone and build repositories
clone_and_build_proof_engine() {
	echo "Installing proof engine"
    if [ ! -d "/home/${USER}/proof-engine" ] || [ -z "$(ls -A /home/${USER}/proof-engine)" ]; then
        sudo git clone https://github.com/functionland/proof-engine.git /home/${USER}/proof-engine
    fi
    sudo chown -R ubuntu:ubuntu /home/${USER}/proof-engine
    sudo chmod -R 777 /home/${USER}/proof-engine
    cd /home/${USER}/proof-engine
    if [ -n "$RELEASE_FLAG" ]; then
        cargo build --release --features headless
    else
        cargo build --features headless
    fi
    cd ..
}

# Function to clone and build repositories
clone_and_build_api() {
	echo "Installing sugarfunge-api"
    if [ ! -d "/home/${USER}/sugarfunge-api" ] || [ -z "$(ls -A /home/${USER}/sugarfunge-api)" ]; then
        git clone https://github.com/functionland/sugarfunge-api.git /home/${USER}/sugarfunge-api
    fi
    sudo chown -R ubuntu:ubuntu /home/${USER}/sugarfunge-api
    sudo chmod -R 777 /home/${USER}/sugarfunge-api
    cd /home/${USER}/sugarfunge-api
    if [ -n "$RELEASE_FLAG" ]; then
        cargo build --release
    else
        cargo build
    fi
    cd ..
}

generate_node_key() {
    config_path="/home/$USER/.fula/config.yaml"
    echo "Checking identity in $config_path..."
	sudo chmod +r "$config_path"

    # Check if the identity field exists and has a value
    identity=$(python3 -c "import yaml; print(yaml.safe_load(open('$config_path'))['identity'])")
    
    if [ -z "$identity" ]; then
        echo "Error: 'identity' field is missing or empty in $config_path."
        exit 1
    else
        echo "'identity' field is present in $config_path: $identity"
        new_key=$(/home/$USER/go-fula/go-fula --config "$config_path" --generateNodeKey | grep -E '^[a-f0-9]{64}$')
        
        # Check if the node_key file exists and has different content
        if [ ! -f "$SECRET_DIR/node_key.txt" ] || [ "$new_key" != "$(cat $SECRET_DIR/node_key.txt)" ]; then
            echo -n "$new_key" > "$SECRET_DIR/node_key.txt"
            echo "Node key saved to $SECRET_DIR/node_key.txt"
        else
            echo "Node key file already exists and is up to date."
        fi
		
		# Generate the peer ID from the node key
        generated_peer_id=$(/home/$USER/sugarfunge-node/target/$ENVIRONMENT/sugarfunge-node key inspect-node-key --file "$SECRET_DIR/node_key.txt")
        
        # Read the stored peer ID from the file
        stored_peer_id=$(cat "$SECRET_DIR/node_peerid.txt")

        # Compare the generated peer ID with the stored peer ID
        if [ "$generated_peer_id" != "$stored_peer_id" ]; then
            echo "Error: The generated peer ID does not match the stored peer ID."
            echo "Generated peer ID: $generated_peer_id"
            echo "Stored peer ID: $stored_peer_id"
            exit 1
        else
            echo "The generated peer ID matches the stored peer ID: $generated_peer_id"
        fi
    fi
}

# Function to set up and start go-fula service
setup_gofula_service() {
    gofula_service_file_path="/etc/systemd/system/go-fula.service"
    echo "Setting up go-fula service at $gofula_service_file_path"

    # Check if the file exists and then remove it
    if [ -f "$gofula_service_file_path" ]; then
        sudo systemctl stop go-fula.service
        sudo systemctl disable go-fula.service
        sudo rm "$gofula_service_file_path"
        sudo systemctl daemon-reload
        echo "Removed $gofula_service_file_path."
    else
        echo "$gofula_service_file_path does not exist."
    fi

    # Initialize go-fula and extract the blox peer ID
    init_output=$(/home/$USER/go-fula/go-fula --config /home/$USER/.fula/config.yaml --initOnly)
    blox_peer_id=$(echo "$init_output" | awk '/blox peer ID:/ {print $NF}')
    # Check if blox_peer_id is empty and exit with an error if it is
    if [ -z "$blox_peer_id" ]; then
        echo "Error: Failed to extract blox peer ID. Exiting."
        exit 1
    fi

    echo "Extracted blox peer ID: $blox_peer_id"

    # Save the blox peer ID to the file
	mkdir -p "$SECRET_DIR"
    echo -n "$blox_peer_id" > "$SECRET_DIR/node_peerid.txt"
    echo "Blox peer ID saved to $SECRET_DIR/node_peerid.txt"

    # Create the service file using the provided path
    sudo bash -c "cat > '$gofula_service_file_path'" << EOF
[Unit]
Description=Go Fula Service
After=network.target

[Service]
Type=simple
Environment=HOME=/home/$USER
ExecStart=/home/$USER/go-fula/go-fula --config /home/$USER/.fula/config.yaml
Restart=always
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable the service
    sudo systemctl daemon-reload
    sudo systemctl enable go-fula.service
    sudo systemctl start go-fula.service
    echo "Go-fula service has been set up and started."
}

# Function to setup the Fula config file
setup_fula_config() {
    echo "Setting up Fula config..."
    config_path="/home/$USER/.fula/config.yaml"

    # Check if the Fula config file already exists
    mkdir -p /home/$USER/.fula/blox/store

    # Since we are initOnly and creating hte config before this step to create identity, we need to read the identity and ipniIdentity before replacing them
    EXISTING_IPNI_PUBLISHER_IDENTITY=$(grep 'ipniPublisherIdentity:' "$config_path" | awk '{print $2}')
    EXISTING_IDENTITY=$(grep 'identity:' "$config_path" | awk '{print $2}')

    # Create the config file if it doesn't exist
    cat > "$config_path" << EOF
storeDir: /home/$USER/.fula/blox/store
poolName: "$POOL_ID"
logLevel: info
listenAddrs:
    - /ip4/0.0.0.0/tcp/40001
    - /ip4/0.0.0.0/udp/40001/quic
    - /ip4/0.0.0.0/udp/40001/quic-v1
    - /ip4/0.0.0.0/udp/40001/quic-v1/webtransport
authorizer: 12D3KooWRTzN7HfmjoUBHokyRZuKdyohVVSGqKBMF24ZC3tGK78Q
authorizedPeers:
    - 12D3KooWRTzN7HfmjoUBHokyRZuKdyohVVSGqKBMF24ZC3tGK78Q
staticRelays:
    - /dns/relay.dev.fx.land/tcp/4001/p2p/12D3KooWDRrBaAfPwsGJivBoUw5fE7ZpDiyfUjqgiURq2DEcL835
    - /dns/alpha-relay.dev.fx.land/tcp/4001/p2p/12D3KooWFLhr8j6LTF7QV1oGCn3DVNTs1eMz2u4KCDX6Hw3BFyag
    - /dns/bravo-relay.dev.fx.land/tcp/4001/p2p/12D3KooWA2JrcPi2Z6i2U8H3PLQhLYacx6Uj9MgexEsMsyX6Fno7
    - /dns/charlie-relay.dev.fx.land/tcp/4001/p2p/12D3KooWKaK6xRJwjhq6u6yy4Mw2YizyVnKxptoT9yXMn3twgYns
    - /dns/delta-relay.dev.fx.land/tcp/4001/p2p/12D3KooWDtA7kecHAGEB8XYEKHBUTt8GsRfMen1yMs7V85vrpMzC
    - /dns/echo-relay.dev.fx.land/tcp/4001/p2p/12D3KooWQBigsW1tvGmZQet8t5MLMaQnDJKXAP2JNh7d1shk2fb2
forceReachabilityPrivate: true
allowTransientConnection: true
disableResourceManger: true
maxCIDPushRate: 100
ipniPublishDisabled: true
ipniPublishInterval: 10s
IpniPublishDirectAnnounce:
    - https://cid.contact/ingest/announce
EOF

    # Conditionally append identity and ipniPublisherIdentity if they exist
    if [ -n "$EXISTING_IDENTITY" ]; then
        echo "identity: $EXISTING_IDENTITY" >> "$config_path"
    fi

    if [ -n "$EXISTING_IPNI_PUBLISHER_IDENTITY" ]; then
        echo "ipniPublisherIdentity: $EXISTING_IPNI_PUBLISHER_IDENTITY" >> "$config_path"
    fi
    echo "Fula config file created at $config_path."
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
    declare -a services=("go-fula" "sugarfunge-node$NODE_NO.service"  "sugarfunge-api$NODE_NO.service")

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
        sleep 5
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

    echo "User: $USER is setting up None-Validator No: $NODE_NO on RPC PORT:$RPC_PORT with password:$PASSWORD"

    # Install required packages
    echo "Installing required packages"
    install_packages

    # Pull the required Docker image and verify
    echo "Pulling required docker image for node"
    pull_docker_image_node

    echo "Pulling required docker image for api"
    pull_docker_image_api

    # Set LIBCLANG_PATH for the user
    echo "Setting required env paths"
    set_libclang_path

    # Install Rust and Cargo
    echo "Installing rust"
    install_rust

    # Install Go
    echo "Installing go"
    install_go

    # Clone and build the necessary repositories
    echo "Cloning and building node"
    clone_and_build_node

    echo "Cloning and building node"
    clone_and_build_api

    # Clone and build the necessary repositories
    echo "Cloning and building fula"
    clone_and_build_fula

    echo "Cloning and building proof-engine"
    clone_and_build_proof_engine

    # Create fula config
    setup_fula_config

    # Setup and start go-fula service
    setup_gofula_service

    # Read the keys from the file
    echo "Reading secret keys from the file"
    read_keys_from_file

    # Create node peerID and key that matches between fula and node
    generate_node_key

    # Insert keys into the node
    echo "Inserting keys into node"
    insert_keys

    # Setup and start node service
    echo "Setting up node service"
    setup_node_service

    # Check if NODE_DOMAIN is not empty
    local NODE_ADDRESS
    if [ "$NODE_DOMAIN" != "" ]; then
        # Configure NGINX for HTTP
        echo "Configuring http"
        configure_nginx

        # Obtain SSL certificates from Let's Encrypt
        echo "Obtaining SSL certificate http"
        obtain_ssl_certificates

        # Configure NGINX for WSS
        echo "Configuring wss"
        configure_nginx_wss

        # Obtain SSL certificates from Let's Encrypt
        echo "Obtaining SSL certificate wss"
        obtain_ssl_certificates_wss


        # Configure automatic SSL certificate renewal
        echo "Configuring cronjob for auto SSL renewal"
        configure_auto_ssl_renewal
        NODE_ADDRESS="/dns4/node.functionyard.fula.network/tcp/$PORT/p2p/$PEER_ID"
    else
        echo "NODE_DOMAIN is not set. Skipping SSL and NGINX configuration."
        NODE_ADDRESS="/ip4/127.0.0.1/tcp/$PORT/p2p/$PEER_ID"
    fi
    sleep 10

    echo "Setting up node api service"
    setup_api_service

    # Check the status of the services
    sleep 10
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
