#!/bin/bash -v

# retrieve dependancies
curl https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/packagelist_yum -o ./packagelist_yum
curl https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/packagelist_pip3 -o ./packagelist_pip3
curl https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/packagelist_pip -o ./packagelist_pip
#activate repos
amazon-linux-extras install -y epel lamp-mariadb10.2-php7.2 php7.2 

yum makecache -y 
yum update -y *
yum install -y $(cat ./packagelist_yum)

pip3 install -U $(cat ./packagelist_pip3)
pip install -U $(cat ./packagelist_pip)

# CodeDeploy Agent
wget https://aws-codedeploy-eu-west-1.s3.amazonaws.com/latest/install 
chmod +x install 
./install auto 
service codedeploy-agent start 

# CloudWatch Agent
#TODO

#retrieve scripts
for PIPELINENAME in GitScripts 
do 
    PIPELINEID=`aws codepipeline start-pipeline-execution --name $PIPELINENAME --region eu-west-1 | jq -r '.pipelineExecutionId' | sed 's/\\n//g' `
    PIPELINESTATUS='' 
    while [ 1 -eq 1 ] ; do 
        PIPELINESTATUS=`aws codepipeline get-pipeline-execution --pipeline-name $PIPELINENAME --pipeline-execution-id $PIPELINEID --region eu-west-1 | jq '.pipelineExecution.status' -r | sed 's/\\n//g' ` 
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
/usr/bin/ansible-galaxy install Datadog.datadog
/usr/bin/ansible-playbook /opt/scripts/ansible/datadog/install.yml

#launch cloud init scripts
/opt/scripts/AWS/cloud-init/common.sh