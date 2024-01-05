#!/bin/bash

set -e

# Variables
USER="ubuntu"
PASSWORD_FILE="/home/$USER/password.txt"
SECRET_DIR="/home/$USER/.secrets"
DATA_DIR="/home/$USER/data"
LOG_DIR="/var/log"

# Function to generate a random 25-character password
generate_password() {
	echo "generating password"
    sudo mkdir -p $(dirname "$PASSWORD_FILE")
    sudo cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 25 > "$PASSWORD_FILE"
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
	echo "Installing sugarfunge-api"
    if [ ! -d "sugarfunge-api" ] || [ -z "$(ls -A sugarfunge-api)" ]; then
        git clone https://github.com/functionland/sugarfunge-api.git
    fi
    cd sugarfunge-api
    cargo build --release
    cd ..
	
	echo "Installing sugarfunge-node"
    if [ ! -d "sugarfunge-node" ] || [ -z "$(ls -A sugarfunge-node)" ]; then
        git clone https://github.com/functionland/sugarfunge-node.git
    fi
    cd sugarfunge-node
    cargo build --release
    cd ..

	echo "Installing go-fula"
    if [ ! -d "go-fula" ] || [ -z "$(ls -A go-fula)" ]; then
        git clone https://github.com/functionland/go-fula.git
    fi
    cd go-fula
    go build -o go-fula ./cmd/blox
    cd ..
}


