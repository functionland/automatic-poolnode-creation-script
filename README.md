# automatic-poolnode-creation-script

## pool_creation.sh
This script is optimized to create a pool node on ubuntu. It creates the pool if it is not created already using a new node (not the provided seed) and it also runs sugarfunge-node, sugarfunge-api and go-fula to be able to manage the pool automatically.

- It funds a new random seed account from the provided seed
- It uses the new account to create a pool with the region specified and the pool name is similar to region
- It runs node, api and go-fula to automatically manage the pool requests

### Run

You can run it on an aws EC2 instance or Google cloud instance with the below command. However on aws instance you can omit the region name as it fetches it based on the region that the instance is created.

```
bash install.sh {{Seed of an account with enough Gas}} {{region name without space or special character}}
```

## validator_node.sh
### Functionyard Validator Node Setup Script

This README provides detailed instructions for setting up a validator node for the Functionyard network using the provided setup script. The script automates the environment preparation, software installation, Docker configuration, and service management required to run a Functionyard validator node securely and efficiently.

### Overview

The Functionyard validator setup script is a Bash script intended for Ubuntu servers. It aims to simplify the setup process for validators participating in the Functionyard network by automating routine tasks and ensuring best practices in security and configuration.

### Prerequisites

- A machine running Ubuntu (18.04 or later is recommended).
- Root or sudo access on the machine.
- An active internet connection for downloading necessary packages and Docker images.

### Usage

To use the script, you must provide a password for the node's keystore and a unique identifier for the validator.
Also you need to store a file named keys01.info or keys02.info on your home folder (/home/user/) with the below content:

```bash
Aura account1
Secret phrase:       xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx
  Network ID:        substrate
  Secret seed:       0xb0000000
  Public key (hex):  0x18000000
  Account ID:        0x18000000
  Public key (SS58): 5Cxxxxxxx
  SS58 Address:      5Cxxxxxxx
  
peerID: 12D3Kooxxxxxxx
nodeKey: 1xxxxxxxxxxxx
```

Note that the above file will be automatically removed by script at the end of installation. Then you can run the command with required parameters

### Parameters

--password: [default=''] A strong password for securing the node's keystore. If not set an 25-character password will be automatically generated. ALWAYS put hte password in single quote.

--validator: [default=01] A unique number or identifier for the validator. This helps in naming and managing multiple validators on the same host. default to 01

--domain: [default=''] This is optional and if set, the script will set up the domain to be used to connect to the node. the DNS should be already set and pointing to the server. If not set the node can be used locally using 127.0.0.1 only

--bootnodes: [default=''] You can use this parameter to provide bootstrap nodes to this node to connect to initially.

--user: [default=ubuntu] You should set the user that you are logged in as the system uses home folder for storing data. e.g /home/user

Example
```bash
./validator_node.sh --user=ubuntu --password='VeryStrongPassword$!' --validator=01 --domain=test.fx.land --bootnodes=/ip4/127.0.0.1/tcp/30334/p2p/12D3KooWBeXV65svCyknCvG1yLxXVFwRxzBLqvBJnUF6W84BLugv
```

### Features

- Automatic Installation: Installs Docker, Nginx, Rust, and other dependencies without manual intervention.
- Docker Management: Pulls the latest Sugarfunge Node image from the Docker Hub and configures it to run as a persistent service.
- Secure WebSocket (WSS): Sets up Nginx and Let's Encrypt to create a secure WebSocket endpoint, enabling safe validator communications.
- Key Management: Reads and configures validator keys from a specified file, establishing a unique identity for each validator node.
- System Service: Registers the validator node as a system service, ensuring it automatically starts on boot and restarts after failures.
- Logging: Directs detailed logs to specified files, aiding in monitoring and troubleshooting.

### File Structure
- validator_setup.sh: The primary script file.
- keys01.info: An example key file. Each validator should have a unique key file, named corresponding to the validator number (e.g., - keys02.info for validator 02).
- Security Considerations
- Key Security: Ensure the key and password files are stored securely and accessible only to authorized personnel.
- Script Review: Understand the script's actions before execution, particularly in production environments.
- System Updates: Keep your system and Docker images updated to receive the latest security patches and feature improvements.


## nonvalidator_node.sh
### Functionyard None-Validator Node Setup Script

This README provides detailed instructions for setting up a none-validator node for the Functionyard network using the provided setup script. The script automates the environment preparation, software installation, Docker configuration, and service management required to run a Functionyard validator node securely and efficiently.

### Overview

The Functionyard validator setup script is a Bash script intended for Ubuntu servers. It aims to simplify the setup process for validators participating in the Functionyard network by automating routine tasks and ensuring best practices in security and configuration.

### Prerequisites

- A machine running Ubuntu (18.04 or later is recommended).
- Root or sudo access on the machine.
- An active internet connection for downloading necessary packages and Docker images.

### Usage

To use the script, you must provide a password for the node's keystore and a unique identifier for the validator.
Also you need to store a file named keys03.info or keys04.info on your home folder (/home/user/) with the below content:

```bash
Aura account1
Secret phrase:       xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx
  Network ID:        substrate
  Secret seed:       0xb0000000
  Public key (hex):  0x18000000
  Account ID:        0x18000000
  Public key (SS58): 5Cxxxxxxx
  SS58 Address:      5Cxxxxxxx
```

Note that the above file will be automatically removed by script at the end of installation. Then you can run the command with required parameters

### Parameters

--password: [default=''] A strong password for securing the node's keystore. If not set an 25-character password will be automatically generated. ALWAYS put hte password in single quote.

