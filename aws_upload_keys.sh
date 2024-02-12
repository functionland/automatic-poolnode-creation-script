#!/bin/bash
bucket_name="fula-validator" # Change this to your actual S3 bucket name
pem_key_path="s3://${bucket_name}/functionland.pem"
# Download key pair from S3
aws s3 cp "$pem_key_path" /home/cloudshell-user/functionland.pem

chmod 600 /home/cloudshell-user/functionland.pem
# Define your regions
regions=(
    us-east-2
    us-west-1
    af-south-1
    ap-east-1
    ap-south-1
    ap-south-2
    ap-northeast-2
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

# Function to process region
process_region() {
    local region=$1

    echo "Processing region: $region"
    # Retrieve the public IP of the instance
    instance_ip=$(aws ec2 describe-instances --region $region --query 'Reservations[].Instances[?State.Name==`running`].PublicIpAddress' --output text)

    if [ -n "$instance_ip" ]; then
        echo "Instance IP: $instance_ip"
        # Define and call zip_and_upload function via SSH
        ssh_command="source ~/.bashrc; function zip_and_upload() {
            local region_name=\$1
            local zip_filename=\"\${region_name}.zip\"
            zip -r \"\$zip_filename\" \"\$PASSWORD_FILE\" \"\$SECRET_DIR\"
            aws s3 cp \"\$zip_filename\" \"s3://fula-pools/\$zip_filename\"
            rm \"\$zip_filename\"
        }
        zip_and_upload pool-$region"
        # SSH Command (This part needs to be run from a system where SSH is possible)
        ssh -o StrictHostKeyChecking=no -i /home/cloudshell-user/functionland.pem ubuntu@$instance_ip "$ssh_command" &
    else
        echo "Failed to retrieve the instance IP address."
    fi
}

# Initial loop through each region
for region in "${regions[@]}"; do
    process_region "$region"
    sleep 10
done
# Write instance details to file
echo "Finished"