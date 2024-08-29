#!/bin/bash

# init variables
PLATFORM=
OS=
PKG_MANAGER=

# retrieve dependancies
echo "====== [ BASE : Retrieve dependancies ] ======"
# packages
curl -s https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/packagelist_yum -o /tmp/packagelist_yum
curl -s https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/packagelist_apt -o /tmp/packagelist_apt
curl -s https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/packagelist_pip3 -o /tmp/packagelist_pip3
curl -s https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/ansible_collections -o /tmp/ansible_collections
# platform dependant code
curl -s https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/bootstrap_aws.sh -o /tmp/bootstrap_aws.sh ; chmod +x /tmp/bootstrap_aws.sh

# detect running platform
echo "====== [ BASE : Detect running platform ] ======"
token=$(curl -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" -s http://169.254.169.254/latest/api/token)
if curl -s -m 2 -H "X-aws-ec2-metadata-token: $token" 2 http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1; then
  PLATFORM="aws"
elif curl -s -m 2 http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01 >/dev/null 2>&1; then
  PLATFORM="azure"
elif curl -s -m 2 http://metadata.google.internal/computeMetadata/v1/ >/dev/null 2>&1; then
  PLATFORM="gcp"
else
  PLATFORM="other"
fi
echo "PLATFORM=\"$PLATFORM\"" | sudo tee -a /etc/environment
export PLATFORM

# detect packages manager and install packages 
echo "====== [ BASE : Detect package manager ] ======"
OS=`grep -e '^ID=' /etc/os-release | cut -d= -f2`
echo "OS=\"$OS\"" | sudo tee -a /etc/environment
export OS
case $OS in
  
  amzn)
    if [ -n "$(command -v yum)" ]
    then
      export PKG_MANAGER="yum"
      echo 'PKG_MANAGER="yum"' | sudo tee -a /etc/environment
    elif [ -n "$(command -v dnf)" ]
    then
      export PKG_MANAGER="dnf"
      echo 'PKG_MANAGER="dnf"' | sudo tee -a /etc/environment
    fi
    
    #activate amazon repos
    echo "====== [ BASE : Install base packages ] ======"
    sudo amazon-linux-extras install -y epel python3.8
    sudo ${PKG_MANAGER} makecache -y 
    sudo ${PKG_MANAGER} update -y
    sudo ${PKG_MANAGER} install -y $(cat /tmp/packagelist_yum | egrep -v '^#')
    sudo ${PKG_MANAGER} remove awscli -y
    sudo pip3.8 install -U $(cat /tmp/packagelist_pip3 | egrep -v '^#')
    ;;
  
  debian|ubuntu)
    export PKG_MANAGER="apt"
    echo 'PKG_MANAGER="apt"' | sudo tee -a /etc/environment
    
    echo "====== [ BASE : Install base packages ] ======"
    # add kubernetes
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly
    # add ansible
    sudo add-apt-repository --yes --update ppa:ansible/ansible
    # add helm
    curl https://baltocdn.com/helm/signing.asc | gpg --batch --yes --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    # add terraform
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

    sudo apt update
    sudo apt install -y $(cat /tmp/packagelist_apt | egrep -v '^#')
    sudo apt dist-upgrade -y
    sudo apt autoremove -y
    sudo apt autoclean -y
    sudo pip3 install -U $(cat /tmp/packagelist_pip3 | egrep -v '^#')
    ;;
esac
ansible-galaxy collection install $(cat /tmp/ansible_collections | egrep -v '^#')


# update awscli to v2
echo "====== [ BASE : Update AWS CLI ] ======"
AWSCLI_VERSION=`aws --version 2> /dev/null | cut -d ' ' -f1 | cut -d '/' -f2 | cut -d '.' -f1`
curl "https://awscli.amazonaws.com/awscli-exe-linux-`uname -m`.zip" -o "awscliv2.zip"
unzip awscliv2.zip
if [ "$AWSCLI_VERSION" == "2"  ]; then
  sudo ./aws/install -u #-U
else
  sudo ./aws/install
fi
rm -rf awscliv2.zip aws

