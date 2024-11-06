#!/bin/bash

# Amazon Linux 2 x86_64 HVM gp2

echo "## EC2 User Data starting"

CDK_STACK_NAME="CdkIpsecVpnServerStack" # The CDK stack name, used to get CDK stack (CloudFormation) outputs

PROJECT_NAME_COMP_OUTPUT_KEY="CdkipsecvpnserverCfnOutput" # The CloudFormation output key - The project name and component
BASE_STACK_NAME_OUTPUT_KEY="CdkipsecvpnserverbasestacknameCfnOutput" # The CloudFormation output key - The name of a dependant (Base) CDK stack
PSK_STACK_NAME_OUTPUT_KEY="CdkipsecvpnserverpskstacknameCfnOutput" # The CloudFormation output key - The name of a dependant (PSK) CDK stack
ALLOC_ID_OUTPUT_KEY="CdkipsecvpnserverAllocationIdCfnOutput" # The CloudFormation output key - The AllocationId of the Elastic IP
LOG_GROUP_NAME_OUTPUT_KEY="CdkipsecvpnserverloggroupnameCfnOutput" # The CloudFormation output key - The Logs log group name for use in the EC2 instance setup
PARAMETER_NAME_OUTPUT_KEY="Cdkipsecvpnserverpublicipv4parameternameCfnOutput" # The CloudFormation output key - The SSM parameter name to store the public (IPv4) address of the EC2 instance
VPC_NAME_OUTPUT_KEY="CdkipsecvpnservervpcnameCfnOutput" # The CloudFormation output key - The VPC name for use in the EC2 instance name
PSK_LEN_OUTPUT_KEY="CdkipsecvpnserverpsklenCfnOutput" # The CloudFormation output key - The PSK length

echo "## Update the yum package index and install packages"
yum update -y
yum install -y docker jq
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

echo "## Get the name of a dependant (Base) CDK stack"
BASE_STACK_NAME_QUERY="Stacks[0].Outputs[?OutputKey=='${BASE_STACK_NAME_OUTPUT_KEY}'].OutputValue"
BASE_STACK_NAME=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${BASE_STACK_NAME_QUERY}" --output text)
echo "## The name of a dependant (Base) CDK stack: ${BASE_STACK_NAME}"

echo "## Get the name of a dependant (PSK) CDK stack"
PSK_STACK_NAME_QUERY="Stacks[0].Outputs[?OutputKey=='${PSK_STACK_NAME_OUTPUT_KEY}'].OutputValue"
PSK_STACK_NAME=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${PSK_STACK_NAME_QUERY}" --output text)
echo "## The name of a dependant (PSK) CDK stack: ${PSK_STACK_NAME}"

echo "## Get the AllocationId of the Elastic IP"
ALLOC_ID_QUERY="Stacks[0].Outputs[?OutputKey=='${ALLOC_ID_OUTPUT_KEY}'].OutputValue"
ALLOC_ID=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${ALLOC_ID_QUERY}" --output text)
echo "## The AllocationId of the Elastic IP: ${ALLOC_ID}"

echo "## Get the Logs log group name for use in the EC2 instance setup"
LOG_GROUP_NAME_QUERY="Stacks[0].Outputs[?OutputKey=='${LOG_GROUP_NAME_OUTPUT_KEY}'].OutputValue"
LOG_GROUP_NAME=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${LOG_GROUP_NAME_QUERY}" --output text)
echo "## The Logs log group name for use in the EC2 instance setup: ${LOG_GROUP_NAME}"

echo "## Get the SSM parameter name to store the public (IPv4) address of the EC2 instance"
PARAMETER_NAME_QUERY="Stacks[0].Outputs[?OutputKey=='${PARAMETER_NAME_OUTPUT_KEY}'].OutputValue"
PARAMETER_NAME=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${PARAMETER_NAME_QUERY}" --output text)
echo "## The SSM parameter name to store the public (IPv4) address of the EC2 instance: ${PARAMETER_NAME}"

echo "## Get the VPC name for use in the EC2 instance name"
VPC_NAME_QUERY="Stacks[0].Outputs[?OutputKey=='${VPC_NAME_OUTPUT_KEY}'].OutputValue"
VPC_NAME=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${VPC_NAME_QUERY}" --output text)
echo "## The VPC name for use in the EC2 instance name: ${VPC_NAME}"

