#!/bin/bash

set -o braceexpand

bastion_ip=$(terraform output -raw bastion_ip)

worker_no=$(terraform output -raw worker_no)

user="gcp"

ssh-keygen -R $bastion_ip

scp -i ./gcp ./gcp $user@$bastion_ip:/tmp/gcp

scp -i ./gcp ./docker.yaml $user@$bastion_ip:/tmp/docker.yaml

scp -i ./gcp ./locust_master.yaml $user@$bastion_ip:/tmp/locust_master.yaml

scp -i ./gcp ./locust_worker.yaml $user@$bastion_ip:/tmp/locust_worker.yaml

scp -i ./gcp ./nginx.conf $user@$bastion_ip:/tmp/nginx.conf

scp -i ./gcp ./loadbalancer.yaml $user@$bastion_ip:/tmp/loadbalancer.yaml

cat > inventory.ini <<EOF
[all:vars]
ansible_ssh_user=gcp
ansible_ssh_private_key_file=/tmp/gcp
[all]
10.0.0.10
$(for i in $(seq 0 $(($worker_no-1))); do echo 10.0.0.2$i; done)
[master]
10.0.0.10
[workers]
$(for i in $(seq 0 $(($worker_no-1))); do echo 10.0.0.2$i; done)
EOF

scp -i ./gcp ./inventory.ini $user@$bastion_ip:/tmp/inventory.ini

# export FRONTEND_ADDR=$(kubectl get svc frontend-external | awk '{print $4}' | tail -1)
export FRONTEND_ADDR="https://echo.free.beeceptor.com"

ssh -i ./gcp $user@$bastion_ip "sudo apt install -y software-properties-common;\
        sudo add-apt-repository --yes --update ppa:ansible/ansible;\
        sudo apt update;\
        sudo apt install -y ansible;\
    "

ssh -i ./gcp $user@$bastion_ip "ansible-playbook /tmp/loadbalancer.yaml"

ssh -i ./gcp $user@$bastion_ip "export ANSIBLE_HOST_KEY_CHECKING=False;\
    ansible-playbook -i /tmp/inventory.ini /tmp/docker.yaml"

ssh -i ./gcp $user@$bastion_ip "export ANSIBLE_HOST_KEY_CHECKING=False;\
    export FRONTEND_ADDR=$FRONTEND_ADDR;\
    export WORKER_NO=$worker_no;\
    export USER_NO=10;\
    ansible-playbook -i /tmp/inventory.ini /tmp/locust_master.yaml"

ssh -i ./gcp $user@$bastion_ip "export ANSIBLE_HOST_KEY_CHECKING=False;\
    ansible-playbook -i /tmp/inventory.ini /tmp/locust_worker.yaml"
