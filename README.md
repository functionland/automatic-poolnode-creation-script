# automatic-poolnode-creation-script
This script is optimized to create a pool node on ubuntu and it also runs sugarfunge-node, sugarfunge-api and go-fula to be able to manage the pool automatically..

### Run

You can run it on an aws EC2 instance or Google cloud instance with the below command. However on aws instance you can omit the region name as it fetches it based on the region that the instance is created.

```
bash install.sh {{Seed of an account with enough Sugar}} {{region name without space or special character}}
```