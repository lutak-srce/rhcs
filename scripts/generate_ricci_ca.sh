#!/bin/bash

# check arg0: dir for keys
[ -z "$1" ] && echo "Please specify directory for ricci CA generation" && exit 1
CADIR="$1"

# set umask
umask 0022

# create directory tree if it does not exist
[ ! -d "$CADIR" ] && mkdir -p $CADIR

#
# functions stolen from CentOS 6 ricci init script
#

# Some functions to make the below more readable
SSL_PUBKEY="$CADIR/cacert.pem"
SSL_PRIVKEY="$CADIR/privkey.pem"
NSS_CERTS_DIR="$CADIR"
NSS_PKCS12="$CADIR/server.p12"
CONFIG="$CADIR/cacert.config"

[ ! -f $CONFIG ] && cat >> $CONFIG << EOF
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

ssl_certs_ok()
{
        if [ ! -f "$SSL_PRIVKEY" ] ; then
                return 1
        fi
        if [ ! -f "$SSL_PUBKEY" ] ; then
                return 2
        fi
        return 0
}

nss_certs_ok()
{
        test -f "$NSS_PKCS12"
        return $?
}

generate_ssl_certs()
{
        rm -f "$SSL_PUBKEY" "$SSL_PRIVKEY"
        echo -n "generating SSL certificates...  "
        /usr/bin/openssl genrsa -out "$SSL_PRIVKEY" 2048 >&/dev/null &&
        /usr/bin/openssl req -new -x509 -key "$SSL_PRIVKEY" -out "$SSL_PUBKEY" -days 1825 -config $CONFIG &&
        /bin/chown $RUNASUSER:$RUNASUSER "$SSL_PRIVKEY" "$SSL_PUBKEY" &&
        /bin/chmod 600 "$SSL_PRIVKEY" &&
        /bin/chmod 644 "$SSL_PUBKEY"
        ret=$?
        echo "done"
        return $ret
}

generate_nss_certs()
{
        echo -n "Generating NSS database...  "
        openssl pkcs12 -export -in "$SSL_PUBKEY" -inkey "$SSL_PRIVKEY" -out "$NSS_PKCS12" -name "ricci private key" -passout pass: >&/dev/null
        certutil -N -d "$NSS_CERTS_DIR" -f /dev/zero
        pk12util -i "$NSS_PKCS12" -d "$NSS_CERTS_DIR" -w /dev/zero >/dev/null
        chmod 600 $NSS_CERTS_DIR/{cert8.db,key3.db,secmod.db}
        chown ricci:ricci $NSS_CERTS_DIR/{cert8.db,key3.db,secmod.db} "$NSS_PKCS12"
        ret=$?
        echo "done"
        return $ret
}

# main
ssl_certs_ok
if [ "$?" -ne 0 ] ; then
        generate_ssl_certs
fi
nss_certs_ok
if [ "$?" -ne 0 ] ; then
        generate_nss_certs
fi
chmod -R 440 $CADIR/*
echo "Success" && exit 0
