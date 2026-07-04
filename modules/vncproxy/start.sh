#!/bin/bash

# bash build.sh

mkdir -p /var/vncproxy

# Database file name
DBFILE="/var/vncproxy/vncproxy.db"

rm -fr $DBFILE

# Create the SQLite database and table
sqlite3 $DBFILE <<EOF
CREATE TABLE IF NOT EXISTS vncproxy (
    forward_key VARCHAR(8) PRIMARY KEY,
    dest_addr TEXT NOT NULL,
    dest_passwd VARCHAR(8),
    comment TEXT
);
EOF

# Function to insert a record into the vncproxy table
record() {
    sqlite3 $DBFILE "INSERT INTO vncproxy (forward_key, dest_addr, dest_passwd, comment) VALUES ('$1', '$2', '$3', '$4');"
}

# Example data insertion
#record "D250aaaa" "10.250.0.2:5900" "D250xxxx" "Alpha One"
#record "D250bbbb" "10.250.0.3:5900" "null" "Bravo Two"
#record "D250cccc" "zerotop-xtouch:5900" "null" "Gamma Three"

if [[ -f /var/vncproxy/records ]]
then
	source /var/vncproxy/records
fi

if [[ /bin/vncproxy ]]
then
	source /etc/srvctl/host.conf
	vncproxy $SC_HOST_IP:5900 $DBFILE
fi

echo "OK: vncproxy $SC_HOST_IP:5900"