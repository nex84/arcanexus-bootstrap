#!/bin/bash -v

# retrieve dependancies
curl https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/packagelist_yum -o /tmp/packagelist_yum
curl https://raw.githubusercontent.com/nex84/arcanexus-bootstrap/master/packagelist_pip3 -o /tmp/packagelist_pip3
#activate repos
amazon-linux-extras install -y epel

yum makecache -y 
yum update -y *
yum install -y $(cat /tmp/packagelist_yum)

pip3 install -U $(cat /tmp/packagelist_pip3)

# CodeDeploy Agent
curl https://aws-codedeploy-eu-west-1.s3.amazonaws.com/latest/install -o /tmp/install
chmod +x /tmp/install 
/tmp/install auto 
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
/usr/local/bin/ansible-galaxy role install  Datadog.datadog
# /usr/local/bin/ansible-playbook /opt/scripts/ansible/datadog/install.yml
DD_AGENT_MAJOR_VERSION=7 DD_SITE="datadoghq.com" bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
# Activate processes monitoring
echo <<EOF >> /etc/datadog-agent/datadog.yaml
process_config:
  enabled: 'true'
EOF
# Activate network monitoring
sudo -u dd-agent echo <<EOF >> /etc/datadog-agent/system-probe.yaml
network_config:   # use system_probe_config for Agent's older than 7.24.1
  ## @param enabled - boolean - optional - default: false
  ## Set to true to enable Network Performance Monitoring.
  #
  enabled: true
EOF
systemctl restart datadog-agent

#launch cloud init scripts
/opt/scripts/AWS/cloud-init/common.sh