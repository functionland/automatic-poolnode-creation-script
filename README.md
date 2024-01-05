# automatic-poolnode-creation-script
This script is optimized to create a pool node on ubuntu. It creates the pool if it is not created already using a new node (not the provided seed) and it also runs sugarfunge-node, sugarfunge-api and go-fula to be able to manage the pool automatically.

- It funds a new random seed account from the provided seed
- It uses the new account to create a pool with the region specified and the pool name is similar to region
- It runs node, api and go-fula to automatically manage the pool requests

### Run

You can run it on an aws EC2 instance or Google cloud instance with the below command. However on aws instance you can omit the region name as it fetches it based on the region that the instance is created.

```
bash install.sh {{Seed of an account with enough Sugar}} {{region name without space or special character}}
```