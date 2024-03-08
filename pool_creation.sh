#!/bin/bash

set -e

# Variables
USER="ubuntu"

CLOUDFLARE_API_TOKEN=""
POOL_DOMAIN=""
CLOUDFLARE_ZONE_ID=""
MASTER_SEED=""
REGION_INPUT=""
NODE_API_URL=""
POOL_ID=""

# Function to show usage
usage() {
    echo "Usage: $0 --seed=123 --user=ubuntu --cloudflaretoken=API_TOKEN --domain=test.fx.land --region=us-west-1 --api=https://api."
    exit 1
}

# Parse named parameters
while [ "$1" != "" ]; do
    case $1 in
        --seed=*)
            MASTER_SEED="${1#*=}"
            ;;
        --api=*)
            NODE_API_URL="${1#*=}"
            ;;
        --cloudflaretoken=*)
            CLOUDFLARE_API_TOKEN="${1#*=}"
            ;;
        --cloudflarezone=*)
            CLOUDFLARE_ZONE_ID="${1#*=}"
            ;;
        --user=*)
            USER="${1#*=}"
            ;;
        --region=*)
            REGION_INPUT="${1#*=}"
            ;;
        --domain=*)
            POOL_DOMAIN="${1#*=}"
            ;;
        *)
            echo "$1 i not supported"
            usage
            ;;
    esac
    shift
done

if [ -z "$POOL_DOMAIN" ]; then
    echo "missing domain parameter. Skipping the domain handling"
else
    POOL_DOMAIN="functionyard.fula.network"
fi

if [ -z "$USER" ]; then
    echo "missing USER parameter."
    USER="ubuntu"
fi

if [ -z "$NODE_API_URL" ]; then
    echo "missing NODE_API_URL parameter."
    NODE_API_URL="https://api.node3.functionyard.fula.network"
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "missing CLOUDFLARE_API_TOKEN parameter."
    usage
fi

if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
    echo "missing CLOUDFLARE_ZONE_ID parameter."
    usage
fi

if [ -z "$MASTER_SEED" ]; then
    echo "missing MASTER_SEED parameter."
    usage
fi

PASSWORD_FILE="/home/${USER}/password.txt"
SECRET_DIR="/home/${USER}/.secrets"
EXTERNAL="/uniondrive"
DATA_DIR="${EXTERNAL}/data"
LOG_DIR="/var/log"
USER_HOME="/home/${USER}"
FULA_CONFIG="/home/${USER}/.fula/config.yaml"

sudo mkdir -p "${EXTERNAL}"
sudo mkdir -p "${DATA_DIR}"

getent group fula >/dev/null || sudo groupadd fula
sudo usermod -a -G fula root
sudo usermod -a -G fula ${USER}
sudo chown root:fula "${EXTERNAL}"
sudo chmod 777 -R "${EXTERNAL}"


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
        ap-south-2) echo "AsiaPacificHyderabad" ;;
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

install_packages() {
    sudo apt-get update -qq
    sudo apt-get install -y docker.io nginx software-properties-common certbot python3-certbot-nginx
    sudo apt-get install -y wget git curl build-essential jq pkg-config libssl-dev protobuf-compiler llvm libclang-dev clang plocate cmake
    sudo apt-get install -y g++ libx11-dev libasound2-dev libudev-dev libxkbcommon-x11-0
    sudo systemctl start docker
    sudo systemctl enable docker
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
    source "$USER_HOME/.cargo/env"
	
	rustup default stable
	rustup update nightly
	rustup update stable
	rustup target add wasm32-unknown-unknown --toolchain nightly
	rustup target add wasm32-unknown-unknown
}

# Function to pull the required Docker image and verify
pull_docker_image_ipfs() {
    echo "Pulling the required Docker image ipfs..."
    sudo docker pull ipfs/kubo:master-latest

    # Check if the image was pulled successfully
    if sudo docker images | grep -q 'ipfs/kubo'; then
        echo "Docker image kubo pulled successfully."
    else
        echo "Error: Docker image kubo pull failed."
        exit 1
    fi
}

