#!/bin/bash

# check arg0: dir for keys
[ -z "$1" ] && echo "Please specify directory for ricci client cert generation" && exit 1
CRTDIR="$1"

# set umask
umask 0022

# create directory tree if it does not exist
[ ! -d "$CRTDIR" ] && mkdir -p $CRTDIR

# write config file
[ ! -f $CRTDIR/cacert.config ] && cat >> $CRTDIR/cacert.config << EOF
[ req ]
distinguished_name     = req_distinguished_name
attributes             = req_attributes
prompt                 = no

[ req_distinguished_name ]
C                      = US
ST                     = State or Province
L                      = Locality
O                      = Organization Name
OU                     = Organizational Unit Name
CN                     = Common Name
emailAddress           = root@localhost

[ req_attributes ]
EOF

# ricci client:
[ ! -f $CRTDIR/privkey.pem ] && /usr/bin/openssl genrsa -out $CRTDIR/privkey.pem 2048 
[ ! -f $CRTDIR/cacert.pem  ] && /usr/bin/openssl req -new -x509 -key $CRTDIR/privkey.pem -out $CRTDIR/cacert.pem -days 1825 -config $CRTDIR/cacert.config

echo "Success" && exit 0
