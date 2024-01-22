#!/bin/bash

set -e

# Function to clone and build repositories
update_and_build() {
	echo "Updating sugarfunge-api"
    if [ ! -d "sugarfunge-api" ] || [ -z "$(ls -A sugarfunge-api)" ]; then
        git clone https://github.com/functionland/sugarfunge-api.git
    fi
    cd sugarfunge-api
    git pull
    cargo build --release
    cd ..
	
	echo "Updating sugarfunge-node"
    if [ ! -d "sugarfunge-node" ] || [ -z "$(ls -A sugarfunge-node)" ]; then
        git clone https://github.com/functionland/sugarfunge-node.git
    fi
    cd sugarfunge-node
    git pull
    cargo build --release
    cd ..

	echo "Updating go-fula"
    if [ ! -d "go-fula" ] || [ -z "$(ls -A go-fula)" ]; then
        git clone https://github.com/functionland/go-fula.git
    fi
    cd go-fula
    git pull
    go build -o go-fula ./cmd/blox
    cd ..
}

update_and_restart() {
    # Stop services
    echo "Stopping services..."
    sudo systemctl stop sugarfunge-node.service
    sudo systemctl stop sugarfunge-api.service
    sudo systemctl stop go-fula.service

    # Get docker images and process them
    echo "Processing Docker images..."
    sudo docker images | while read -r repository tag image_id created size
    do
        # Skip header line
        if [[ "$repository" == "REPOSITORY" ]]; then
            continue
        fi

        if [[ "$tag" == "<none>" ]]; then
            # Remove images without a tag
            echo "Removing image $image_id..."
            sudo docker rmi "$image_id"
        else
            # Pull images with a tag
            echo "Pulling image $repository:$tag..."
            sudo docker pull "$repository:$tag"
        fi
        sleep 2
    done

    # Start services
    echo "Starting services..."
    sudo systemctl start sugarfunge-node.service
    sleep 5
    sudo systemctl start sugarfunge-api.service
    sleep 5
    sudo systemctl start go-fula.service

    # Check services status
    echo "Checking services status..."
    for service in sugarfunge-node.service sugarfunge-api.service go-fula.service
    do
        status=$(sudo systemctl is-active "$service")
        if [[ "$status" != "active" ]]; then
            echo "Error: $service is not running!"
        else
            echo "$service is running."
        fi
        sleep 5
    done
}

# Main script execution
main() {
    update_and_build
    sleep 10
    update_and_restart
}

# Run the main function with the provided region
main "$@"