echo "## Get the PSK length"
PSK_LEN_QUERY="Stacks[0].Outputs[?OutputKey=='${PSK_LEN_OUTPUT_KEY}'].OutputValue"
PSK_LEN=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${PSK_LEN_QUERY}" --output text)
echo "## The PSK length: ${PSK_LEN}"

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

echo "## Load environment variables from AWS Systems Manager Parameter Store"
for PARAM_NAME in VPN_USER VPN_ADDL_USERS VPN_CLIENT_NAME VPN_DNS_SRV1 VPN_DNS_SRV2; do
  PARAM_NAME_PATH="/${BASE_STACK_NAME}/${PARAM_NAME}"
  export ${PARAM_NAME}="$(aws ssm get-parameter --region "${REGION}" --name "${PARAM_NAME_PATH}" --with-decryption --query "Parameter.Value" --output text)"
done

echo "## Load VPN_IPSEC_PSK environment variable from AWS Secrets Manager"
SECRET_NAME="${PSK_STACK_NAME}/VPN_IPSEC_PSK/${PSK_LEN}"
VPN_IPSEC_PSK=$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${SECRET_NAME}" --query "SecretString" --output text | jq -r '."password"')

echo "## Load VPN_PASSWORD environment variable from AWS Secrets Manager"
SECRET_NAME="${BASE_STACK_NAME}/VPN_USER/${VPN_USER}"
VPN_PASSWORD=$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${SECRET_NAME}" --query "SecretString" --output text | jq -r '."password"')

VPN_ADDL_PASSWORDS=()
echo "## For each additional VPN user, load their p/w from AWS Secrets Manager, store in VPN_ADDL_PASSWORDS: ${VPN_ADDL_USERS}"
for ADDL_USER in ${VPN_ADDL_USERS}; do
  SECRET_NAME="${BASE_STACK_NAME}/VPN_ADDL_USERS/${ADDL_USER}"
  SECRET=$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${SECRET_NAME}" --query "SecretString" --output text | jq -r '."password"')
  VPN_ADDL_PASSWORDS+=("${SECRET}")
done

echo "## Start docker service"
service docker start

echo "## Start IPsec VPN container in daemon mode, always restart"
docker run \
  -e "VPN_IPSEC_PSK=${VPN_IPSEC_PSK}" \
  -e "VPN_USER=${VPN_USER}" \
  -e "VPN_PASSWORD=${VPN_PASSWORD}" \
  -e "VPN_ADDL_USERS=${VPN_ADDL_USERS}" \
  -e "VPN_ADDL_PASSWORDS=${VPN_ADDL_PASSWORDS[*]}" \
  -e "VPN_CLIENT_NAME=${VPN_CLIENT_NAME}" \
  -e "VPN_DNS_SRV1=${VPN_DNS_SRV1}" \
  -e "VPN_DNS_SRV2=${VPN_DNS_SRV2}" \
  --name "${PROJECT_NAME_COMP}" \
  --restart=always \
  -p 500:500/udp -p 4500:4500/udp \
  --privileged \
  --log-driver=awslogs \
  --log-opt "awslogs-region=${REGION}" \
  --log-opt "awslogs-group=${LOG_GROUP_NAME}" \
  --log-opt "awslogs-multiline-pattern='^INFO'" \
  -d hwdsl2/ipsec-vpn-server

echo "## Before using IPsec/L2TP mode, you may require docker container to restart once"
docker restart "${PROJECT_NAME_COMP}"

# -----

echo "## Get Elastic IP public IPv4 address"
PUBLIC_IPV4=$(aws ec2 describe-addresses --region "${REGION}" --allocation-ids "${ALLOC_ID}" --query "Addresses[0].PublicIp" --output text)
echo "## EC2 instance public IPv4 address: ${PUBLIC_IPV4}"

echo "## Write EC2 instance public IPv4 address to AWS Systems Manager Parameter Store"
PARAM_PUBLIC_IPV4_DESCRIPTION="The '${PROJECT_NAME_COMP}' public IPv4 address, used by other CDK stacks for: security groups and IP whitelists."
aws ssm put-parameter --region "${REGION}" --name "${PARAMETER_NAME}" --description "${PARAM_PUBLIC_IPV4_DESCRIPTION}" --value "${PUBLIC_IPV4}" --type "String" --overwrite --tier "Standard"

echo "## EC2 User Data finished"