# Function to set up and extract keys
setup_and_extract_keys() {
	echo "setup_and_extract_keys"
    mkdir -p "$SECRET_DIR"
    if [ ! -f "$SECRET_DIR/secret_phrase.txt" ] || [ ! -f "$SECRET_DIR/secret_seed.txt" ]; then
        output=$(./sugarfunge-node/target/release/sugarfunge-node key generate --scheme Sr25519 --password-filename="$PASSWORD_FILE" 2>&1)
        echo "$output"
        secret_phrase=$(echo "$output" | grep "Secret phrase:" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        echo "$secret_phrase" > "$SECRET_DIR/secret_phrase.txt"

        secret_seed=$(echo "$output" | grep "Secret seed:" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        echo "$secret_seed" > "$SECRET_DIR/secret_seed.txt"

        account=$(echo "$output" | grep "SS58 Address:" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        echo "$account" > "$SECRET_DIR/account.txt"
    fi
    if [ ! -f "$SECRET_DIR/node_key.txt" ]; then
        output=$(./sugarfunge-node/target/release/sugarfunge-node key generate-node-key 2>&1)
        echo "$output"
        node_key=$(echo "$output" | tr ' ' '\n' | tail -n 1)
        echo "$node_key" > "$SECRET_DIR/node_key.txt"

        node_peerid=$(echo "$output" | head -n 1)
        echo "$node_peerid" > "$SECRET_DIR/node_peerid.txt"
    fi
}

# Function to insert keys into the node
insert_keys() {
	echo "insert_keys"
    secret_phrase=$(cat "$SECRET_DIR/secret_phrase.txt")
    ./sugarfunge-node/target/release/sugarfunge-node key insert --base-path="$DATA_DIR" --chain $HOME/sugarfunge-node/customSpecRaw.json --scheme Sr25519 --suri "$secret_phrase" --password-filename "$PASSWORD_FILE" --key-type aura
    ./sugarfunge-node/target/release/sugarfunge-node key insert --base-path="$DATA_DIR" --chain $HOME/sugarfunge-node/customSpecRaw.json --scheme Ed25519 --suri "$secret_phrase" --password-filename "$PASSWORD_FILE" --key-type gran
}

# Function to set up and start node service
setup_node_service() {
	echo "setup_node_service"
    sudo bash -c 'cat > /etc/systemd/system/sugarfunge-node.service' << EOF
[Unit]
Description=Sugarfunge Node
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=$HOME/sugarfunge-node/target/release/sugarfunge-node \
    --chain $HOME/sugarfunge-node/customSpecRaw.json \
    --enable-offchain-indexing true \
    --base-path="$DATA_DIR" \
    --keystore-path="$SECRET_DIR" \
    --port 30334 \
    --rpc-port 9944 \
    --rpc-cors=all \
    --rpc-methods=Unsafe \
    --rpc-external \
    --validator \
    --name MyNode \
    --password-filename="$PASSWORD_FILE" \
    --node-key=$(cat "$SECRET_DIR/node_key.txt")
Restart=always
StandardOutput=file:"$LOG_DIR/MyNode.log"
StandardError=file:"$LOG_DIR/MyNode.err"

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable sugarfunge-node.service
    sudo systemctl start sugarfunge-node.service
}


# Function to set up and start API service
setup_api_service() {
	echo "setup_api_service"
    sudo bash -c 'cat > /etc/systemd/system/sugarfunge-api.service' << EOF
[Unit]
Description=Sugarfunge API
After=sugarfunge-node.service
Requires=sugarfunge-node.service

[Service]
Type=simple
User=$USER
ExecStart=$HOME/sugarfunge-api/target/release/sugarfunge-api \
    --db-uri="$DATA_DIR" \
    --node-server ws://127.0.0.1:9946
Environment=FULA_SUGARFUNGE_API_HOST=http://127.0.0.1:4000 \
            FULA_CONTRACT_API_HOST=https://contract-api.functionyard.fula.network \
            LABOR_TOKEN_CLASS_ID=100 \
            LABOR_TOKEN_ASSET_ID=100 \
            CHALLENGE_TOKEN_CLASS_ID=110 \
            CHALLENGE_TOKEN_ASSET_ID=100 \
            LABOR_TOKEN_VALUE=1 \
            CHALLENGE_TOKEN_VALUE=1 \
            CLAIMED_TOKEN_CLASS_ID=120 \
            CLAIMED_TOKEN_ASSET_ID=100
Restart=always
StandardOutput=file:"$LOG_DIR/MyNodeAPI.log"
StandardError=file:"$LOG_DIR/MyNodeAPI.err"

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable sugarfunge-api.service
    sudo systemctl start sugarfunge-api.service
}


# Function to set up and start go-fula service
setup_gofula_service() {
	echo "setup_gofula_service"
    sudo bash -c 'cat > /etc/systemd/system/go-fula.service' << EOF
[Unit]
Description=Go Fula Service
After=network.target

[Service]
Type=simple
ExecStart=/home/$USER/go-fula/go-fula
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable go-fula.service
    sudo systemctl start go-fula.service
}

# Function to fund an account
fund_account() {
	echo "fund_account"
    secret_seed=$(cat "$SECRET_DIR/secret_seed.txt")
    account=$(cat "$SECRET_DIR/account.txt")
    curl -X POST https://api.node3.functionyard.fula.network/account/fund \
    -H "Content-Type: application/json" \
    -d "{\"seed\": \"$secret_seed\", \"amount\": 1000000000000000000, \"to\": \"$account\"}"
}

# Function to create a pool
create_pool() {
	echo "create_pool"
    seed=$(cat "$SECRET_DIR/secret_seed.txt")
    node_peerid=$(cat "$SECRET_DIR/node_peerid.txt")
    pool_name=$1
    region=$2

    response=$(curl -X POST https://api.node3.functionyard.fula.network/fula/pool/create \
    -H "Content-Type: application/json" \
    -d "{\"seed\": \"$seed\", \"pool_name\": \"$pool_name\", \"peer_id\": \"$node_peerid\", \"region\": \"$region\"}")

    pool_id=$(echo $response | jq '.pool_id')
    echo "Pool ID: $pool_id"

    # Update the Fula config file with the pool ID
    setup_fula_config "$pool_id"
}

# Function to setup the Fula config file
setup_fula_config() {
	echo "setup_fula_config"
    pool_id="$1"
    mkdir -p /home/$USER/.fula/blox/store
    cat > /home/$USER/.fula/config.yaml << EOF
identity: 
storeDir: /home/$USER/.fula/blox/store
poolName: "$pool_id"
logLevel: info
listenAddrs:
    - /ip4/0.0.0.0/tcp/40001
    - /ip4/0.0.0.0/udp/40001/quic
    - /ip4/0.0.0.0/udp/40001/quic-v1
    - /ip4/0.0.0.0/udp/40001/quic-v1/webtransport
authorizer: 12D3KooWMMt4C3FKui14ai4r1VWwznRw6DoP5DcgTfzx2D5VZoWx
authorizedPeers:
    - 12D3KooWMMt4C3FKui14ai4r1VWwznRw6DoP5DcgTfzx2D5VZoWx
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
ipniPublisherIdentity: 
EOF
}

cleanup() {
    echo "Cleaning up..."

    # Remove Go tarball
    if [ -f "go1.21.0.linux-amd64.tar.gz" ]; then
        echo "Removing Go tarball..."
        sudo rm go1.21.0.linux-amd64.tar.gz
    fi

    # Add other cleanup tasks here
}

# Main script execution
main() {
	# Set DEBIAN_FRONTEND to noninteractive to avoid interactive prompts
    export DEBIAN_FRONTEND=noninteractive
	
    # Check if a region is provided
    if [ $# -lt 1 ]; then
        echo "Please provide a region as an argument."
        exit 1
    fi

    region=$1
    pool_name="${region// /}"

    # Update and install dependencies
    sudo apt update
    sudo apt install -y wget git curl build-essential jq pkg-config libssl-dev protobuf-compiler llvm libclang-dev clang plocate cmake 

	# Set LIBCLANG_PATH for the user
    # echo "export LIBCLANG_PATH=/usr/lib/llvm-14/lib/" | sudo tee /etc/profile.d/libclang.sh
	echo "export LIBCLANG_PATH=/usr/lib/llvm-14/lib/" >> ~/.profile
	source ~/.profile

    # Install Go 1.21 from source
    install_go

    # Install Rust and Cargo
    install_rust

    # Clone and build the necessary repositories
    clone_and_build

    # Generate a strong password and save it
    generate_password

    # Setup and extract keys
    setup_and_extract_keys

    # Insert keys into the node
    insert_keys

    # Setup and start node service
    setup_node_service

    # Setup and start API service
    setup_api_service

    # Setup and start go-fula service
    setup_gofula_service

    # Fund an account
    fund_account

    # Create a pool
    create_pool "$pool_name" "$region"
	
	cleanup

    echo "Setup complete. Please review the logs and verify the services are running correctly."
}

# Run the main function with the provided region
main "$@"
