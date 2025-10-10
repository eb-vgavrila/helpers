#!/bin/bash

# Create EC2 Instance Script
# Environment variables required:
# - AMI_ID: The AMI ID to use for the instance
# - INSTANCE_TYPE: The instance type (e.g., c4.large)
# - EC2_INSTANCE_NAME: The name tag for the instance
# - GITLAB_RUNNER_TOKEN: Token for GitLab runner registration
# - CI_PIPELINE_URL: Map pipeline URL to EC2 instance for traceability

set -e

echo "Getting Public Subnet ID of the VPC"
PUBLIC_SUBNET_ID=$(aws ec2 describe-route-tables --filters "Name=route.gateway-id,Values=igw-*" --query 'RouteTables[].Associations[?Main==`false`].SubnetId' --output text --region us-west-2)
echo "Public Subnet ID $PUBLIC_SUBNET_ID"

echo "Creating user data script with RUNNER_TOKEN"
cat > /tmp/user-data-with-token.sh << EOF
#!/bin/bash
export RUNNER_TOKEN="$GITLAB_RUNNER_TOKEN"
export RUNNER_TAG="ec2-glr${GITLAB_RUNNER_TAG:+_${GITLAB_RUNNER_TAG}}"
EOF

curl -s https://raw.githubusercontent.com/eb-vgavrila/helpers/refs/heads/main/cloud-init-glr.sh >> /tmp/user-data-with-token.sh

echo "Creating EC2 Instance"
INSTANCE_RESPONSE=$(aws ec2 run-instances --image-id $AMI_ID --associate-public-ip-address --instance-type $INSTANCE_TYPE --subnet-id $PUBLIC_SUBNET_ID --region us-west-2 --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${EC2_INSTANCE_NAME}_${CI_PIPELINE_URL}}]" --user-data file:///tmp/user-data-with-token.sh --output json)

echo "Instance created successfully"
EC2_INSTANCE_ID=$(echo $INSTANCE_RESPONSE | jq -r '.Instances[0].InstanceId')
echo "Instance ID - $EC2_INSTANCE_ID"

echo "Waiting for instance to reach running state..."
sleep 30  # we know it won't reach running state that fast
for i in $(seq 1 20); do
  INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID --region us-west-2 --query 'Reservations[0].Instances[0].State.Name' --output text)
  INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $EC2_INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text --region us-west-2)
  if [ "$INSTANCE_STATE" = "running" ] && [ "$INSTANCE_STATUS" = "ok" ]; then 
    echo "Instance is now running and status is ok!"
    break
  elif [ "$INSTANCE_STATE" = "terminated" ] || [ "$INSTANCE_STATE" = "stopping" ] || [ "$INSTANCE_STATE" = "stopped" ]; then 
    echo "Instance failed to start properly. Current state: $INSTANCE_STATE"
    exit 1
  fi
  if [ $i -eq 20 ]; then 
    echo "Timeout: Instance did not reach running state with ok status after 20 attempts (10 minutes)"
    exit 1
  fi
  echo "Instance state $INSTANCE_STATE, Status $INSTANCE_STATUS"
  sleep 30
done

echo "EC2_INSTANCE_ID=$EC2_INSTANCE_ID" > instance_id.env
echo "Instance creation completed successfully. Instance ID saved to instance_id.env"
