#!/bin/bash

# init variables
AWS_DEFAULT_REGION=

# determine default AWS region
echo "====== [ AWS : Determine default region ] ======"
# Get IMDSv2 token
token=$(curl -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" -s http://169.254.169.254/latest/api/token)
AWS_CURRENT_REGION=`curl -H "X-aws-ec2-metadata-token: $token" -s http://169.254.169.254/latest/dynamic/instance-identity/document|jq -r .region`
if [ "$AWS_CURRENT_REGION" != "" ]
then
  export AWS_DEFAULT_REGION=$AWS_CURRENT_REGION
else
  export AWS_DEFAULT_REGION=eu-west-1
fi
echo "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}" | sudo tee -a /etc/environment

# CodeDeploy Agent
echo "====== [ AWS : Install CodeDeploy Agent ] ======"
curl https://aws-codedeploy-eu-west-1.s3.amazonaws.com/latest/install -o /tmp/install
chmod +x /tmp/install 
sudo /tmp/install auto 
sudo service codedeploy-agent start 

# CloudWatch Agent
echo "====== [ AWS : Install Cloudwatch Agent ] ======"
ansible-playbook /opt/scripts/ansible/amazon-cloudwatch-agent/install.yml
