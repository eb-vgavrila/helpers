#!/bin/bash
set -e

# Cloud-init configuration to install and register GitLab runner in EC2 instance

# Log all output to a file for debugging
exec > >(tee /var/log/user-data.log) 2>&1

echo "Starting GitLab Runner installation at $(date)"

# Check if curl exists and install if not
if ! command -v curl &> /dev/null; then
    echo "curl not found, installing..."
    apt update -y && apt install -y curl
fi

echo "Downloading GitLab Runner..."
sudo curl -L --output /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
sudo chmod +x /usr/local/bin/gitlab-runner

echo "Creating GitLab Runner user..."
useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
echo "Add gitlab-runner to sudoers..."
echo "gitlab-runner ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers

echo "Installing GitLab Runner as a service..."
sudo gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
sudo gitlab-runner start

# Wait for the service to be ready
sleep 5

# Register the runner if RUNNER_TOKEN is provided
if [ -n "$RUNNER_TOKEN" ]; then
    echo "Registering GitLab Runner..."
    sudo gitlab-runner register \
        --url https://gitlab.com/ \
        --registration-token "$RUNNER_TOKEN" \
        --non-interactive \
        --executor shell \
        --description "EC2 GitLab Runner" \
        --tag-list "$RUNNER_TAG"
    
    echo "GitLab Runner registered successfully"
else
    echo "RUNNER_TOKEN not provided, skipping registration"
    exit 1
fi

# Verify installation
echo "GitLab Runner version:"
gitlab-runner --version

echo "GitLab Runner service status:"
systemctl status gitlab-runner --no-pager

echo "Removing logout script"
sudo rm /home/gitlab-runner/.bash_logout

echo "GitLab Runner installation completed at $(date)"
