#create SSH keys for ansible
mkdir ssh_keys

SSH_KEY_PATH="./ssh_keys/ansible"

ssh-keygen -t ed25519 -f $SSH_KEY_PATH -C ansible -P "" <<< y

#init and apply terraform config

TERRAFORM_DIR="terraform"

(cd "$TERRAFORM_DIR" && terraform init)

(cd "$TERRAFORM_DIR" && terraform apply -auto-approve)

sleep 5 

#Get the machines IP
masters_ip=$(cd "$TERRAFORM_DIR" && terraform output -raw masters_ip)
workers_ip=$(cd "$TERRAFORM_DIR" && terraform output -raw workers_ip)

IFS=',' read -a masters_ip_arr <<< "$masters_ip"
IFS=',' read -a workers_ip_arr <<< "$workers_ip"
#ansible
CONFIG_PATH="./ansible/ansible.cfg"
INVENTORY_PATH="./ansible/inventory.ini"

#create cfg
echo "[defaults]
inventory = $INVENTORY_PATH
private_key_file = ."$SSH_KEY_PATH"
remote_user = ansible
host_key_checking = False" > $CONFIG_PATH

#create inventory

echo "${masters_ip_arr[0]}"
echo "[masters]
[first_master]
${masters_ip_arr[0]}
[joined_masters]
$(for add in "${masters_ip_arr[@]:1}"; do echo "$add"; done)
[nodes]
$(for add in "${workers_ip_arr[@]}"; do echo "$add"; done)
[masters:children]
first_master
joined_masters" > $INVENTORY_PATH


#execute playbook

(cd ansible && ansible-playbook -i inventory.ini playbook.yaml)


