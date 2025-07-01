#!/bin/bash

# Destroy EC2 Instance Script
# This script terminates an EC2 instance
# Environment variables required:
# - EC2_INSTANCE_ID: The instance ID to terminate

set -e

echo "Checking if EC2_INSTANCE_ID is available"
if [ -z "$EC2_INSTANCE_ID" ]; then
  echo "No EC2_INSTANCE_ID found, skipping destruction"
  exit 0
fi

echo "Destroying EC2 Instance - $EC2_INSTANCE_ID"
aws ec2 terminate-instances --instance-ids $EC2_INSTANCE_ID --region us-west-2
echo "Instance destroyed successfully"
