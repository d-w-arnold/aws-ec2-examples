#!/bin/bash

# Canonical, Ubuntu, 22.04 LTS, amd64 jammy image

echo "## EC2 User Data starting"

CDK_STACK_NAME="CdkProxyServerStack" # The CDK stack name, used to get CDK stack (CloudFormation) outputs

PROJECT_NAME_COMP_OUTPUT_KEY="CdkproxyserverCfnOutput" # The CloudFormation output key - The project name and component
ALLOC_ID_OUTPUT_KEY="CdkproxyserverAllocationIdCfnOutput" # The CloudFormation output key - The AllocationId of the Elastic IP
PARAMETER_NAME_OUTPUT_KEY="Cdkproxyserverpublicipv4parameternameCfnOutput" # The CloudFormation output key - The SSM parameter name to store the public (IPv4) address of the EC2 instance
VPC_NAME_OUTPUT_KEY="CdkproxyservervpcnameCfnOutput" # The CloudFormation output key - The VPC name for use in the EC2 instance name

echo "## Update the apt package index and install packages"
apt-get update -y
apt-get install -y jq tinyproxy unzip

echo "## Install AWS CLI tools"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
aws --version

echo "## Get AWS region"
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 3600")
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
echo "## AWS region: ${REGION}"

echo "## Make sure the stack is in a finished state, ensuring CloudFormation output keys are available"
DATA_STATE="unknown"
DATA_STATE_QUERY="Stacks[0].StackStatus"
SUB="COMPLETE"
COUNT=0
until [[ "${DATA_STATE}" == *"${SUB}"* || ${COUNT} == 100 ]]; do
  DATA_STATE=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${DATA_STATE_QUERY}")
  echo "## ${COUNT} ${DATA_STATE}"
  ((COUNT = COUNT + 1))
  sleep 5
done

# -----

echo "## Get the project name and component"
PROJECT_NAME_COMP_QUERY="Stacks[0].Outputs[?OutputKey=='${PROJECT_NAME_COMP_OUTPUT_KEY}'].OutputValue"
PROJECT_NAME_COMP=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${PROJECT_NAME_COMP_QUERY}" --output text)
echo "## The project name and component: ${PROJECT_NAME_COMP}"

echo "## Get the AllocationId of the Elastic IP"
ALLOC_ID_QUERY="Stacks[0].Outputs[?OutputKey=='${ALLOC_ID_OUTPUT_KEY}'].OutputValue"
ALLOC_ID=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${ALLOC_ID_QUERY}" --output text)
echo "## The AllocationId of the Elastic IP: ${ALLOC_ID}"

echo "## Get the SSM parameter name to store the public (IPv4) address of the EC2 instance"
PARAMETER_NAME_QUERY="Stacks[0].Outputs[?OutputKey=='${PARAMETER_NAME_OUTPUT_KEY}'].OutputValue"
PARAMETER_NAME=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${PARAMETER_NAME_QUERY}" --output text)
echo "## The SSM parameter name to store the public (IPv4) address of the EC2 instance: ${PARAMETER_NAME}"

echo "## Get the VPC name for use in the EC2 instance name"
VPC_NAME_QUERY="Stacks[0].Outputs[?OutputKey=='${VPC_NAME_OUTPUT_KEY}'].OutputValue"
VPC_NAME=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${VPC_NAME_QUERY}" --output text)
echo "## The VPC name for use in the EC2 instance name: ${VPC_NAME}"

# -----

echo "## Get EC2 instance ID"
EC2_INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
echo "## EC2 instance ID: ${EC2_INSTANCE_ID}"

echo "## Get EC2 instance name"
EC2_INSTANCE_NAME="${PROJECT_NAME_COMP}-${VPC_NAME}-public"
echo "## EC2 instance name: ${EC2_INSTANCE_NAME}"

echo "## Update EC2 instance name"
aws ec2 create-tags --region "${REGION}" --resources "${EC2_INSTANCE_ID}" --tags Key=Name,Value="${EC2_INSTANCE_NAME}"

echo "## Associate the AllocationId of the Elastic IP with EC2 instance ID"
aws ec2 associate-address --region "${REGION}" --allocation-id "${ALLOC_ID}" --instance-id "${EC2_INSTANCE_ID}"

# -----

echo "## Load Tinyproxy configuration from AWS Systems Manager Parameter Store"
PARAM_NAME_PATH="/${CDK_STACK_NAME}/tinyproxy-conf"
TINYPROXY_CONF_PATH="/etc/tinyproxy/tinyproxy.conf"
TINYPROXY_CONF_OPTS="$(aws ssm get-parameter --region "${REGION}" --name ${PARAM_NAME_PATH} --with-decryption --query "Parameter.Value" --output text)"
TINYPROXY_CONF_OPTS=$(echo "${TINYPROXY_CONF_OPTS}" | tr '\n' ' ')
DELIMITER=","

echo "## Clear Tinyproxy configuration file: ${TINYPROXY_CONF_PATH}"
echo "" > ${TINYPROXY_CONF_PATH}

echo "## Creating Tinyproxy configuration options array"
TINYPROXY_CONF_OPTS_ARRAY=()
TINYPROXY_CONF_OPTS="${TINYPROXY_CONF_OPTS}${DELIMITER}"
while [[ ${TINYPROXY_CONF_OPTS} ]]; do
  TINYPROXY_CONF_OPTS_ARRAY+=( "${TINYPROXY_CONF_OPTS%%"${DELIMITER}"*}" )
  TINYPROXY_CONF_OPTS=${TINYPROXY_CONF_OPTS#*"${DELIMITER}"}
done

echo "## Populating Tinyproxy configuration file"
SECRET_NAME="${CDK_STACK_NAME}/proxy-server-basic-auth"
PLACEHOLDER_PW="<password>"
for TINYPROXY_CONF_OPT in "${TINYPROXY_CONF_OPTS_ARRAY[@]}"; do
  echo "## Tinyproxy configuration option: ${TINYPROXY_CONF_OPT}"
  if [[ "${TINYPROXY_CONF_OPT}" == BasicAuth* ]]; then
    echo "## Updating Tinyproxy configuration BasicAuth option password"
    TINYPROXY_CONF_OPT_BASIC_AUTH_PW="$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${SECRET_NAME}" --query "SecretString" --output text | jq -r '."password"')"
    TINYPROXY_CONF_OPT="${TINYPROXY_CONF_OPT/${PLACEHOLDER_PW}/${TINYPROXY_CONF_OPT_BASIC_AUTH_PW}}"
  fi
  echo "${TINYPROXY_CONF_OPT}" >> ${TINYPROXY_CONF_PATH}
done

echo "## Restart Tinyproxy service as root"
service tinyproxy restart

# -----

echo "## Get Elastic IP public IPv4 address"
PUBLIC_IPV4=$(aws ec2 describe-addresses --region "${REGION}" --allocation-ids "${ALLOC_ID}" --query "Addresses[0].PublicIp" --output text)
echo "## EC2 instance public IPv4 address: ${PUBLIC_IPV4}"

echo "## Write EC2 instance public IPv4 address to AWS Systems Manager Parameter Store"
PARAM_PUBLIC_IPV4_DESCRIPTION="The '${PROJECT_NAME_COMP}' public IPv4 address, used by other CDK stacks for: security groups and IP whitelists."
aws ssm put-parameter --region "${REGION}" --name "${PARAMETER_NAME}" --description "${PARAM_PUBLIC_IPV4_DESCRIPTION}" --value "${PUBLIC_IPV4}" --type "String" --overwrite --tier "Standard"

echo "## EC2 User Data finished"
