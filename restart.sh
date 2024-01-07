#!/bin/bash

export FULA_CONTRACT_API_HOST="https://contract-api.functionyard.fula.network"
export FULA_SUGARFUNGE_API_HOST="http://127.0.0.1:4000"


# Variables from the original script
USER="ubuntu"  # Adjust as necessary

# Define the directories and services from the original script
DATA_DIR="/home/$USER/.sugarfunge-node/data"
SERVICES=("sugarfunge-node01.service" "sugarfunge-node02.service" "sugarfunge-node03.service" "sugarfunge-api03.service")  # Add other related services if necessary

SEED_MASTER=$1
SEED_NODE=$2
# Function to stop services in reverse order
stop_services() {
    echo "Stopping services in reverse order..."
    for (( idx=${#SERVICES[@]}-1 ; idx>=0 ; idx-- )); do
        service=${SERVICES[idx]}
        sudo systemctl stop "$service"
        echo "Stopped $service."
    done
}

# Function to clear data directories
clear_data_folders() {
    echo "Clearing data folders..."
    if [ -d "$DATA_DIR" ]; then
        sudo rm -rf "$DATA_DIR"/*
        echo "Cleared data in $DATA_DIR."
    else
        echo "Data directory $DATA_DIR does not exist."
    fi
}

# Function to start services
start_services() {
    echo "Starting services..."
    for service in "${SERVICES[@]}"; do
        sudo systemctl start "$service"
        echo "Started $service."
        sleep 10
    done
}

# Function to fund an account
fund_account() {
    echo "Funding account..."
    curl -X POST -H "Content-Type: application/json" \
    --data "{
        \"seed\": \"$1\",
        \"amount\": 1000000000000000000,
        \"to\": \"5Dc6dTQo6ZhDsHVFTDYwYz2oWDQ88kuEWrg39XWzrFagPdjS\"
    }" http://127.0.0.1:4000/account/fund
}

# Function to create a pool
create_pool() {
    echo "Creating pool..."
    curl -X POST -H "Content-Type: application/json" \
    --data "{
        \"seed\": \"$1\",
        \"pool_name\":\"Canada Central\",
        \"peer_id\": \"12D3KooWRTzN7HfmjoUBHokyRZuKdyohVVSGqKBMF24ZC3tGK78Q\",
        \"region\": \"CanadaCentral\"
    }" http://127.0.0.1:4000/fula/pool/create
}

# Function to upload a manifest
upload_manifest() {
    echo "Uploading manifest..."
    curl -X POST -H "Content-Type: application/json" \
    --data "{
        \"seed\": \"0xde74b73a4e99c09ae760e7d05c1cf50bd166312fe1be6fb46609b690efb0e472\",
        \"replication_factor\": 1,
        \"pool_id\": 1,
        \"cid\": \"QmcwQBzZcFVa7gyEQazd9WryzXKVMK2TvwBweruBZhy3pf\",
        \"manifest_metadata\": {
            \"job\": {
                \"work\": \"Storage\",
                \"engine\": \"IPFS\",
                \"uri\": \"QmcwQBzZcFVa7gyEQazd9WryzXKVMK2TvwBweruBZhy3pf\"
            }
        }
    }" $FULA_SUGARFUNGE_API_HOST/fula/manifest/upload
}

# Function to store a manifest
store_manifest() {
    echo "Storing manifest..."
    curl -X POST -H "Content-Type: application/json" \
    --data "{
        \"seed\": \"0x141fa827544cfc60756675ee58ebfd54e8311779c7ef1ec44265e8605d2f2bdd\",
        \"uploader\": \"5CcHZucP2u1FXQW9wuyC11vAVxB3c48pUhc5cc9b3oxbKPL2\",
        \"cid\": \"QmcwQBzZcFVa7gyEQazd9WryzXKVMK2TvwBweruBZhy3pf\",
        \"pool_id\": 1
    }" $FULA_SUGARFUNGE_API_HOST/fula/manifest/storage
}


# Main function to orchestrate stopping, clearing, and restarting
main() {
    # Stop all the services
    stop_services

    # Clear only the data folders
    clear_data_folders

    # Restart the stopped services
    start_services

    # Wait a little for services to be fully up
    sleep 5

    # Fund account
    fund_account "$SEED_MASTER"

    # Create pool
    create_pool "$SEED_NODE"

    upload_manifest

    store_manifest

    echo "All services have been restarted and data folders cleared."
}

# Run the main function
main "$@"
