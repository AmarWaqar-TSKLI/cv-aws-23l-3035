#!/bin/bash
set -e

dnf install -y nginx
systemctl enable --now nginx

# sync script (same as ec2/sync-cv.sh)
cat > /usr/local/bin/sync-cv.sh <<'SYNC'
#!/bin/bash
# Sync the CV from S3 into the web root and set the footer

BUCKET="cv-23l-3035"
PREFIX="site/"
WEB_ROOT="/usr/share/nginx/html"
LOG="/var/log/cv-sync.log"

# IMDSv2 token
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)

if aws s3 sync "s3://$BUCKET/$PREFIX" "$WEB_ROOT" --region "$REGION" --only-show-errors \
   && [ -n "$INSTANCE_ID" ] \
   && sed -i "s/{{HOSTED_ON}}/EC2 $INSTANCE_ID/" "$WEB_ROOT/index.html"; then
  STATUS="ok"
else
  STATUS="failed"
fi

echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') sync=$STATUS instance=$INSTANCE_ID" >> "$LOG"
SYNC
chmod 755 /usr/local/bin/sync-cv.sh

# run the sync every 2 minutes
cat > /etc/systemd/system/cv-sync.service <<'UNIT'
[Unit]
Description=Sync CV from S3

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-cv.sh
UNIT

cat > /etc/systemd/system/cv-sync.timer <<'UNIT'
[Unit]
Description=Run cv-sync every 2 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
UNIT

/usr/local/bin/sync-cv.sh
systemctl daemon-reload
systemctl enable --now cv-sync.timer
