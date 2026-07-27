#!/usr/bin/env bash
# deploy.sh — Build locally and deploy the JAR to an EC2 instance via SSH
#
# Usage:
#   chmod +x ec2/deploy.sh
#   ./ec2/deploy.sh <ec2-public-ip> /path/to/key.pem
#
# Prerequisites:
#   - Java 17 + Maven installed locally
#   - EC2 instance running Amazon Linux 2023 with port 8080 open
#   - Your .pem key file readable (chmod 400)

set -euo pipefail

EC2_IP="${1:?Usage: $0 <ec2-public-ip> <key.pem>}"
KEY_FILE="${2:?Usage: $0 <ec2-public-ip> <key.pem>}"
APP_USER="ec2-user"
APP_PORT=8080
JAR_NAME="helloworld-springboot-java.jar"
SERVICE_NAME="helloworld-springboot"

echo "──────────────────────────────────────────"
echo "Building JAR locally..."
echo "──────────────────────────────────────────"
mvn -q clean package -DskipTests

echo "──────────────────────────────────────────"
echo "Copying files to EC2 at $EC2_IP..."
echo "──────────────────────────────────────────"
scp -i "$KEY_FILE" -o StrictHostKeyChecking=no \
    "target/$JAR_NAME" \
    "ec2/$SERVICE_NAME.service" \
    "$APP_USER@$EC2_IP:/home/$APP_USER/"

echo "──────────────────────────────────────────"
echo "Installing Java 17 and configuring systemd..."
echo "──────────────────────────────────────────"
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no "$APP_USER@$EC2_IP" << EOF
  set -euo pipefail

  # Install Java 17 if not present
  if ! java -version 2>&1 | grep -q "17"; then
    sudo yum install -y java-17-amazon-corretto-headless
  fi

  # Move JAR to /opt
  sudo mkdir -p /opt/$SERVICE_NAME
  sudo mv /home/$APP_USER/$JAR_NAME /opt/$SERVICE_NAME/app.jar
  sudo chown -R $APP_USER:$APP_USER /opt/$SERVICE_NAME

  # Install and enable the systemd service
  sudo mv /home/$APP_USER/$SERVICE_NAME.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable $SERVICE_NAME
  sudo systemctl restart $SERVICE_NAME

  echo "Service status:"
  sudo systemctl status $SERVICE_NAME --no-pager
EOF

echo "──────────────────────────────────────────"
echo "Deployment complete!"
echo "App URL: http://$EC2_IP:$APP_PORT"
echo "──────────────────────────────────────────"