# Function to pull the required Docker image and verify
pull_docker_image_ipfs_cluster() {
    echo "Pulling the required Docker image ipfs-cluster..."
    sudo docker pull ipfs/ipfs-cluster:stable

    # Check if the image was pulled successfully
    if sudo docker images | grep -q 'ipfs/ipfs-cluster'; then
        echo "Docker image ipfs-cluster pulled successfully."
    else
        echo "Error: Docker image ipfs-cluster pull failed."
        exit 1
    fi
}

# Function to clone and build repositories
clone_and_build() {
	echo "Installing sugarfunge-api"
    if [ ! -d "/home/${USER}/sugarfunge-api" ] || [ -z "$(ls -A /home/${USER}/sugarfunge-api)" ]; then
        git clone https://github.com/functionland/sugarfunge-api.git  /home/${USER}/sugarfunge-api
    fi
    cd /home/${USER}/sugarfunge-api
    cargo build --release
    cd ..
	
	echo "Installing sugarfunge-node"
    if [ ! -d "/home/${USER}/sugarfunge-node" ] || [ -z "$(ls -A /home/${USER}/sugarfunge-node)" ]; then
        git clone https://github.com/functionland/sugarfunge-node.git  /home/${USER}/sugarfunge-node
    fi
    cd /home/${USER}/sugarfunge-node
    cargo build --release
    cd ..

	echo "Installing go-fula"
    if [ ! -d "/home/${USER}/go-fula" ] || [ -z "$(ls -A /home/${USER}/go-fula)" ]; then
        git clone https://github.com/functionland/go-fula.git  /home/${USER}/go-fula
    fi
    cd /home/${USER}/go-fula
    go build -o go-fula ./cmd/blox
    cd ..

    echo "Clonning fula-ota"
    if [ ! -d "/home/${USER}/fula-ota" ] || [ -z "$(ls -A /home/${USER}/fula-ota)" ]; then
        git clone https://github.com/functionland/fula-ota.git /home/${USER}/fula-ota
    fi
}


