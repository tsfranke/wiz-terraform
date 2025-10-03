#!/bin/bash

# Update system
apt-get update

# Install libssl1.1 dependency for MongoDB 4.4
wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb

# Install MongoDB 4.4 (outdated version)
wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-4.4.list
apt-get update
apt-get install -y mongodb-org=4.4.29 mongodb-org-server=4.4.29 mongodb-org-shell=4.4.29 mongodb-org-mongos=4.4.29 mongodb-org-tools=4.4.29

# Configure MongoDB to bind to all interfaces
sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf

# Start MongoDB without authentication first
systemctl start mongod
systemctl enable mongod

# Create admin user
sleep 10
mongo --eval 'db.getSiblingDB("admin").createUser({user: "admin", pwd: "password123", roles: ["root"]})'

# Create application database and user
mongo --eval 'db.getSiblingDB("todoapp").createUser({user: "appuser", pwd: "apppass123", roles: [{role: "readWrite", db: "todoapp"}]})'

# Now enable authentication
echo "security:" >> /etc/mongod.conf
echo "  authorization: enabled" >> /etc/mongod.conf

# Restart MongoDB with authentication
systemctl restart mongod

# Install AWS CLI
apt-get install -y awscli

# Create backup script
cat > /opt/mongodb-backup.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/mongodb-backup-$DATE"
BUCKET_NAME="${bucket_name}"

# Create backup
mongodump -u admin -p password123 --authenticationDatabase admin --out $BACKUP_DIR

# Compress backup
tar -czf /tmp/mongodb-backup-$DATE.tar.gz -C /tmp mongodb-backup-$DATE

# Upload to S3
aws s3 cp /tmp/mongodb-backup-$DATE.tar.gz s3://$BUCKET_NAME/

# Cleanup
rm -rf $BACKUP_DIR /tmp/mongodb-backup-$DATE.tar.gz
EOF

chmod +x /opt/mongodb-backup.sh

# Setup daily backup cron job
echo "0 2 * * * root /opt/mongodb-backup.sh" >> /etc/crontab
