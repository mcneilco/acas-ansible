## Running a deployment

### Requirements

#### AWS credentials:
You must obtain AWS Cli credentials by going to [Company AWS Console > IAM > Users > {your username} > Create access key](https://console.aws.amazon.com/iam/home?#/users/BrianBolt?section=security_credentials)


Place the Access key ID and Secret access key in a file on your system called:
```~/.aws/credentials``` in the following format:

```
[company]
region=us-east-1
aws_access_key_id = {Access key ID}
aws_secret_access_key = {Secret access key}
```

#### Ansible Vault password
You must have a file `~/.company_vault.txt` with the vault password (same for each vault.yml file in this repo).  
The file is located in the [AWS > us-east-1 > System Manager > Parameter Store > company_vault.txt](https://console.aws.amazon.com/systems-manager/parameters/company_vault.txt/description?region=us-east-1)


#### Ansible dependencies

```
pip install ansible boto3 botocore dnspython
```

### Deployments
There is a simple wrapper script to do a full deploy.

```
sh deploy-stack.sh <name of environment>
```

#### Examples:

##### Deploy Stage (full deploy):

```bash
sh deploy-stack.sh stage
```

##### Deploy Stage - just cloudformation:

If you just edited the vars.yml file to change the list of whitelisted IP addresses you would just need to run the following to update the security groups.  This is relatively safe but it's recommended to do this on a Test system first:

```
ansible-playbook deploy-docker.yml -i "environments/stage" --tags "cloud-formation-deploy"
```

##### Creating a new stack:

First create a folder by copying prod:
```
INSTANCE_NAME=newname
cp -R environments/prod environments/$INSTANCE_NAME
```

Edit the var.yml file to match your instance:

* `env`
    * make the same as `$INSTANCE_NAME` above
* `machine_name`
    * set to `{{ stack_name }}` (prod is special in that it's the only one that isn't named `company-$INSTANCENAME`)
* `vpc_cidr`
    * If connecting to an LD instance, this is important to get from schrodinger as they reserver a specific range for VPC peering connections which are configured manually
* `livedesign_fqdn`, `livedesign_private_ip`, `schrodinger_peering_cidr`
    * This should all be gotten from schrodinger and are only required if hooking the instance up to live design
    * Required if using `ldap` authentication for `acas_authstrategy`
    * `livedesign_fqdn`
      * This is for providing links to users to reach the live design server (open In live design button)
      * `livedesign_private_ip`
        * Used for direct database access over peering connection for open in live design scripts
        * Used for direct ldap connection over peering connection
      * `schrodinger_peering_cidr`
        * Currently used just for recording purposes
        * This is stored with the cloud formation stack variables but is not currently used
* `pub_subnet_cidr`
    * We are reserving the first 16 addresses of the VPC CIDR range for the public subnet so we use the /28 range of the VPC CIDR
    * e.g. if `vpc_cidr` is `10.100.60.128/25` (10.100.60.128 - 10.100.60.255), then the `pub_subnet_cidr` should be `10.100.60.128/28` (10.100.60.128 - 10.100.60.143)
* `acas_private_ip`
    * AWS reservers the first 3 addreses of a VPC CIDR Range for internal usage, therfore we made the instance privat ip the 4th address in the `pub_subnet_cidr`
    * e.g. 10.100.60.128/25 - first address = 10.100.60.128 so + 4 = 10.100.60.132
* `acas_authstrategy`
    * Allowed values - `acas`, `ldap`
        * `acas`
            * Use ACAS internal authentication instead of reaching to Live Design LDAP
            * This can be useful if you want a stanalone instance of acas without having to connect it to Live Design.
        * `ldap`
            * This sets the appropriate flags in ACAS to reach out to Live Design's ldap system located on the Live Design server
* `run_backups`, `backups_retention`
    * For non-prod systems
        * `run_backups`: `false`
        * `backups_retention`: {must still be an interger but won't be used}
    * For prod system
        * `run_backups`: `true`
        * `backups_retention`: 7


## Backups

[See acas_custom wiki page](https://bitbucket.org/company/acas_custom/wiki/Disaster%20recovery)


### SSH to instance
Get the ssh key [AWS > us-east-1 > System Manager > Parameter Store > acas.pem](https://console.aws.amazon.com/systems-manager/parameters/ansible-testing.pem/description?region=us-east-1)

```
ssh -i "~/.ssh/acas.pem" centos@company-stage.onacaslims.com
```


### Ansible vault

Changing a password in a vault file:

> First remove the original password by opening the file and deleting the lines

Add a new password:
```
cd environments/stage/group_vars/all/
echo -n 'TheNewPassword' | ansible-vault encrypt_string --output vault.yml --stdin-name 'livedesign_db_password' >> vault.yml
```

Viewing a password:

Get the text from the vault file (spaces don't matter)

[Vault password stored here](https://console.aws.amazon.com/systems-manager/parameters/company_vault.txt/description?region=us-east-1)
```
chiphertext='          $ANSIBLE_VAULT;1.1;AES256
          11111111111111111111111111111111111111111111111111111111111111111111111111111111
          1111111111111111111111111111111111111111111111111a111111111111111111111111111111
          11111111111111111111111111111111111111111111111111111111111111111111111111111111
          1111111111111111111a111111111111111111111111111111111111111111111111111111111111
            11111111111111111111111111111111111111111111111111111111111111111111'
printf "%s\n" $chiphertext | ansible-vault decrypt /dev/stdin --output=/dev/stderr > /dev/null       
```


### Debugging
> This is helpsful when debugging why an ec2 instance may not respond to cloud formation after being created

```
sudo tail -f /var/log/cloud-init.log
sudo tail -f /var/log/cfn-init.log
```

### Other notes
* We are not doing the following because we found that 1024-65535 are required for [Ephemeral Ports](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html#nacl-ephemeral-ports)
    * We haven't sorted out locking down inbound ports 1024-65535. Something in this range is required for the CloudFormation user function to run, so we allow it in the template
    * For any system with real data, it is easy to manually lock this down after the CloudFomrmation stack creation process completes:
        * Navigate to your new stack [cloudformation](https://console.aws.amazon.com/cloudformation/home?region=us-east-1)
        * Click on the resources tab and scroll down to find the resource name "NetworkAcl"
        * Click on the link to the physical id. This will open then ACL configuration in a new tab
        * Select the Inbound Rules tab and then click "Edit Inbound Rules"
        * Delete rule 103 and save

#### Deploy Stack (before ansible)

```
aws cloudformation deploy \
    --profile company \
    --template-file ./ACAS-Template.yaml \
    --parameter-overrides \
        InstanceType=r3.large \
        KeyName=ansible-testing \
        ImageId=ami-9887c6e7 \
    --stack-name acas-stage
```


### Delete Stack
```
aws cloudformation delete-stack --profile company --stack-name acas-tmp
```
This currently deletes the data volume!

### Set and remove termination protection for prod or other critical stacks
```
aws cloudformation update-termination-protection --profile company --enable-termination-protection --stack-name acas-jam-tmp

aws cloudformation update-termination-protection --profile company --no-enable-termination-protection --stack-name acas-jam-tmp
```

