#!/bin/bash

set -e

# Variables
USER="ubuntu"

CLOUDFLARE_API_TOKEN=""
DOMAIN=""
CLOUDFLARE_ZONE_ID=""
IDENTITY=""

# Function to show usage
usage() {
    echo "Usage: $0 --identity=123 --user=ubuntu --cloudflaretoken=API_TOKEN --cloudflarezone= --domain=test.fx.land"
    exit 1
}

# Parse named parameters
while [ "$1" != "" ]; do
    case $1 in
        --identity=*)
            IDENTITY="${1#*=}"
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
        --domain=*)
            DOMAIN="${1#*=}"
            ;;
        *)
            echo "$1 i not supported"
            usage
            ;;
    esac
    shift
done

if [ -z "$DOMAIN" ]; then
    echo "missing domain parameter. Skipping the domain handling"
else
    DOMAIN="functionyard.fula.network"
fi

if [ -z "$USER" ]; then
    echo "missing USER parameter."
    USER="ubuntu"
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "missing CLOUDFLARE_API_TOKEN parameter."
    usage
fi

if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
    echo "missing CLOUDFLARE_ZONE_ID parameter."
    usage
fi

if [ -z "$IDENTITY" ]; then
    echo "missing identity parameter."
    usage
fi

IDENTITY_FILE="/home/${USER}/identity.key"
CONFIG_FILE="/home/${USER}/config.json"
LOG_DIR="/var/log"
USER_HOME="/home/${USER}"

# Function to get the AWS Token
get_aws_token() {
    echo $(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
}

install_packages() {
    sudo apt-get update -qq
    sudo apt-get install -y docker.io nginx software-properties-common certbot python3-certbot-nginx
    sudo apt-get install -y wget git curl build-essential jq pkg-config libssl-dev protobuf-compiler llvm libclang-dev clang plocate cmake
    sudo apt-get install -y g++ libx11-dev libasound2-dev libudev-dev libxkbcommon-x11-0
    sudo systemctl start docker
    sudo systemctl enable docker
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
clone_and_build() {

	echo "Installing relay"
    if [ ! -d "/home/${USER}/go-libp2p-relay-daemon" ] || [ -z "$(ls -A /home/${USER}/go-libp2p-relay-daemon)" ]; then
        git clone https://github.com/functionland/go-libp2p-relay-daemon.git  /home/${USER}/go-libp2p-relay-daemon
    fi
    cd /home/${USER}/go-libp2p-relay-daemon
    go build -o go-libp2p-relay-daemon ./cmd/go-libp2p-relay-daemon
    cd ..
}


# Function to set up and extract keys
setup_and_extract_keys() {
	echo "setup_and_extract_keys"
    if [ ! -f $CONFIG_FILE ]; then
        cp  /home/${USER}/go-libp2p-relay-daemon/config.json $CONFIG_FILE
    fi
    if [ ! -f $IDENTITY_FILE ]; then
        cd /home/${USER}/go-libp2p-relay-daemon
        go run ./cmd/identity --identity="${IDENTITY}"
        cp  /home/${USER}/go-libp2p-relay-daemon/identity.key $IDENTITY_FILE
        cd ..
    fi
}


# Function to set up and start relay service
setup_relay_service() {
    relay_service_file_path="/etc/systemd/system/relay.service"
    echo "Setting up relay service at $relay_service_file_path"

    # Check if the file exists and then remove it
    if [ -f "$relay_service_file_path" ]; then
        sudo systemctl stop relay.service
        sudo systemctl disable relay.service
        sudo rm "$relay_service_file_path"
        sudo systemctl daemon-reload
        echo "Removed $relay_service_file_path."
    else
        echo "$relay_service_file_path does not exist."
    fi

    # Create the service file using the provided path
    sudo bash -c "cat > '$relay_service_file_path'" << EOF
[Unit]
Description=Relay Service
After=network.target

[Service]
Type=simple
Environment=HOME=/home/$USER
ExecStart=/home/$USER/go-libp2p-relay-daemon/go-libp2p-relay-daemon -config "${CONFIG_FILE}" -id "${IDENTITY_FILE}"
Restart=always
RestartSec=10s
StartLimitInterval=5min
StartLimitBurst=4

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable the service
    sudo systemctl daemon-reload
    sudo systemctl enable relay.service
    sudo systemctl start relay.service
    echo "Relay service has been set up and started."
}

verify_services_status() {
    echo "Checking status of services..."

    # Define your services
    declare -a services=("relay")

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

create_cloudflare_dns_record() {
  public_ip="$1"

  # Construct the DNS record name
  dns_record="dev.relay.${DOMAIN}"

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

    # Clone and build the necessary repositories
    clone_and_build

    setup_and_extract_keys
	
	# Setup and start relay service
    setup_relay_service
    
	cleanup

    echo "Setup complete."

    verify_services() {

        verify_services_status
        services_running=$?

        return $services_running
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