# Function to set up and extract keys
setup_and_extract_keys() {
	echo "setup_and_extract_keys"
    sudo mkdir -p "$SECRET_DIR"
    if [ ! -f "$SECRET_DIR/secret_phrase.txt" ] || [ ! -f "$SECRET_DIR/secret_seed.txt" ]; then
        output=$(/home/$USER/sugarfunge-node/target/release/sugarfunge-node key generate --scheme Sr25519 --password="$(cat "$PASSWORD_FILE")" 2>&1)
        echo "$output"
        secret_phrase=$(echo "$output" | grep "Secret phrase:" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        echo -n "$secret_phrase" | sudo tee "$SECRET_DIR/secret_phrase.txt" > /dev/null

        secret_seed=$(echo "$output" | grep "Secret seed:" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        echo -n "$secret_seed" | sudo tee "$SECRET_DIR/secret_seed.txt" > /dev/null

        account=$(echo "$output" | grep "SS58 Address:" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        echo -n "$account" | sudo tee "$SECRET_DIR/account.txt" > /dev/null
    fi
}

# Function to insert keys into the node
insert_keys() {
	echo "insert_keys"
    sudo chmod -R 775 "$SECRET_DIR"
    sudo chmod -R 775 "$DATA_DIR"
    sudo chmod -R 775 "$USER_HOME/sugarfunge-node"
    sudo chown -R ubuntu:ubuntu "$DATA_DIR"
    sudo chown -R ubuntu:ubuntu "$USER_HOME/sugarfunge-node"
    secret_phrase=$(cat "$SECRET_DIR/secret_phrase.txt")
    sudo /home/$USER/sugarfunge-node/target/release/sugarfunge-node key insert --base-path="$DATA_DIR" --chain $USER_HOME/sugarfunge-node/customSpecRaw.json --scheme Sr25519 --suri "$secret_phrase" --password "$(cat "$PASSWORD_FILE")" --key-type aura
    sudo /home/$USER/sugarfunge-node/target/release/sugarfunge-node key insert --base-path="$DATA_DIR" --chain $USER_HOME/sugarfunge-node/customSpecRaw.json --scheme Ed25519 --suri "$secret_phrase" --password "$(cat "$PASSWORD_FILE")" --key-type gran
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
User=root
ExecStart=$USER_HOME/sugarfunge-node/target/release/sugarfunge-node \
--chain $USER_HOME/sugarfunge-node/customSpecRaw.json \
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
--validator \
--bootnodes /dns4/node.functionyard.fula.network/tcp/30334/p2p/12D3KooWBeXV65svCyknCvG1yLxXVFwRxzBLqvBJnUF6W84BLugv
Restart=always
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4
StandardOutput=file:$LOG_DIR/MyNode.log
StandardError=file:$LOG_DIR/MyNode.err

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
    sudo tee "$api_service_file_path" > /dev/null << EOF
[Unit]
Description=Sugarfunge API
After=sugarfunge-node.service
Requires=sugarfunge-node.service

[Service]
Type=simple
User=root
ExecStart=$USER_HOME/sugarfunge-api/target/release/sugarfunge-api \
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
StandardOutput=file:$LOG_DIR/MyNodeAPI.log
StandardError=file:$LOG_DIR/MyNodeAPI.err

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
	sudo mkdir -p "$SECRET_DIR"
    echo -n "$blox_peer_id" | sudo tee "$SECRET_DIR/node_peerid.txt" > /dev/null
    echo "Blox peer ID saved to $SECRET_DIR/node_peerid.txt"

    # Create the service file using the provided path
    sudo bash -c "cat > '$gofula_service_file_path'" << EOF
[Unit]
Description=Go Fula Service
After=network.target

[Service]
Type=simple
Environment=HOME=/home/$USER
ExecStart=/home/$USER/go-fula/go-fula --config /home/$USER/.fula/config.yaml --poolHost
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
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$NODE_API_URL/account/balance" \
    -H "Content-Type: application/json" \
    -d "{\"account\": \"$account\"}")

    # Check if the status code is anything other than 200
    if [ "$response" != "200" ]; then
        echo "Account is not funded or an error occurred. HTTP Status: $response. Attempting to fund account..."
        secret_seed=$(cat "$SECRET_DIR/secret_seed.txt")
        
        # Fund the account
        fund_response=$(curl -s -X POST "$NODE_API_URL/account/fund" \
        -H "Content-Type: application/json" \
        -d "{\"seed\": \"$MASTER_SEED\", \"amount\": 4000000000000000000, \"to\": \"$account\"}")
        
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
    pools_response=$(curl -s -X POST "$NODE_API_URL/fula/pool" \
    -H "Content-Type: application/json" \
    -d "{}")

    # Check if the current region exists in the list of pools
    if echo "$pools_response" | jq --arg region "$region" '.pools[] | select(.region == $region) | .pool_id' | grep -q .; then
        POOL_ID=$(echo "$pools_response" | jq --arg region "$region" '.pools[] | select(.region == $region) | .pool_id')
        echo "Pool for region $region already exists. No need to create a new one."
    elif echo "$pools_response" | jq --arg pool_name "$pool_name" '.pools[] | select(.pool_name == $pool_name) | .pool_id' | grep -q .; then
        POOL_ID=$(echo "$pools_response" | jq --arg pool_name "$pool_name" '.pools[] | select(.pool_name == $pool_name) | .pool_id')
        echo "Pool for pool_name $pool_name already exists. No need to create a new one."
    else
        echo "No existing pool found for region $region. Attempting to create a new pool..."
        seed=$(cat "$SECRET_DIR/secret_seed.txt")
        node_peerid=$(cat "$SECRET_DIR/node_peerid.txt")

        # Capture the HTTP status code while creating the pool
        create_response=$(curl -s -o response.json -w "%{http_code}" -X POST "$NODE_API_URL/fula/pool/create" \
        -H "Content-Type: application/json" \
        -d "{\"seed\": \"$seed\", \"pool_name\": \"$pool_name\", \"peer_id\": \"$node_peerid\", \"region\": \"$region\"}")
        
        # Extract the pool_id from the response
        POOL_ID=$(jq '.pool_id' < response.json)
        rm response.json  # Clean up the temporary file

        # Check if the pool was created successfully (HTTP status 200) and pool_id is not null
        if [[ $create_response == 200 ]] && [[ $POOL_ID != null ]]; then
            echo "Created Pool ID: $POOL_ID"
            # Update the Fula config file with the pool ID
            setup_fula_config "$POOL_ID"
        else
            echo "Failed to create the pool for region $region. HTTP Status: $create_response, Pool ID: $POOL_ID"
        fi
    fi
}

# Function to setup the Fula config file
setup_fula_config() {
    echo "Setting up Fula config..."
    local pool_id="$1"
    config_path="/home/$USER/.fula/config.yaml"

    # Check if the Fula config file already exists
    sudo mkdir -p /home/$USER/.fula/blox/store

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
authorizer: "$(cat ${SECRET_DIR}/node_peerid.txt)"
authorizedPeers: []
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

config_ipfs() {
    cd /home/${USER}/go-fula/modules/initipfs
    if [ ! -f "/home/${USER}/go-fula/modules/initipfs/go.mod" ]; then
        go mod init main.go
    fi
    go mod tidy
    go run /home/${USER}/go-fula/modules/initipfs --internal="/home/${USER}/.fula" --external="${EXTERNAL}" --defaultIpfsConfig="/home/${USER}/fula-ota/docker/fxsupport/linux/kubo/config" --apiIp="127.0.0.1"
    cd /home/${USER}
}

# Function to set up and start IPFS service
setup_ipfs_service() {
    sudo mkdir -p "/home/${USER}/.fula/ipfs_data"
    sudo mkdir -p "${EXTERNAL}/ipfs_staging"
    sudo chown -R "${USER}":"${USER}" "${EXTERNAL}/ipfs_staging"
    ipfs_service_file_path="/etc/systemd/system/ipfs.service"
    echo "Setting up IPFS service at ${ipfs_service_file_path}"
    sudo touch /home/${USER}/.fula/.ipfs_setup
    # Debug mode service configuration
    EXEC_START="/usr/bin/docker run -u root --rm --name ipfs_host --network host \
-e IPFS_PROFILE=badgerds \
-e IPFS_PATH=/internal/ipfs_data \
-v ${EXTERNAL}/ipfs_staging:/export:rw,shared \
-v ${EXTERNAL}:/uniondrive:rw,shared \
-v /home/${USER}/.fula:/internal:rw,shared \
-v /home/${USER}/fula-ota/docker/fxsupport/linux/kubo:/container-init.d:rw,shared \
ipfs/kubo:master-latest"
    ENVIRONMENT="IPFS_PROFILE=badgerds \
,IPFS_PATH=/internal/ipfs_data"

    sudo bash -c "cat > '${ipfs_service_file_path}'" << EOF
[Unit]
Description=IPFS

[Service]
Type=simple
User=root
Environment=$ENVIRONMENT
ExecStart=$EXEC_START
Restart=always
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4
StandardOutput=file:${LOG_DIR}/ipfs.log
StandardError=file:${LOG_DIR}/ipfs.err

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ipfs.service
    sudo systemctl start ipfs.service
    echo "IPFS service has been set up and started."
}

verify_ipfs_running() {
  # Attempt to get IPFS node ID information
  response=$(curl -s -X POST http://127.0.0.1:5001/api/v0/id)

  # Check if curl request was successful (non-zero exit code indicates failure)
  if [ $? -ne 0 ]; then
    echo "Error: IPFS does not appear to be running. curl request failed."
    return 1  # Return an error code for non-zero exit status
  fi

  # Check if the response contains an "ID" field (indicates valid IPFS response)
  if ! echo "$response" | grep -q "ID"; then
    echo "Error: IPFS does not appear to be running. Invalid response."
    return 1  # Return an error code for non-zero exit status
  fi

  # Success!
  echo "IPFS is running."
  return 0 
}

config_ipfscluster() {
    cd /home/${USER}/go-fula/modules/initipfscluster
    if [ ! -f "/home/${USER}/go-fula/modules/initipfscluster/go.mod" ]; then
        go mod init main.go
    fi
    sudo mkdir -p "${EXTERNAL}/ipfs-cluster"
    sudo chown -R "${USER}":"${USER}" "${EXTERNAL}/ipfs-cluster"
    go mod tidy
    go run /home/${USER}/go-fula/modules/initipfscluster --internal="/home/${USER}/.fula" --external="${EXTERNAL}"
    cd /home/${USER}
}

# Function to set up and start API service
setup_ipfscluster_service() {
    local poolName=""
    while [ -z "$poolName" ] || [ "$poolName" = "0" ]; do
        echo "Waiting for CLUSTER_CLUSTERNAME to be set..."
        if [ -f "$FULA_CONFIG" ];then
            poolName=$(grep 'poolName:' "${FULA_CONFIG}" | cut -d':' -f2 | tr -d ' "')
        fi
        sleep 5
    done
    secret=$(printf "%s" "${poolName}" | sha256sum | cut -d' ' -f1)
    local peer_id
    local node_account

    while [ -z "$peer_id" ] || [ -z "$node_account" ]; do
        echo "Waiting for CLUSTER_CLUSTERNAME to be set..."
        peer_id=$(cat "$SECRET_DIR/node_peerid.txt")
        node_account=$(cat "$SECRET_DIR/account.txt")
        sleep 5
    done

    ipfscluster_service_file_path="/etc/systemd/system/ipfscluster.service"
    sudo touch /home/${USER}/.fula/.ipfscluster_setup
    echo "Setting up IPFS CLUSTER service at ${ipfscluster_service_file_path}"
    # Debug mode service configuration
    EXEC_START="/usr/bin/docker run -u root --rm --name ipfs_cluster --network host \
-e IPFS_CLUSTER_PATH=/uniondrive/ipfs-cluster \
-e CLUSTER_REPLICATIONFACTORMIN=2 \
-e CLUSTER_REPLICATIONFACTORMAX=6 \
-e CLUSTER_DISABLEREPINNING=false \
-e CLUSTER_CLUSTERNAME=${poolName} \
-e CLUSTER_SECRET=${secret} \
-e CLUSTER_FOLLOWERMODE=false \
-e CLUSTER_CRDT_TRUSTEDPEERS=${peer_id} \
-e CLUSTER_PEERNAME=${node_account} \
-v ${EXTERNAL}:/uniondrive:rw,shared \
-v /home/${USER}/.fula:/internal:rw,shared \
ipfs/ipfs-cluster:stable"
    ENVIRONMENT="IPFS_CLUSTER_PATH=/uniondrive/ipfs-cluster \
,CLUSTER_REPLICATIONFACTORMIN=2 \
,CLUSTER_REPLICATIONFACTORMAX=6 \
,CLUSTER_DISABLEREPINNING=false \
,CLUSTER_CLUSTERNAME=${poolName} \
,CLUSTER_SECRET=${secret} \
,CLUSTER_FOLLOWERMODE=false \
,CLUSTER_CRDT_TRUSTEDPEERS=${peer_id} \
,CLUSTER_PEERNAME=${node_account}"

    sudo bash -c "cat > '${ipfscluster_service_file_path}'" << EOF
[Unit]
Description=IPFSCLUSTER

[Service]
Type=simple
User=root
Environment=$ENVIRONMENT
ExecStart=$EXEC_START
Restart=always
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4
StandardOutput=file:${LOG_DIR}/ipfscluster.log
StandardError=file:${LOG_DIR}/ipfscluster.err

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ipfscluster.service
    sudo systemctl start ipfscluster.service
    echo "IPFS CLUSTER service has been set up and started."
}

verify_ipfscluster_running() {
  # Attempt to get IPFS Cluster ID information
  response=$(curl -s -X POST http://127.0.0.1:9094/id)

  # Check if curl request was successful (non-zero exit code indicates failure)
  if [ $? -ne 0 ]; then
    echo "Error: IPFS Cluster does not appear to be running. curl request failed."
    return 1  # Return an error code for non-zero exit status
  fi

  # Key Checks for IPFS Cluster Health
  if ! echo "$response" | grep -q "id" || \
     ! echo "$response" | grep -q "cluster_peers" || \
     ! echo "$response" | jq -e '.error == ""' > /dev/null; then 
    echo "Error: IPFS Cluster might not be running correctly. Invalid response."
    return 1  # Return an error code 
  fi

  # Success!
  echo "IPFS Cluster appears to be running."
  return 0 
}

verify_pool_creation() {
    echo "Verifying pool creation..."
    region=$1  # Pass the region as an argument to the function

    # Get the list of existing pools
    pools_response=$(curl -s -X POST "$NODE_API_URL/fula/pool" \
    -H "Content-Type: application/json" \
    -d "{}")

    # Check if the specified region exists in the list of pools
    if echo "$pools_response" | jq --arg region "$region" '.pools[] | select(.region == $region)' | grep -q 'pool_id'; then
        echo "OK Verification successful: Pool for region $region exists."
        return 0
    else
        echo "ERROR: Verification failed: No pool found for region $region."
        return 1
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
            echo -n "$new_key" | sudo tee "$SECRET_DIR/node_key.txt" > /dev/null
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


verify_services_status() {
    echo "Checking status of services..."

    # Define your services
    declare -a services=("go-fula" "sugarfunge-node" "sugarfunge-api" "ipfs")

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
        return 1
    else
        echo "OK All services are running as expected."
        return 0
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

zip_and_upload() {
    local region_name=$1
    local zip_filename="${region_name}.zip"

    echo "Zipping directories..."
    zip -r "$zip_filename" "$PASSWORD_FILE" "$SECRET_DIR"

    echo "Uploading $zip_filename to S3..."
    aws s3 cp "$zip_filename" "s3://fula-pools/$zip_filename"

    echo "Upload complete. Cleaning up local zip file..."
    rm "$zip_filename"
}

create_cloudflare_dns_record() {
  local pool_id="$1"
  public_ip="$2"

  # Construct the DNS record name
  dns_record="${pool_id}.pools.${POOL_DOMAIN}"

  # Create DNS A Record using Cloudflare API
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
       -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
       -H "Content-Type: application/json" \
       --data "{\"type\":\"A\",\"name\":\"${dns_record}\",\"content\":\"${public_ip}\",\"ttl\":120,\"proxied\":false}"
}

get_public_addr() {
# Function to get the AWS Region
    local token=$1
    echo $(curl -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/public-ipv4 -s)
}

# Main script execution
main() {
	# Set DEBIAN_FRONTEND to noninteractive to avoid interactive prompts
    export DEBIAN_FRONTEND=noninteractive
	echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/needrestart.conf

    if [ -z "${REGION_INPUT}" ]; then
        # Only one argument provided, find the region automatically
        region=$(find_pool_region_aws)
		echo "region was determined from aws instance: $region"
        if [ -z "$region" ]; then
            echo "Could not determine the region automatically. Please provide the region as a second argument."
            exit 1
        fi
    else
        # Region provided as second argument
        region="${REGION_INPUT}"
    fi
    pool_name=$(echo "$region" | sed -e 's/\([A-Z]\)/ \1/g' -e 's/^ //')
	
	echo "creating region=$region and pool_name=$pool_name"
	
    # Update and install dependencies
    sudo apt update
    sudo apt install -y awscli zip wget git curl build-essential jq pkg-config libssl-dev protobuf-compiler llvm libclang-dev clang plocate cmake

    install_packages

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

    # ipfs nad ipfs-cluster
    pull_docker_image_ipfs
    pull_docker_image_ipfs_cluster
	
	# Setup and start go-fula service
    setup_gofula_service

    # setup ipfs service
    config_ipfs
    setup_ipfs_service
	
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

    # setup ipfscluster service
    config_ipfscluster
    setup_ipfscluster_service

    # Setup domain name
    local public_ip
    aws_token=$(get_aws_token)
    public_ip=$(get_public_addr "$aws_token")

    public_ip=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    create_cloudflare_dns_record "$POOL_ID" "$public_ip"
	
	cleanup

    echo "Setup complete."

    echo "uploading keys and secrets to aws s3"
    zip_and_upload "$region"

    verify_services() {
        verify_pool_creation "$region"
        pool_created=$?

        sleep 10

        verify_services_status
        services_running=$?

        verify_ipfs_running
        ipfs_running=$?

        verify_ipfscluster_running
        ipfscluster_running=$?

        return $((ipfs_running + pool_created + services_running + ipfscluster_running))
    }

    # Check the status of the services
    verify_services
    success_code=$?
   
    # Determine final message based on success or failure
    if [ $success_code -eq 0 ]; then
        echo "Setup complete. All verifications were successful!"
    else
        echo "Setup encountered errors. Please review the logs for more details."
    fi

    echo "everything is finished"

}

# Run the main function with the provided region
main "$@"
