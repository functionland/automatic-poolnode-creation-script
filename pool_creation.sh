#!/bin/bash

set -e

# Variables
USER="ubuntu"
PASSWORD_FILE="/home/$USER/password.txt"
SECRET_DIR="/home/$USER/.secrets"
DATA_DIR="/home/$USER/data"
LOG_DIR="/var/log"

# Function to map AWS region to your custom region naming convention
get_region_name() {
    local aws_region=$1
    case $aws_region in
        us-east-1) echo "UsEastNVirginia" ;;
        us-east-2) echo "UsEastOhio" ;;
        us-west-1) echo "UsWestNCalifornia" ;;
        us-west-2) echo "UsWestOregon" ;;
        af-south-1) echo "AfricaCapeTown" ;;
        ap-east-1) echo "AsiaPacificHongKong" ;;
        ap-south-1) echo "AsiaPacificMumbai" ;;
        ap-northeast-3) echo "AsiaPacificOsaka" ;;
        ap-northeast-2) echo "AsiaPacificSeoul" ;;
        ap-southeast-1) echo "AsiaPacificSingapore" ;;
        ap-southeast-2) echo "AsiaPacificSydney" ;;
        ap-northeast-1) echo "AsiaPacificTokyo" ;;
        ca-central-1) echo "CanadaCentral" ;;
        eu-central-1) echo "EuropeFrankfurt" ;;
        eu-west-1) echo "EuropeIreland" ;;
        eu-west-2) echo "EuropeLondon" ;;
        eu-south-1) echo "EuropeMilan" ;;
        eu-west-3) echo "EuropeParis" ;;
        eu-north-1) echo "EuropeStockholm" ;;
        eu-central-2) echo "EuropeZurich" ;;
        eu-south-2) echo "EuropeSpain" ;;
        me-central-1) echo "MiddleEastUAE" ;;
        il-central-1) echo "IsraelTelAviv" ;;
        sa-east-1) echo "SouthAmericaSaoPaulo" ;;
        *) echo "" ;;
    esac
}

