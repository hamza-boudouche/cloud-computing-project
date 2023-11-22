#!/bin/bash

terraform init

ssh-keygen -t rsa -b 4096 -f ./gcp -P "" <<< y

terraform apply -auto-approve

sleep 5
bash ./setup_bastion.sh
