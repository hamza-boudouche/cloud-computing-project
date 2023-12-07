#!/bin/bash

cat > inventory.ini <<EOF
[all:vars]
ansible_ssh_user=gcp
ansible_ssh_private_key_file=./gcp
[all]
$(terraform output -raw locust_ip)
EOF

export FRONTEND_ADDR="http://$(kubectl get svc frontend-external | awk '{print $4}' | tail -1)"

export USER_NO=200

export ANSIBLE_HOST_KEY_CHECKING=False

ansible-playbook -i ./inventory.ini ./docker.yaml

ansible-playbook -i ./inventory.ini ./loadgen.yaml