# Function to get the AWS Token
get_aws_token() {
    echo $(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
}

# Function to get the AWS Region
get_aws_region() {
    local token=$1
    echo $(curl -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/placement/region -s)
}

# Main function to find pool region on aws
find_pool_region_aws() {
    local token
    token=$(get_aws_token)
    if [ -n "$token" ]; then
        local aws_region
        aws_region=$(get_aws_region "$token")
        if [ -n "$aws_region" ]; then
            local pool_region
            pool_region=$(get_region_name "$aws_region")
            echo "$pool_region"
        else
            echo ""
        fi
    else
        echo ""
    fi
}

# Function to generate a random 25-character password
generate_password() {
    echo "Checking if a password needs to be generated..."
    if [ ! -f "$PASSWORD_FILE" ]; then
        echo "Password file does not exist. Generating password..."
        sudo mkdir -p $(dirname "$PASSWORD_FILE")
        sudo cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 25 > "$PASSWORD_FILE"
        echo "Password generated and saved to $PASSWORD_FILE"
    else
        echo "Password file already exists. No new password generated."
    fi
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
        output=$(/home/$USER/sugarfunge-node/target/release/sugarfunge-node key generate --scheme Sr25519 --password="$(cat "$PASSWORD_FILE")" 2>&1)
        echo "$output"
        secret_phrase=$(echo "$output" | grep "Secret phrase:" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        echo -n "$secret_phrase" > "$SECRET_DIR/secret_phrase.txt"

        secret_seed=$(echo "$output" | grep "Secret seed:" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        echo -n "$secret_seed" > "$SECRET_DIR/secret_seed.txt"

        account=$(echo "$output" | grep "SS58 Address:" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        echo -n "$account" > "$SECRET_DIR/account.txt"
    fi
}

# Function to insert keys into the node
insert_keys() {
	echo "insert_keys"
    secret_phrase=$(cat "$SECRET_DIR/secret_phrase.txt")
    /home/$USER/sugarfunge-node/target/release/sugarfunge-node key insert --base-path="$DATA_DIR" --chain $HOME/sugarfunge-node/customSpecRaw.json --scheme Sr25519 --suri "$secret_phrase" --password "$(cat "$PASSWORD_FILE")" --key-type aura
    /home/$USER/sugarfunge-node/target/release/sugarfunge-node key insert --base-path="$DATA_DIR" --chain $HOME/sugarfunge-node/customSpecRaw.json --scheme Ed25519 --suri "$secret_phrase" --password "$(cat "$PASSWORD_FILE")" --key-type gran
}

# Function to set up and start node service
setup_node_service() {
	node_service_file_path="/etc/systemd/system/sugarfunge-node.service"
	echo "setup_node_service at $node_service_file_path"
	# Check if the file exists and then remove it
	if [ -f "$node_service_file_path" ]; then
		sudo systemctl stop sugarfunge-node.service
		sudo systemctl disable sugarfunge-node.service
		sudo rm "$node_service_file_path"
		sudo systemctl daemon-reload
		echo "Removed $node_service_file_path."
	else
		echo "$node_service_file_path does not exist."
	fi
    sudo bash -c "cat > '$node_service_file_path'" << EOF
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
    --name MyNode \
    --password-filename="$PASSWORD_FILE" \
    --node-key=$(cat "$SECRET_DIR/node_key.txt") \
	--bootnodes /dns4/node.functionyard.fula.network/tcp/30334/p2p/12D3KooWBeXV65svCyknCvG1yLxXVFwRxzBLqvBJnUF6W84BLugv
Restart=always
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4
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
	api_service_file_path="/etc/systemd/system/sugarfunge-api.service"
	echo "setup_api_service at $api_service_file_path"
	# Check if the file exists and then remove it
	if [ -f "$api_service_file_path" ]; then
		sudo systemctl stop sugarfunge-api.service
		sudo systemctl disable sugarfunge-api.service
		sudo rm "$api_service_file_path"
		sudo systemctl daemon-reload
		echo "Removed $api_service_file_path."
	else
		echo "$api_service_file_path does not exist."
	fi
    sudo bash -c "cat > '$api_service_file_path'" << EOF
[Unit]
Description=Sugarfunge API
After=sugarfunge-node.service
Requires=sugarfunge-node.service

[Service]
Type=simple
User=$USER
ExecStart=$HOME/sugarfunge-api/target/release/sugarfunge-api \
    --db-uri="$DATA_DIR" \
    --node-server ws://127.0.0.1:9944
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
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4
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


# Function to fund an account
fund_account() {
    echo "Checking account balance before funding..."
    account=$(cat "$SECRET_DIR/account.txt")
    
    # Make the API request and capture the HTTP status code
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST https://api.node3.functionyard.fula.network/account/balance \
    -H "Content-Type: application/json" \
    -d "{\"account\": \"$account\"}")

    # Check if the status code is anything other than 200
    if [ "$response" != "200" ]; then
        echo "Account is not funded or an error occurred. HTTP Status: $response. Attempting to fund account..."
        secret_seed=$(cat "$SECRET_DIR/secret_seed.txt")
        
        # Fund the account
        fund_response=$(curl -s -X POST https://api.node3.functionyard.fula.network/account/fund \
        -H "Content-Type: application/json" \
        -d "{\"seed\": \"$MASTER_SEED\", \"amount\": 1000000000000000000, \"to\": \"$account\"}")
        
        echo "Fund response: $fund_response"
    else
        echo "Account is already funded. HTTP Status: $response."
    fi
}



# Function to create a pool
create_pool() {
    echo "Checking if pool already exists..."
    pool_name=$1
    region=$2

    # Get the list of existing pools
    pools_response=$(curl -s -X GET https://api.node3.functionyard.fula.network/fula/pool \
    -H "Content-Type: application/json")

    # Check if the current region exists in the list of pools
    if echo "$pools_response" | jq --arg region "$region" '.pools[] | select(.region == $region)' | grep -q 'pool_id'; then
        echo "Pool for region $region already exists. No need to create a new one."
    else
        echo "No existing pool found for region $region. Attempting to create a new pool..."
        seed=$(cat "$SECRET_DIR/secret_seed.txt")
        node_peerid=$(cat "$SECRET_DIR/node_peerid.txt")

        # Capture the HTTP status code while creating the pool
        create_response=$(curl -s -o response.json -w "%{http_code}" -X POST https://api.node3.functionyard.fula.network/fula/pool/create \
        -H "Content-Type: application/json" \
        -d "{\"seed\": \"$seed\", \"pool_name\": \"$pool_name\", \"peer_id\": \"$node_peerid\", \"region\": \"$region\"}")
        
        # Extract the pool_id from the response
        pool_id=$(cat response.json | jq '.pool_id')
        rm response.json  # Clean up the temporary file

        # Check if the pool was created successfully (HTTP status 200) and pool_id is not null
        if [[ $create_response == 200 ]] && [[ $pool_id != null ]]; then
            echo "Created Pool ID: $pool_id"
            # Update the Fula config file with the pool ID
            setup_fula_config "$pool_id"
        else
            echo "Failed to create the pool for region $region. HTTP Status: $create_response, Pool ID: $pool_id"
        fi
    fi
}

# Function to setup the Fula config file
setup_fula_config() {
    echo "Setting up Fula config..."
    pool_id="$1"
    config_path="/home/$USER/.fula/config.yaml"

    # Check if the Fula config file already exists
    mkdir -p /home/$USER/.fula/blox/store

    # Since we are initOnly and creating hte config before this step to create identity, we need to read the identity and ipniIdentity before replacing them
    EXISTING_IPNI_PUBLISHER_IDENTITY=$(grep 'ipniPublisherIdentity:' "$config_path" | awk '{print $2}')
    EXISTING_IDENTITY=$(grep 'identity:' "$config_path" | awk '{print $2}')

    # Create the config file if it doesn't exist
    cat > "$config_path" << EOF
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
EOF

    # Conditionally append identity and ipniPublisherIdentity if they exist
    if [ ! -z "$EXISTING_IDENTITY" ]; then
        echo "identity: $EXISTING_IDENTITY" >> "$config_path"
    fi

    if [ ! -z "$EXISTING_IPNI_PUBLISHER_IDENTITY" ]; then
        echo "ipniPublisherIdentity: $EXISTING_IPNI_PUBLISHER_IDENTITY" >> "$config_path"
    fi
    echo "Fula config file created at $config_path."
}

verify_pool_creation() {
    echo "Verifying pool creation..."
    region=$1  # Pass the region as an argument to the function

    # Get the list of existing pools
    pools_response=$(curl -s -X POST https://api.node3.functionyard.fula.network/fula/pool \
    -H "Content-Type: application/json" \
     -d "{}")

    # Check if the specified region exists in the list of pools
    if echo "$pools_response" | jq --arg region "$region" '.pools[] | select(.region == $region)' | grep -q 'pool_id'; then
        echo "OK Verification successful: Pool for region $region exists."
    else
        echo "ERROR: Verification failed: No pool found for region $region."
    fi
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
        generated_peer_id=$(/home/$USER/sugarfunge-node/target/release/sugarfunge-node key inspect-node-key --file "$SECRET_DIR/node_key.txt")
        
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


check_services_status() {
    echo "Checking status of services..."

    # Define your services
    declare -a services=("go-fula" "sugarfunge-node" "sugarfunge-api")

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
	echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/needrestart.conf
	
    # Check if a master seed is provided
    if [ $# -lt 1 ]; then
        echo "Please provide at least the MASTER seed as an argument."
        exit 1
    fi
	
	export MASTER_SEED=$1

    if [ $# -eq 1 ]; then
        # Only one argument provided, find the region automatically
        region=$(find_pool_region_aws)
		echo "region was determined from aws instance: $region"
        if [ -z "$region" ]; then
            echo "Could not determine the region automatically. Please provide the region as a second argument."
            exit 1
        fi
    else
        # Region provided as second argument
        region=$2
    fi
    pool_name=$(echo "$region" | sed -e 's/\([A-Z]\)/ \1/g' -e 's/^ //')
	
	echo "creating region=$region and pool_name=$pool_name"
	
    # Update and install dependencies
    sudo apt update
    sudo apt install -y wget git curl build-essential jq pkg-config libssl-dev protobuf-compiler llvm libclang-dev clang plocate cmake

	# Set LIBCLANG_PATH for the user
    # echo "export LIBCLANG_PATH=/usr/lib/llvm-14/lib/" | sudo tee /etc/profile.d/libclang.sh
	if ! grep -q 'export LIBCLANG_PATH=/usr/lib/llvm-14/lib/' ~/.profile; then
		echo "export LIBCLANG_PATH=/usr/lib/llvm-14/lib/" >> ~/.profile
	fi

	source ~/.profile

    # Install Go 1.21 from source
    install_go

    # Install Rust and Cargo
    install_rust

    # Clone and build the necessary repositories
    clone_and_build

    # Generate a strong password and save it
    generate_password
	
	# Setup and start go-fula service
    setup_gofula_service
	
	# Generate Peer ID for node
	generate_node_key
	
    # Setup and extract keys
    setup_and_extract_keys

    # Insert keys into the node
    insert_keys

    # Fund an account
    fund_account

    # Create a pool
    create_pool "$pool_name" "$region"
	
	# Setup and start node service
    setup_node_service

    # Setup and start API service
    setup_api_service
	
	cleanup
	
	unset MASTER_SEED
	
	# Verify pool creation
	verify_pool_creation "$region"
	
	# Check the status of the services
	sleep 10
	check_services_status

    echo "Setup complete. Please review the logs and verify the services are running correctly."
}

# Run the main function with the provided region
main "$@"
