#!/bin/bash

# Canonical, Ubuntu, 22.04 LTS, amd64 jammy image

echo "## EC2 User Data starting"

CDK_STACK_NAME="CdkOpenvpnVpnServerStack" # The CDK stack name, used to get CDK stack (CloudFormation) outputs

PROJECT_NAME_COMP_OUTPUT_KEY="CdkopenvpnvpnserverCfnOutput" # The CloudFormation output key - The project name and component
URL_OUTPUT_KEY="CdkopenvpnvpnserverurlCfnOutput" # The CloudFormation output key - The server URL
NLB_DNS_NAME_OUTPUT_KEY="CdkopenvpnvpnservernlbdnsnameCfnOutput" # The CloudFormation output key - The NLB DNS name
BASE_STACK_NAME_OUTPUT_KEY="CdkopenvpnvpnserverbasestacknameCfnOutput" # The CloudFormation output key - The name of a dependant (Base) CDK stack
USER_STACK_NAME_OUTPUT_KEY="CdkopenvpnvpnserveruserstacknameCfnOutput" # The CloudFormation output key - The name of a dependant (User) CDK stack
ALLOC_ID_OUTPUT_KEY="CdkopenvpnvpnserverAllocationIdCfnOutput" # The CloudFormation output key - The AllocationId of the Elastic IP
PARAMETER_NAME_OUTPUT_KEY="Cdkopenvpnvpnserverpublicipv4parameternameCfnOutput" # The CloudFormation output key - The SSM parameter name to store the public (IPv4) address of the EC2 instance
VPC_NAME_OUTPUT_KEY="CdkopenvpnvpnservervpcnameCfnOutput" # The CloudFormation output key - The VPC name for use in the EC2 instance name
ADMIN_PASSWORD_LEN_OUTPUT_KEY="CdkopenvpnvpnserveradminpasswordlenCfnOutput" # The CloudFormation output key - The admin password length
USER_PASSWORD_LEN_OUTPUT_KEY="CdkopenvpnvpnserveruserpasswordlenCfnOutput" # The CloudFormation output key - The (VPN) user password length

echo "## Update the apt package index and install packages"
apt-get update -y
apt-get install -y jq ntp unzip

echo "## Install AWS CLI tools"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
aws --version

echo "## Get AWS region"
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
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

echo "## Get the Admin Web UI, using the server URL"
URL_QUERY="Stacks[0].Outputs[?OutputKey=='${URL_OUTPUT_KEY}'].OutputValue"
URL=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${URL_QUERY}" --output text)
echo "## The Admin Web UI: ${URL}admin"

echo "## Get the NLB DNS name"
NLB_DNS_NAME_QUERY="Stacks[0].Outputs[?OutputKey=='${NLB_DNS_NAME_OUTPUT_KEY}'].OutputValue"
NLB_DNS_NAME=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${NLB_DNS_NAME_QUERY}" --output text)
echo "## The NLB DNS name: ${NLB_DNS_NAME}"

echo "## Get the name of a dependant (Base) CDK stack"
BASE_STACK_NAME_QUERY="Stacks[0].Outputs[?OutputKey=='${BASE_STACK_NAME_OUTPUT_KEY}'].OutputValue"
BASE_STACK_NAME=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${BASE_STACK_NAME_QUERY}" --output text)
echo "## The name of a dependant (Base) CDK stack: ${BASE_STACK_NAME}"

echo "## Get the name of a dependant (Psk) CDK stack"
USER_STACK_NAME_QUERY="Stacks[0].Outputs[?OutputKey=='${USER_STACK_NAME_OUTPUT_KEY}'].OutputValue"
USER_STACK_NAME=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${USER_STACK_NAME_QUERY}" --output text)
echo "## The name of a dependant (Psk) CDK stack: ${USER_STACK_NAME}"

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

echo "## Get the admin password length"
ADMIN_PASSWORD_LEN_QUERY="Stacks[0].Outputs[?OutputKey=='${ADMIN_PASSWORD_LEN_OUTPUT_KEY}'].OutputValue"
ADMIN_PASSWORD_LEN=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${ADMIN_PASSWORD_LEN_QUERY}" --output text)
echo "## The admin password length: ${ADMIN_PASSWORD_LEN}"

