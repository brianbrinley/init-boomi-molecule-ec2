# Introduction 
This script is used to initilize the first node for a Boomi Molecule within AWS. EBS must be attached to the EC2 but does not need to be mounted. Additional, the script will mount the EFS required.

# Getting Started
Add the script to your EC2 instance. Modify the values under the properties function. 

Then make the file executable and execute it.

```
chmod +x ./init-molecule-ec2.sh
./init-molecule-ec2.sh
```


# Insired from 

[Boomi CICD](https://github.com/OfficialBoomi/boomicicd-cli)
