#!/bin/bash
if [ -z "$1" ]; then
  echo "Options:"
  echo "  --launch: Launch a new EC2 instance with the latest AMI"
  echo "  --stop <instance_info_file>: Stop the EC2 instance"
  echo "  --start <instance_info_file>: Start the EC2 instance"
  exit 0
fi

# Check if the AWS CLI is installed
if ! command -v aws &> /dev/null; then
  echo "AWS CLI is not installed. Please install it first."
  exit 1
fi

# Load variables from config file launch-chip-atlas.conf including AWS_EC2_LAUNCH_TEMPLATE_ID and CHIP_ATLAS_AWS_ACCOUNT_ID
source "./launch-chip-atlas.conf"

# Check if the environment variables are set
if [ -z $AWS_EC2_LAUNCH_TEMPLATE_ID ]; then
  echo "The environment variable AWS_EC2_LAUNCH_TEMPLATE_ID is not set. Exiting."
  exit 1
fi
if [ -z $CHIP_ATLAS_AWS_ACCOUNT_ID ]; then
  echo "The environment variable CHIP_ATLAS_AWS_ACCOUNT_ID is not set. Exiting."
  exit 1
fi

# Check if the AWS token is in the environment variable
AWS_ACCOUNT_ID_OF_TOKEN=$(aws sts get-caller-identity --query Account --output text)
if [ $AWS_ACCOUNT_ID_OF_TOKEN != $CHIP_ATLAS_AWS_ACCOUNT_ID ]; then
  echo "The AWS token is not for the CHIP Atlas account. Exiting."
  exit 1
else
  echo "The AWS token is for the CHIP-Atlas account. Proceeding."
fi

# Launch the instance if the command line option is --launch
# Return the instance ID and the assigned ip if the instance is launched successfully
if [ "$1" == "--launch" ]; then
  # Get the latest AMI
  LATEST_AMI_INFO=$(aws ec2 describe-images \
    --owners $CHIP_ATLAS_AWS_ACCOUNT_ID \
    --query 'Images[*].[ImageId,CreationDate,Name]' \
    --output text | sort -k2 -r | head -1
  )
  LATEST_AMI_ID=$(echo $LATEST_AMI_INFO | cut -d' ' -f1)
  INSTANCE_CREATION_DATE=$(echo $LATEST_AMI_INFO | cut -d' ' -f3 | cut -d'-' -f1)
  echo "The latest AMI ID is $LATEST_AMI_ID created at $(echo $LATEST_AMI_INFO | cut -d' ' -f2) originally created from $INSTANCE_CREATION_DATE)"

  # Script to launch an EC2 instance using the latest AMI
  TEMPORAL_INSTANCE_NAME="temporalInstance-$(date +'%Y%m%d-%H%M%S')"
  TEMPORAL_INSTANCE_INFO_FILE="${TEMPORAL_INSTANCE_NAME}_info.json"

  echo "Launching the instance with the latest AMI using the launch template $AWS_EC2_LAUNCH_TEMPLATE_ID"
  aws ec2 run-instances --count 1 \
    --launch-template LaunchTemplateId=$AWS_EC2_LAUNCH_TEMPLATE_ID \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${TEMPORAL_INSTANCE_NAME}}]" \
    --image-id $LATEST_AMI_ID \
  > $TEMPORAL_INSTANCE_INFO_FILE \
  && echo "The instance is launched successfully."

  # Wait until the http status code of the webapp turns to 200
  echo "Waiting for the webapp to be up. This may take several minutes..."
  for i in {1..10}; do
    INSTANCE_ID=$(jq -r '.Instances[0].InstanceId' $TEMPORAL_INSTANCE_INFO_FILE)
    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    echo "Public IP: $PUBLIC_IP"
    HTTP_STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$PUBLIC_IP)
    if [ $HTTP_STATUS_CODE -eq 200 ]; then
      echo "ChIP-Atlas is up and running at http://$PUBLIC_IP"
      break
    else
      echo "Webapp is not up yet. Waiting for 90 seconds..."
      sleep 90
    fi
  done
fi

# Stop the instance if the command line option is --stop
if [ "$1" == "--stop" ]; then
  # Second argument should be the instance info file
  if [ -z "$2" ]; then
      echo "Please provide the instance info file as the second argument."
      exit 1
  fi
  INSTANCE_ID=$(jq -r '.Instances[0].InstanceId' $2)
  echo "Stopping the instance $INSTANCE_ID"
  aws ec2 stop-instances --instance-ids $INSTANCE_ID > /dev/null

  # Wait until the instance is stopped
  echo "Waiting for the instance to be stopped. This may take several minutes..."
  for i in {1..10}; do
    INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name' --output text)
    if [ $INSTANCE_STATE == "stopped" ]; then
      echo "The instance $INSTANCE_ID is stopped."
      break
    else
      echo "The instance is not stopped yet. Waiting for 90 seconds..."
      sleep 90
    fi
  done
fi

# Start the instance if the command line option is --start
if [ "$1" == "--start" ]; then
  # Second argument should be the instance info file
  if [ -z "$2" ]; then
      echo "Please provide the instance info file as the second argument."
      exit 1
  fi
  INSTANCE_ID=$(jq -r '.Instances[0].InstanceId' $2)
  echo "Starting the instance $INSTANCE_ID"
  aws ec2 start-instances --instance-ids $INSTANCE_ID > /dev/null

  # Wait until the http status code of the webapp turns to 200
    echo "Waiting for the webapp to be up. This may take several minutes..."
    for i in {1..10}; do
    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    echo "Public IP: $PUBLIC_IP"
    HTTP_STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$PUBLIC_IP)
    if [ $HTTP_STATUS_CODE -eq 200 ]; then
      echo "ChIP-Atlas is up and running at http://$PUBLIC_IP"
      break
    else
      echo "Webapp is not up yet. Waiting for 90 seconds..."
      sleep 90
    fi
  done
fi