echo "## Get the (VPN) user password length"
USER_PASSWORD_LEN_QUERY="Stacks[0].Outputs[?OutputKey=='${USER_PASSWORD_LEN_OUTPUT_KEY}'].OutputValue"
USER_PASSWORD_LEN=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${USER_PASSWORD_LEN_QUERY}" --output text)
echo "## The (VPN) user password length: ${USER_PASSWORD_LEN}"

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

# Launch automation pre-configuration for OpenVPN Access Server (see remaining EC2 User Data):
#  https://openvpn.net/vpn-server-resources/amazon-web-services-ec2-byol-appliance-quick-start-guide/

echo "## Setting OpenVPN Access Server public hostname to: ${NLB_DNS_NAME}"
/usr/local/openvpn_as/scripts/sacli --key host.name --value "${NLB_DNS_NAME}" ConfigPut

echo "## Load OpenVPN Access Server admin password from AWS Secrets Manager"
SECRET_NAME="${CDK_STACK_NAME}/ADMIN_PASSWORD/${ADMIN_PASSWORD_LEN}"
ADMIN_PASSWORD_SECRET=$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${SECRET_NAME}" --query "SecretString" --output text)
ADMIN_PASSWORD_USER=$(echo "${ADMIN_PASSWORD_SECRET}" | jq -r '."admin_username"')
ADMIN_PASSWORD_PW=$(echo "${ADMIN_PASSWORD_SECRET}" | jq -r '."password"')

echo "## Setting OpenVPN Access Server admin password"
/usr/local/openvpn_as/scripts/sacli --user "${ADMIN_PASSWORD_USER}" --new_pass "${ADMIN_PASSWORD_PW}" SetLocalPassword

# The OpenVPN Access Server license key.
# Note: Without a license key, OpenVPN Access Server allows up to two concurrent connections.
#echo "## Load OpenVPN Access Server license from AWS Secrets Manager"
#SECRET_NAME="${BASE_STACK_NAME}/LICENSE"
## shellcheck disable=SC2034
#license=$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${SECRET_NAME}" --query "SecretString" --output text | jq -r '."password"')

echo "## Setting OpenVPN Access Server reroute_gw to 'true'"
/usr/local/openvpn_as/scripts/sacli --key "vpn.client.routing.reroute_gw" --value "true" ConfigPut

echo "## Load OpenVPN Access Server user password from AWS Secrets Manager"
SECRET_NAME="${USER_STACK_NAME}/VPN_USER/${USER_PASSWORD_LEN}"
VPN_USER_SECRET=$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${SECRET_NAME}" --query "SecretString" --output text)
VPN_USER_USER=$(echo "${VPN_USER_SECRET}" | jq -r '."username"')
VPN_USER_PW=$(echo "${VPN_USER_SECRET}" | jq -r '."password"')

echo "## Setting up VPN user for OpenVPN Access Server"
/usr/local/openvpn_as/scripts/sacli --user "${VPN_USER_USER}" --new_pass "${VPN_USER_PW}" SetLocalPassword
/usr/local/openvpn_as/scripts/sacli --user "${VPN_USER_USER}" --key "type" --value "user_connect" UserPropPut
/usr/local/openvpn_as/scripts/sacli --user "${VPN_USER_USER}" --key "prop_autologin" --value "true" UserPropPut

echo "## Starting OpenVPN Access Server"
/usr/local/openvpn_as/scripts/sacli start

# -----

echo "## Get Elastic IP public IPv4 address"
PUBLIC_IPV4=$(aws ec2 describe-addresses --region "${REGION}" --allocation-ids "${ALLOC_ID}" --query "Addresses[0].PublicIp" --output text)
echo "## EC2 instance public IPv4 address: ${PUBLIC_IPV4}"

echo "## Write EC2 instance public IPv4 address to AWS Systems Manager Parameter Store"
PARAM_PUBLIC_IPV4_DESCRIPTION="The '${PROJECT_NAME_COMP}' public IPv4 address, used by other CDK stacks for: security groups and IP whitelists."
aws ssm put-parameter --region "${REGION}" --name "${PARAMETER_NAME}" --description "${PARAM_PUBLIC_IPV4_DESCRIPTION}" --value "${PUBLIC_IPV4}" --type "String" --overwrite --tier "Standard"

echo "## EC2 User Data finished"
