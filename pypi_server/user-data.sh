#!/bin/bash

# Amazon Linux 2 x86_64 HVM gp2

echo "## EC2 User Data starting"

CDK_STACK_NAME="CdkPypiServerStack" # The CDK stack name, used to get CDK stack (CloudFormation) outputs

PROJECT_NAME_COMP_OUTPUT_KEY="CdkpypiserverCfnOutput" # The CloudFormation output key - The project name and component
BASE_STACK_NAME_OUTPUT_KEY="CdkpypiserverbasestacknameCfnOutput" # The CloudFormation output key - The name of a dependant (Base) CDK stack
VPC_NAME_OUTPUT_KEY="CdkpypiservervpcnameCfnOutput" # The CloudFormation output key - The VPC name for use in the EC2 instance name
EFS_FILE_SYSTEM_ID_OUTPUT_KEY="CdkpypiserverefsfilesystemidCfnOutput" # The CloudFormation output key - The Elastic File System (EFS) file system ID
SERVER_DESCRIPTION_OUTPUT_KEY="CdkpypiserverserverdescriptionCfnOutput" # The CloudFormation output key - The server description insert

echo "## Update the yum package index and install packages"
yum update -y
yum install -y httpd-tools jq nfs-utils
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

echo "## Get the VPC name for use in the EC2 instance name"
VPC_NAME_QUERY="Stacks[0].Outputs[?OutputKey=='${VPC_NAME_OUTPUT_KEY}'].OutputValue"
VPC_NAME=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${VPC_NAME_QUERY}" --output text)
echo "## The VPC name for use in the EC2 instance name: ${VPC_NAME}"

echo "## Get the Elastic File System (EFS) file system ID"
EFS_FILE_SYSTEM_ID_QUERY="Stacks[0].Outputs[?OutputKey=='${EFS_FILE_SYSTEM_ID_OUTPUT_KEY}'].OutputValue"
EFS_FILE_SYSTEM_ID=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${EFS_FILE_SYSTEM_ID_QUERY}" --output text)
echo "## The Elastic File System (EFS) file system ID: ${EFS_FILE_SYSTEM_ID}"

echo "## Get the server description insert"
SERVER_DESCRIPTION_QUERY="Stacks[0].Outputs[?OutputKey=='${SERVER_DESCRIPTION_OUTPUT_KEY}'].OutputValue"
SERVER_DESCRIPTION=$(aws cloudformation describe-stacks --stack-name ${CDK_STACK_NAME} --region "${REGION}" --query "${SERVER_DESCRIPTION_QUERY}" --output text)
echo "## The server description insert: ${SERVER_DESCRIPTION}"

# -----

echo "## Get EC2 instance ID"
EC2_INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
echo "## EC2 instance ID: ${EC2_INSTANCE_ID}"

echo "## Get EC2 instance name"
EC2_INSTANCE_NAME="${PROJECT_NAME_COMP}-${VPC_NAME}-private"
echo "## EC2 instance name: ${EC2_INSTANCE_NAME}"

echo "## Update EC2 instance name"
aws ec2 create-tags --region "${REGION}" --resources "${EC2_INSTANCE_ID}" --tags Key=Name,Value="${EC2_INSTANCE_NAME}"

# -----

MOUNTED_ON_PATH="/opt/${PROJECT_NAME_COMP}" # The file system path to find the mounted EFS file system
HTPASSWD_PATH="${MOUNTED_ON_PATH}/htpasswd" # The file system path to the htpasswd config dir
PACKAGES_PATH="${MOUNTED_ON_PATH}/packages" # The file system path to the packages dir
SERVICE_FILENAME="${PROJECT_NAME_COMP}.service" # The service filename
SERVICE_FILENAME_FULL_PATH="/etc/systemd/system/${SERVICE_FILENAME}" # The file system path to the service filename
RUN_SCRIPT="/opt/run_${PROJECT_NAME_COMP}.sh" # The file system path to the run script

echo "## Load from AWS Secrets Manager: port, username and password details"
SECRET_NAME="${BASE_STACK_NAME}/PYPI_SERVER_SECRET"
SERVER_SECRET=$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${SECRET_NAME}" --query "SecretString" --output text)
PORT=$(echo "${SERVER_SECRET}" | jq -r '."port"')
USERNAME=$(echo "${SERVER_SECRET}" | jq -r '."username"')
PASSWORD=$(echo "${SERVER_SECRET}" | jq -r '."password"')

echo "## Make ${MOUNTED_ON_PATH} dir"
mkdir "${MOUNTED_ON_PATH}"

echo "## Write to ${RUN_SCRIPT} file"
cat >"${RUN_SCRIPT}" <<EOL
#!/usr/bin/env bash
sudo yum update -y
sudo yum install -y python3
sudo python3 -m pip install passlib
sudo python3 -m pip install pypiserver
sudo python3 -m pypiserver -v -p ${PORT} -P ${HTPASSWD_PATH} -a download,update,list ${PACKAGES_PATH}
EOL

echo "## Update ${RUN_SCRIPT} file permissions"
chmod u+x "${RUN_SCRIPT}"

echo "## Write to ${SERVICE_FILENAME_FULL_PATH} file"
cat >"${SERVICE_FILENAME_FULL_PATH}" <<EOL
[Unit]
Description="${SERVER_DESCRIPTION} (AWS CDK)"
After=network.target
[Service]
Type=simple
ExecStart=${RUN_SCRIPT}
KillMode=process
Restart=on-failure
RestartSec=42s
[Install]
WantedBy=default.target
EOL

OWNER_USER="ec2-user"
echo "## Update owner of ${MOUNTED_ON_PATH} dir to: ${OWNER_USER}"
chown -R ${OWNER_USER}:${OWNER_USER} "${MOUNTED_ON_PATH}"

ETC_FSTAB="/etc/fstab"
echo "## Persist the EFS file system in ${ETC_FSTAB} so it gets automatically mounted again after reboot"
test -f "/sbin/mount.efs" && echo "${EFS_FILE_SYSTEM_ID}:/ ${MOUNTED_ON_PATH} efs defaults,_netdev" >>${ETC_FSTAB} || echo "${EFS_FILE_SYSTEM_ID}.efs.${REGION}.amazonaws.com:/ ${MOUNTED_ON_PATH} nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0" >>${ETC_FSTAB}

echo "## Mount the EFS file system at: ${MOUNT_PATH} -> ${MOUNTED_ON_PATH}"
mount -a -t efs,nfs4 defaults

echo "## Make ${PACKAGES_PATH} dir"
mkdir "${PACKAGES_PATH}"

echo "## Set username and password for authentication"
htpasswd -b -c "${HTPASSWD_PATH}" "${USERNAME}" "${PASSWORD}"

echo "## Enable the PyPi server service"
systemctl enable "${SERVICE_FILENAME}"

echo "## Start the PyPi server service"
systemctl start "${SERVICE_FILENAME}"

echo "## Sleep 1 second ..."
sleep 1

echo "## EC2 User Data finished"