echo "====== [ BASE : install Bitwarden CLI ] ======"
bitwarden_cli_url=$(curl -s https://api.github.com/repos/bitwarden/sdk/releases/latest | grep "bws-x86_64-unknown-linux-gnu-" | cut -d '"' -f 4 | grep https)
curl -Ls -o bitwarden-linux-amd64.zip "$bitwarden_cli_url"
sudo unzip -o bitwarden-linux-amd64.zip -d /usr/bin && rm -f bitwarden-linux-amd64.zip
sudo chmod 755 /usr/bin/bws

# Workaround : oeuf/poule
echo "====== [ BASE : Workaround : get scripts ] ======"
GIT_PAT_TOKEN=`aws ssm get-parameter --region eu-west-1 --name "git_pat_token" --with-decryption | jq -r .Parameter.Value`
sudo mkdir -p /opt/
cd /opt
if [ -e "/opt/scripts" ] ; then sudo rm -rf /opt/scripts ; fi
sudo git clone https://nex84:${GIT_PAT_TOKEN}@github.com/Arcanexus/scripts.git

# nexus user
echo "====== [ BASE : Create user : nexus ] ======"
sudo ansible-playbook /opt/scripts/ansible/Common/init_linux_user.yaml -e user_name=nexus -e user_password=`aws ssm get-parameter --name "default_password" --with-decryption | jq -r .Parameter.Value`  -e user_sudogroup=sudo -e user_nopasswd=false
# rundeck user
echo "====== [ BASE : Create user : rundeck ] ======"
sudo ansible-playbook /opt/scripts/ansible/Common/init_linux_user.yaml -e user_name=rundeck -e user_password=`aws ssm get-parameter --name "default_password" --with-decryption | jq -r .Parameter.Value`  -e user_sudogroup=sudo -e user_nopasswd=true

#retrieve scripts
echo "====== [ BASE : Deploy scripts ] ======"
GIT_PAT_TOKEN=`aws ssm get-parameter --name "git_pat_token" --with-decryption | jq -r .Parameter.Value`
REPO=Arcanexus/scripts
if [ "$PLATFORM" = "aws" ]; then
  WORKFLOW_NAME=deployToEC2.yml
else
  WORKFLOW_NAME=deployToOnPrem.yml
fi

# Trigger the workflow
execute=$(curl -s -X POST \
  -H "Authorization: token $GIT_PAT_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW_NAME/dispatches" \
  -d '{"ref":"main"}' | jq -r '.id')
sleep 5
run_id=$(curl -s -H "Authorization: Bearer $GIT_PAT_TOKEN" -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW_NAME/runs?event=workflow_dispatch" | jq -r '.workflow_runs[0].id')
run_url=$(curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW_NAME/runs?event=workflow_dispatch" | jq -r '.workflow_runs[0].html_url')
echo "Workflow triggered with run ID: $run_id [ $run_url ]"

# Wait for the workflow to finish
while true; do
  status=$(curl -s -H "Authorization: token $GIT_PAT_TOKEN" -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$REPO/actions/runs/$run_id" | jq -r '.status')

  if [ "$status" == "completed" ]; then
    conclusion=$(curl -s -H "Authorization: token $GIT_PAT_TOKEN" -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$REPO/actions/runs/$run_id" | jq -r '.conclusion')
    echo "Workflow finished with conclusion: $conclusion"
    break
  elif [ "$status" == "in_progress" ] || [ "$status" == "queued" ]; then
    echo "Workflow is still in progress..."
  else
    echo "Unexpected status: $status"
    break
  fi

  sleep 10  # Wait for 10 seconds before checking again
done

#retrieve docker-stacks
echo "====== [ BASE : Deploy docker-stacks ] ======"
REPO=Arcanexus/docker-stacks
if [ "$PLATFORM" = "aws" ]; then
  WORKFLOW_NAME=deployToEC2.yml
else
  WORKFLOW_NAME=deployToOnPrem.yml
fi

# Trigger the workflow
execute=$(curl -s -X POST \
  -H "Authorization: token $GIT_PAT_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW_NAME/dispatches" \
  -d '{"ref":"main"}' | jq -r '.id')
sleep 5
run_id=$(curl -s -H "Authorization: Bearer $GIT_PAT_TOKEN" -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW_NAME/runs?event=workflow_dispatch" | jq -r '.workflow_runs[0].id')
run_url=$(curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW_NAME/runs?event=workflow_dispatch" | jq -r '.workflow_runs[0].html_url')
echo "Workflow triggered with run ID: $run_id [ $run_url ]"

# Wait for the workflow to finish
while true; do
  status=$(curl -s -H "Authorization: token $GIT_PAT_TOKEN" -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$REPO/actions/runs/$run_id" | jq -r '.status')

  if [ "$status" == "completed" ]; then
    conclusion=$(curl -s -H "Authorization: token $GIT_PAT_TOKEN" -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$REPO/actions/runs/$run_id" | jq -r '.conclusion')
    echo "Workflow finished with conclusion: $conclusion"
    break
  elif [ "$status" == "in_progress" ] || [ "$status" == "queued" ]; then
    echo "Workflow is still in progress..."
  else
    echo "Unexpected status: $status"
    break
  fi

  sleep 10  # Wait for 10 seconds before checking again
done

echo "====== [ BASE : Create logs dir ] ======"
sudo mkdir -m 777 -p /var/log/arcanexus/

# launch platform specific steps
echo "====== [ BASE : Launch ${PLATFORM} specific script ] ======"
/tmp/bootstrap_${PLATFORM}.sh

# Install Datadog Agent
# echo "====== [ BASE : Install Datadog Agent ] ======"
# DATADOG_API_KEY=`aws ssm get-parameter --name "datadog_api_key" --with-decryption | jq -r .Parameter.Value`
# ansible-galaxy install Datadog.datadog
# # ansible-playbook /opt/scripts/ansible/datadog/install.yml
# ansible-playbook /opt/scripts/ansible/datadog/install_manual.yml -e datadog_api_key="${DATADOG_API_KEY}"

# Install Prometheus Node-exporter
# echo "====== [ BASE : Install Prometheus node-exporter ] ======"
# ansible-playbook /opt/scripts/ansible/prometheus-node-exporter/install.yml

# Install Promtail
echo "====== [ BASE : Install Promtail ] ======"
ansible-playbook /opt/scripts/ansible/promtail/install-local.yml

#launch cloud init scripts
echo "====== [ BASE : Launch Common script ] ======"
/opt/scripts/$(echo "$PLATFORM" | tr '[:lower:]' '[:upper:]')/cloud-init/common.sh

# Final Report
if [ "$PLATFORM" == "aws" ]; then
  echo "====== [ BASE : Send report ] ======"
  ansible-playbook /opt/scripts/ansible/Common/cloud-init-report.yml
fi

echo "====== [ BASE : END OF CLOUD-INIT ] ======"
echo "Rebooting to apply the latest updates"
sudo shutdown -r now