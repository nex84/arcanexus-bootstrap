#!/bin/bash

# init variables
AWS_DEFAULT_REGION=

# determine default AWS region
AWS_CURRENT_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|jq -r .region`
if [ "$AWS_CURRENT_REGION" != "" ]
then
  export AWS_DEFAULT_REGION=$AWS_CURRENT_REGION
else
  export AWS_DEFAULT_REGION=eu-west-1
fi
echo "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}" | sudo tee -a /etc/environment

# CodeDeploy Agent
curl https://aws-codedeploy-eu-west-1.s3.amazonaws.com/latest/install -o /tmp/install
chmod +x /tmp/install 
sudo /tmp/install auto 
sudo service codedeploy-agent start 

# CloudWatch Agent
ansible-playbook /opt/scripts/ansible/amazon-cloudwatch-agent/install.yml
