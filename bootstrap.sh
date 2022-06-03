#!/bin/bash -v

# retrieve dependancies
curl https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/packagelist_yum -o /tmp/packagelist_yum
curl https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/packagelist_pip3 -o /tmp/packagelist_pip3
curl https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/ansible_collections -o /tmp/ansible_collections
#activate repos
amazon-linux-extras install -y epel

yum makecache -y 
yum update -y *
yum install -y $(cat /tmp/packagelist_yum | egrep -v 'ˆ#')

pip3 install -U $(cat /tmp/packagelist_pip3 | egrep -v 'ˆ#')

ansible-galaxy collection install $(cat /tmp/ansible_collections | egrep -v 'ˆ#')

# update awscli to v2
yum remove awscli -y
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

export AWS_DEFAULT_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|jq -r .region`
echo "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}" | tee -a /etc/environment

# rundeck user
groupadd sudo 
useradd rundeck --create-home --shell /bin/zsh --groups sudo
mkdir -p /home/rundeck/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDl1TU2sZnbsZrS0K37kPaFG7Y8kbnhAu/ikDvBND2Omd3Pc0fNbhH5eh+EDrm4UnAb9IXr/osDuF5JR8ao/oNKPk44M3c1P2ZYBtDdKi9b+Mi+ktq1c0DU/IkKvdn1Cf8xYq3dq7yLUILDLHL+riPOlq+N0Qr5yzaOMN/Jl71zuxP62gNvitQCzOBwF9aMPwyUmErleTotlhQPwe3NKPtOSI9I3tpFJy0r3bD7VstW8E/RA407Bg23uh6buHCZOo6Yt4E5v2e1jl69JD1XaX/7fDBoSeqqJv9QRgv/TiSssGf8IkJTXFHLwAA4K64wqnmhYyJruRACu0omxa2aKQZkVptYA0/lr+Qu+mF8hvqmETKD9bO+p/3HfKeajdcBAJpe4UzGvSjXkGBo0Pn3z1i7K/j66nudk/kU8CxUFgaTVclv/OdrC7sqkGwUyZu2WlKuDR+ZVhdlROSBicDeD5qU/sL0Yt4npdarP1/HPlYC/1TuZY52xJ9T2Cm03NH8Me0= rundeck" | tee -a /home/rundeck/.ssh/authorized_keys
chown -R rundeck:  /home/rundeck/.ssh
echo "rundeck   ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers

# CodeDeploy Agent
curl https://aws-codedeploy-eu-west-1.s3.amazonaws.com/latest/install -o /tmp/install
chmod +x /tmp/install 
/tmp/install auto 
service codedeploy-agent start 

#retrieve scripts
for PIPELINENAME in GitScripts 
do 
    PIPELINEID=`aws codepipeline start-pipeline-execution --name $PIPELINENAME --region ${AWS_DEFAULT_REGION} | jq -r '.pipelineExecutionId' | sed 's/\\n//g' `
    PIPELINESTATUS='' 
    while [ 1 -eq 1 ] ; do 
        PIPELINESTATUS=`aws codepipeline get-pipeline-execution --pipeline-name $PIPELINENAME --pipeline-execution-id $PIPELINEID --region ${AWS_DEFAULT_REGION} | jq '.pipelineExecution.status' -r | sed 's/\\n//g' ` 
        if [ "$PIPELINESTATUS" = "Succeeded" ] ; then 
          echo " Success"
          break 
        elif [ "$PIPELINESTATUS" = "Failed" ] ; then 
          echo " Failed"
          break 
        else 
          printf "." 
          sleep 1 
        fi
    done 
done

# Install Datadog Agent
DATADOG_API_KEY=`aws ssm get-parameter --name "gandi_api_key" --with-decryption | jq -r .Parameter.Value`
/usr/local/bin/ansible-galaxy install Datadog.datadog
# /usr/local/bin/ansible-playbook /opt/scripts/ansible/datadog/install.yml
/usr/local/bin/ansible-playbook /opt/scripts/ansible/datadog/install_manual.yml -e datadog_api_key="${DATADOG_API_KEY}"

# CloudWatch Agent
/usr/local/bin/ansible-playbook /opt/scripts/ansible/amazon-cloudwatch-agent/install.yml

#launch cloud init scripts
/opt/scripts/AWS/cloud-init/common.sh

# Final Report
/usr/local/bin/ansible-playbook /opt/scripts/ansible/Common/cloud-init-report.yml