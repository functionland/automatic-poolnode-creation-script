#!/bin/bash

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


# Main function to orchestrate stopping, clearing, and restarting
main() {
    # Stop all the services
    stop_services

    # Clear only the data folders
    clear_data_folders

    # Restart the stopped services
    start_services

    # Wait a little for services to be fully up
    sleep 20

    # Fund account
    fund_account "$SEED_MASTER"

    # Create pool
    create_pool "$SEED_NODE"

    echo "All services have been restarted and data folders cleared."
}

# Run the main function
main "$@"
