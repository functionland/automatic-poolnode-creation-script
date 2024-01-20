#!/bin/bash

# Define your regions
regions=(
    ap-southeast-1
    ap-southeast-2
    ap-northeast-1
    ca-central-1
    eu-central-1
    eu-west-1
    eu-west-2
    eu-south-1
    eu-west-3
    eu-north-1
    eu-central-2
    eu-south-2
    me-central-1
    il-central-1
    sa-east-1
)

# Seed parameter
seed_parameter=$1

# Maximum number of retries
max_retries=3

# Array to keep track of failed regions
declare -a failed_regions
# Function to process region
process_region() {
    local region=$1

    echo "Processing region: $region"
    # Import key pair and create CloudFormation stack
    # Import key pair
    aws ec2 import-key-pair --key-name functionland --public-key-material file:///home/cloudshell-user/functionland-public.b64 --region $region

    # Create CloudFormation stack
    creation_output=$(aws cloudformation create-stack --stack-name FulaEC2Stack --template-body file:///home/cloudshell-user/aws.yaml --parameters ParameterKey=UbuntuAmiId,ParameterValue=$(aws ec2 describe-images --region $region --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --output text) ParameterKey=SeedParameter,ParameterValue="$seed_parameter" --region $region --capabilities CAPABILITY_IAM 2>&1)

    if [[ $creation_output == *"CREATE_COMPLETE"* ]]; then
        echo "Stack creation succeeded in region $region"

        # Retrieve the public IP of the instance
        instance_ip=$(aws ec2 describe-instances --region $region --query 'Reservations[].Instances[?State.Name==`running`].PublicIpAddress' --output text)

        if [ -n "$instance_ip" ]; then
            echo "Instance IP: $instance_ip"
            # SSH Command (This part needs to be run from a system where SSH is possible)
            echo "ssh -i /path/to/functionland.pem ubuntu@$instance_ip 'bash ~/automatic-poolnode-creation-script/pool_creation.sh $seed_parameter'"
        else
            echo "Failed to retrieve the instance IP address."
        fi

    elif [[ $creation_output == *"already exists"* ]]; then
        echo "Stack already exists in region $region"

    else
        echo "Stack creation failed in region $region"
        failed_regions+=("$region")
    fi
}

# Initial loop through each region
for region in "${regions[@]}"; do
    process_region "$region"
done

# Retry failed regions
for (( i=0; i<max_retries; i++ )); do
    if [ ${#failed_regions[@]} -eq 0 ]; then
        echo "All regions processed successfully."
        break
    fi

    echo "Retrying failed regions: ${failed_regions[*]}"
    current_failed=("${failed_regions[@]}")
    failed_regions=() # Reset failed regions

    for region in "${current_failed[@]}"; do
        process_region "$region"
    done
done

if [ ${#failed_regions[@]} -ne 0 ]; then
    echo "Failed to create stacks in the following regions after $max_retries attempts: ${failed_regions[*]}"
fi