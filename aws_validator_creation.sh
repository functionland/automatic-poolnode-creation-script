#!/bin/bash

# Initialize parameters
eip_allocation_id=""
validator_password01=""
validator_password02=""

# Define target region
region="us-east-1"
bucket_name="fula-validator" # Change this to your actual S3 bucket name
pem_key_path="s3://${bucket_name}/functionland.pem"
public_key_path="s3://${bucket_name}/functionland-public.b64"
cloudformation_yaml_path="https://raw.githubusercontent.com/functionland/automatic-poolnode-creation-script/main/aws-validator.yaml"

# Manual parsing of command-line arguments
for arg in "$@"
do
    case $arg in
        --eip_allocation_id=*)
        eip_allocation_id="${arg#*=}"
        shift # Remove --eip_allocation_id from processing
        ;;
        --validator_password01=*)
        validator_password01="${arg#*=}"
        shift # Remove --validator_password01 from processing
        ;;
        --validator_password02=*)
        validator_password02="${arg#*=}"
        shift # Remove --validator_password02 from processing
        ;;
    esac
done

# Check if required parameters are provided
if [ -z "$eip_allocation_id" ] || [ -z "$validator_password01" ] || [ -z "$validator_password02" ]; then
    echo "Missing required parameters."
    echo "Usage: $0 --eip_allocation_id=eipalloc-xxxx --validator_password01=PASSWORD1 --validator_password02=PASSWORD2"
    exit 1
fi

# Download key pair from S3
aws s3 cp "$pem_key_path" /home/cloudshell-user/functionland.pem
aws s3 cp "$public_key_path" /home/cloudshell-user/functionland-public.b64

# Download the CloudFormation YAML file
curl -o /home/cloudshell-user/aws-validator.yaml "$cloudformation_yaml_path"

# Set permissions for the key file
chmod 600 /home/cloudshell-user/functionland.pem
domain01="node.functionyard.fula.network"
bootnodes="/ip4/127.0.0.1/tcp/30334/p2p/12D3KooWBeXV65svCyknCvG1yLxXVFwRxzBLqvBJnUF6W84BLugv"

# Import key pair
aws ec2 import-key-pair --key-name functionland --public-key-material file:///home/cloudshell-user/functionland-public.b64 --region $region

# Check if the stack exists and proceed accordingly
stack_status=$(aws cloudformation describe-stacks --stack-name ValidatorEC2Stack --region $region --query 'Stacks[0].StackStatus' --output text 2>&1)

if [[ $stack_status == "ROLLBACK_COMPLETE" ]]; then
    echo "Stack in ROLLBACK_COMPLETE status, deleting stack in region $region."
    aws cloudformation delete-stack --stack-name ValidatorEC2Stack --region $region
    aws cloudformation wait stack-delete-complete --stack-name ValidatorEC2Stack --region $region
elif [[ $stack_status == "CREATE_COMPLETE" ]]; then
    echo "Stack already exists and is complete in region $region."
    # Optionally, update the stack here if necessary
else
    echo "Creating stack for region $region."
    aws cloudformation create-stack --stack-name ValidatorEC2Stack --template-body file:///home/cloudshell-user/aws-validator.yaml --parameters \
        ParameterKey=UbuntuAmiId,ParameterValue=$(aws ec2 describe-images --region $region --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --output text) \
        ParameterKey=ValidatorPassword01,ParameterValue="$validator_password01" \
        ParameterKey=ValidatorPassword02,ParameterValue="$validator_password02" \
        ParameterKey=Domain01,ParameterValue="$domain01" \
        ParameterKey=Bootnodes,ParameterValue="$bootnodes" \
        --region $region --capabilities CAPABILITY_IAM
    aws cloudformation wait stack-create-complete --stack-name ValidatorEC2Stack --region $region
    echo "Stack creation completed in region $region."
fi

# Retrieve the Instance ID of the newly created or updated instance
instance_id=$(aws ec2 describe-instances --region $region --filters "Name=tag:Name,Values=validator-node" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[0].InstanceId' --output text)

# Check if Instance ID was retrieved successfully
if [ -n "$instance_id" ]; then
    echo "Instance ID: $instance_id"

    # Associate Elastic IP with the Instance
    aws ec2 associate-address --instance-id $instance_id --allocation-id $eip_allocation_id --region $region
    echo "Elastic IP associated with the instance successfully."
else
    echo "Failed to retrieve the Instance ID."
fi
