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
  
Grandpa account1:
Secret phrase:       xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx
  Network ID:        substrate
  Secret seed:       0xb0000000
  Public key (hex):  0xa0000000
  Account ID:        0xa0000000
  Public key (SS58): 5Fxxxxxxxx
  SS58 Address:      5Fxxxxxxxx
  
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