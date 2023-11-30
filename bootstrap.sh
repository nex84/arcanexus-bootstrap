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
if curl -s -m 2 http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1; then
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
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
    sudo apt update
    sudo apt install -y $(cat /tmp/packagelist_apt | egrep -v '^#')
    sudo apt dist-upgrade -y
    sudo apt autoremove -y
    sudo apt autoclean -y
    sudo pip3 install -U $(cat /tmp/packagelist_pip3 | egrep -v '^#')
    ;;

esac

# install Ansible collections
# echo "====== [ BASE : Install Ansible collections ] ======"
# sudo ansible-galaxy collection install $(cat /tmp/ansible_collections | egrep -v '^#')

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

# Workaround : oeuf/poule
echo "====== [ BASE : Workaround : get scripts ] ======"
GIT_PAT_TOKEN=`aws ssm get-parameter --name "git_pat_token" --with-decryption | jq -r .Parameter.Value`
sudo mkdir -p /opt/
cd /opt
sudo git clone https://nex84:${GIT_PAT_TOKEN}@github.com/nex84/scripts.git

# nexus user
echo "====== [ BASE : Create user : nexus ] ======"
sudo ansible-playbook /opt/scripts/ansible/Common/init_linux_user.yaml -e user_name=nexus -e user_password=`aws ssm get-parameter --name "default_password" --with-decryption | jq -r .Parameter.Value`  -e user_sudogroup=sudo -e user_nopasswd=false
# rundeck user
echo "====== [ BASE : Create user : rundeck ] ======"
sudo ansible-playbook /opt/scripts/ansible/Common/init_linux_user.yaml -e user_name=rundeck -e user_password=`aws ssm get-parameter --name "default_password" --with-decryption | jq -r .Parameter.Value`  -e user_sudogroup=sudo -e user_nopasswd=true

#retrieve scripts
echo "====== [ BASE : Deploy scripts ] ======"
GIT_PAT_TOKEN=`aws ssm get-parameter --name "git_pat_token" --with-decryption | jq -r .Parameter.Value`
curl -X POST \
  -H "Authorization: token ${GIT_PAT_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/nex84/scripts/actions/workflows/deployToEC2.yml/dispatches \
  -d '{"ref":"master"}'
echo "Waiting 2m..."
sleep 2m

# launch platform specific steps
echo "====== [ BASE : Launch ${PLATFORM} specific script ] ======"
/tmp/bootstrap_${PLATFORM}.sh

# Install Datadog Agent
echo "====== [ BASE : Install Datadog Agent ] ======"
DATADOG_API_KEY=`aws ssm get-parameter --name "datadog_api_key" --with-decryption | jq -r .Parameter.Value`
ansible-galaxy install Datadog.datadog
# ansible-playbook /opt/scripts/ansible/datadog/install.yml
ansible-playbook /opt/scripts/ansible/datadog/install_manual.yml -e datadog_api_key="${DATADOG_API_KEY}"

# Install Prometheus Node-exporter
echo "====== [ BASE : Install Prometheus node-exporter ] ======"
ansible-playbook /opt/scripts/ansible/prometheus-node-exporter/install.yml

#launch cloud init scripts
echo "====== [ BASE : Launch Common script ] ======"
/opt/scripts/$(echo "$PLATFORM" | tr '[:lower:]' '[:upper:]')/cloud-init/common.sh

# Final Report
echo "====== [ BASE : Send report ] ======"
ansible-playbook /opt/scripts/ansible/Common/cloud-init-report.yml