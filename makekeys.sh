#!/bin/sh

export D=`pwd`
export KEY_CONFIG=$D/openssl.cnf
export KEY_DIR=$D/keys
export KEY_SIZE=1024
export KEY_MAIL='keys@mydomain.com'

DOMAIN='netex.mydomain.com'

############################################################################################

CRL=crl.pem
RT=revoke.pem


d=$KEY_DIR

if test $# -lt 1; then
    echo "usage: $0 [init|client|getkey|revoke|unrevoke] <name>";
    exit 1
fi


case $1 in
    init)
        echo "Folder $KEY_DIR clenum (all files will be lost) (y/n)?"
        read gogogo
        if [ "$gogogo" = "y" ]; then
            echo 'Wait 5 sec'
            sleep 5
        else
            exit 1
        fi

        if test $d; then
            rm -rf $d
            mkdir $d && \
            chmod go-rwx $d && \
            touch $d/index.txt && \
            touch $d/$RT && \
            echo 01 >$d/serial
        else
            echo you must define KEY_DIR
            exit 1
        fi

        export KEY_HOST=server.${DOMAIN}

        if test $KEY_DIR; then
            cd $KEY_DIR && \
                openssl req -days 3650 -nodes -new -x509 -keyout ca.key -out ca.crt -config $KEY_CONFIG && \
                chmod 0600 ca.key

            cd $KEY_DIR && openvpn --genkey --secret ta.key && chmod 600 ta.key

            openssl dhparam -out ${KEY_DIR}/dh${KEY_SIZE}.pem ${KEY_SIZE}

            cd $KEY_DIR && \
                openssl req -days 3650 -nodes -new -keyout server.key -out server.csr -extensions server -config $KEY_CONFIG && \
                openssl ca -days 3650 -out server.crt -in server.csr -extensions server -config $KEY_CONFIG && \
                chmod 0600 server.key
        fi
    ;;
    client)
        if test $# -ne 2; then
            echo "usage: $0 client <name>";
            exit 1
        fi

        if [ -f $KEY_DIR/$2.key ]; then
            echo "key exist $2.key"
            exit 1
        fi

        export KEY_HOST=$2.${DOMAIN}

        cd $KEY_DIR && \
            openssl req -days 3650 -nodes -new -keyout $2.key -out $2.csr -config $KEY_CONFIG && \
            openssl ca -days 3650 -out $2.crt -in $2.csr -config $KEY_CONFIG && \
            chmod 0600 $2.key

        cd $KEY_DIR && \
        tar cfvz /tmp/keys_$2.tar.gz ca.crt ta.key $2.crt $2.key

        mutt -s "`hostname` Keys for $2" \
            -a $KEY_DIR/ca.crt -a $KEY_DIR/ta.key \
            -a $KEY_DIR/$2.crt -a $KEY_DIR/$2.key \
            -a /tmp/keys_$2.tar.gz \
            -- $KEY_MAIL << _EOF_

        Keys for $2;

_EOF_

        rm -f /tmp/keys_$2.tar.gz >/dev/null 2>/dev/null

    ;;
    getkey)
        if test $# -ne 2; then
            echo "usage: $0 getkey <name>";
            exit 1
        fi

        if [ ! -f $KEY_DIR/$2.key ]; then
            echo "key not exist $2.key"
            exit 1
        fi

        cd $KEY_DIR && \
        tar cfvz /tmp/keys_$2.tar.gz ca.crt ta.key $2.crt $2.key

        mutt -s "`hostname` Keys for $2" \
            -a $KEY_DIR/ca.crt -a $KEY_DIR/ta.key \
            -a $KEY_DIR/$2.crt -a $KEY_DIR/$2.key \
            -a /tmp/keys_$2.tar.gz \
            -- $KEY_MAIL << _EOF_

        Keys for $2;

_EOF_

        rm -f /tmp/keys_$2.tar.gz >/dev/null 2>/dev/null
    ;;
    revoke)
        if test $# -ne 2; then
            echo "usage: $0 revoke <name>";
            exit 1
        fi

        export KEY_HOST=$2.${DOMAIN}

        cd $KEY_DIR
        rm -f $RT
        # revoke key and generate a new CRL
        openssl ca -revoke $2.crt -config $KEY_CONFIG
        # generate a new CRL
        openssl ca -gencrl -out $CRL -config $KEY_CONFIG
        cat ca.crt $CRL >$RT
        # verify the revocation
        openssl verify -CAfile $RT -crl_check $2.crt
    ;;
    unrevoke)
        if test $# -ne 2; then
            echo "usage: $0 unrevoke <name>";
            exit 1
        fi
    
        export KEY_HOST=$2.${DOMAIN}

        cd $KEY_DIR
            rm -f $RT

        # generate a new CRL
        openssl ca -gencrl -out $CRL -config $KEY_CONFIG
        cat ca.crt $CRL >$RT
        # verify the revocation
        openssl verify -CAfile $RT -crl_check $2.crt
    ;;
esac