--node: [default=03] A unique number or identifier for the node. This helps in naming and managing multiple nodes on the same host. default to 03

--domain: [default=''] This is optional and if set, the script will set up the domain to be used to connect to the node api. the DNS should be already set and pointing to the server. If not set the node can be used locally using 127.0.0.1 only

--bootnodes: [default=''] You can use this parameter to provide bootstrap nodes to this node to connect to initially.

--user: [default=ubuntu] You should set the user that you are logged in as the system uses home folder for storing data. e.g /home/user

--pool: [default=''] this is the pool that go-fula should see as joined

--release default='']: if not set then it runs node and api in debug mode which means running directly from compiled /target/debug using cargo instead of docker

Example
```bash
./nonvalidator_node.sh --release --user=ubuntu --password='VeryStrongPassword$!' --node=03 --domain=api.test.fx.land --bootnodes=/ip4/127.0.0.1/tcp/30334/p2p/12D3KooWBeXV65svCyknCvG1yLxXVFwRxzBLqvBJnUF6W84BLugv --pool=1
```

### Features

- Automatic Installation: Installs Docker, Nginx, Rust, and other dependencies without manual intervention.
- Docker Management: Pulls the latest Sugarfunge Node image from the Docker Hub and configures it to run as a persistent service.
- Secure WebSocket (WSS): Sets up Nginx and Let's Encrypt to create a secure WebSocket endpoint, enabling safe validator communications.
- Key Management: Reads and configures validator keys from a specified file, establishing a unique identity for each validator node.
- System Service: Registers the validator node as a system service, ensuring it automatically starts on boot and restarts after failures.
- Logging: Directs detailed logs to specified files, aiding in monitoring and troubleshooting.

### File Structure
- nonvalidator_setup.sh: The primary script file.
- keys03.info: An example key file. Each node should have a unique key file, named corresponding to the validator number (e.g., - keys04.info for node 04).
- Security Considerations
- Key Security: Ensure the key and password files are stored securely and accessible only to authorized personnel.
- Script Review: Understand the script's actions before execution, particularly in production environments.
- System Updates: Keep your system and Docker images updated to receive the latest security patches and feature improvements.

## Running an AWS Instance

Run the below command in aws, replacing the ap-south-2 with the region you want:
```
REGION=ap-south-2; aws ec2 import-key-pair --key-name functionland --public-key-material file:///home/cloudshell-user/functionland-public.b64 --region $REGION; aws cloudformation create-stack --stack-name FulaPoolStack --template-body file:///home/cloudshell-user/aws-pools.yaml --parameters ParameterKey=UbuntuAmiId,ParameterValue=$(aws ec2 describe-images --region $REGION --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --output text) --region $REGION;
```
Where `functionland-public.b64` is the file for which the content is the base64 encoded version of the content of your private key to access the instance.

You can check the logs in CLoud Formation. Then get the public ip by running:
```
aws ec2 describe-instances --region $REGION --query 'Reservations[].Instances[].PublicIpAddress' --output text
```

ssh into it and run the commands needed:
```
ssh -i functionland.pem ubuntu@ip-address
```

for example clone the repo:
```
git clone https://github.com/functionland/automatic-poolnode-creation-script
bash ~/automatic-poolnode-creation-script/pool_creation.sh 0x1222222
```

## AWS Setup and install

The easiest way is to use the aws scripts which handles everything from instance setup to install. 

### Validator Nodes

For validator nodes, you can open an aws terminal and run the below and it installs 2 validator nodes on the same instance. IT downloads keys01.info, keys02.info and other required info from S3 and downloads the latest yaml for cloudformation from GitHub.
```
git clone https://github.com/functionland/automatic-poolnode-creation-script && cd automatic-poolnode-creation-script && git pull

bash  ./aws_validator_creation.sh --eip_allocation_id='eipalloc-xxxxxxxxxxx (this group contains the public IP of validator1)' --validator_password01='validator1 password' --validator_password02='validator2 password'
```

### Non-Validator Node

For non-validator node, you can run the below command and it installs one non-validator node on an instance and uploads the keys to the S3
```
git clone https://github.com/functionland/automatic-poolnode-creation-script && cd automatic-poolnode-creation-script && git pull

bash ./aws_nonvalidator_creation.sh --eip_allocation_id='eipalloc-xxxxxxxxxxx (this group contains the public IP of nonvalidator)' --password='nonvalidator password'
```

### Pools

For creating pools for the regions where there is an AWS server (it has a list in the script that iterates through it), you cna run the below command:

```
git clone https://github.com/functionland/automatic-poolnode-creation-script && cd automatic-poolnode-creation-script && git pull

bash ./aws_pool_stack_creation.sh 0x1222222(seed of validator node)
```

Then after all pools are created which takes some time, and to upload the created keys and passwords, you can run:
```
git clone https://github.com/functionland/automatic-poolnode-creation-script && cd automatic-poolnode-creation-script && git pull

bash ./aws_upload_keys.sh
```

## Troubleshooting
- Permission Issues: Run the script with sufficient privileges (sudo may be necessary).
- Docker Problems: Verify Docker's installation and operational status (systemctl status docker).
- Service Failures: For services that fail to start, refer to the designated log files (e.g., /var/log/Node01.log) for specific error messages.

## Contributing
Your contributions are welcome. Please ensure any modifications are thoroughly tested and documented.

## License
This script is provided under the MIT License.

## Support and Contact
For support, questions, or more information about the Functionyard network, please visit Functionland Official Website or contact Functionland Support.