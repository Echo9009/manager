#!/bin/bash

set -e

EVENT="{{ event_name }}"
AWG_MANAGER="/etc/amnezia/amneziawg/awg-manager.sh"
CONF_DIR="/etc/amnezia/amneziawg"
SESSION_ID="{{ user.gen_session.id }}"
API_URL="{{ config.api.url }}"

echo "EVENT=$EVENT"

case $EVENT in
    INIT)
        echo
        echo "Init"
        sudo bash -c "$(curl -sL https://raw.githubusercontent.com/bkeenke/awg-manager/master/init.sh)" @ install >> /dev/null
        echo
        SERVER_HOST="{{ server.settings.host_name }}"
        if [ -z $SERVER_HOST ]; then
            SERVER_HOST="{{ server.settings.host }}"
        fi
        echo "Check domain: $API_URL"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $API_URL/shm/v1/test)
        if [ $HTTP_CODE -ne '200' ]; then
            echo "ERROR: incorrect API URL: $API_URL"
            echo "Got status: $HTTP_CODE"
            exit 1
        fi
        echo
        mkdir -p $CONF_DIR

        echo "Init server"
        chmod 700 $AWG_MANAGER
        $AWG_MANAGER -i -s $SERVER_HOST
        ;;
    CREATE)
        echo "Create new user"
        USER_CFG=$($AWG_MANAGER -u "{{ us.id }}" -c -p)
        echo "Upload user key to SHM"
        curl -s -XPUT \
            -H "session-id: $SESSION_ID" \
            -H "Content-Type: text/plain" \
            $API_URL/shm/v1/storage/manage/vpn{{ us.id }} \
            --data-binary "$USER_CFG"
        sleep 1
        ENCODE=$(cat $CONF_DIR/keys/{{ us.id }}/{{ us.id }}.vpn)
        curl -sk -XPUT \
            -H "session-id: $SESSION_ID" \
            -H "Content-Type: text/plain" \
            $API_URL/shm/v1/storage/manage/encode_{{ us.id }} \
            --data-binary "$ENCODE"
        echo "done"
        ;;
    ACTIVATE)
        echo "Activate user"
        $AWG_MANAGER -u "{{ us.id }}" -U
        echo "done"
        ;;
    BLOCK)
        echo "Block user"
        $AWG_MANAGER -u "{{ us.id }}" -L
        echo "done"
        ;;
    REMOVE)
        echo "Remove user"
        $AWG_MANAGER -u "{{ us.id }}" -d
        echo "Remove user key from SHM"
        curl -s -XDELETE \
            -H "session-id: $SESSION_ID" \
            $API_URL/shm/v1/storage/manage/vpn{{ us.id }}
        curl -s -XDELETE \
            -H "session-id: $SESSION_ID" \
            $API_URL/shm/v1/storage/manage/encode_{{ us.id }}
        echo "done"
        ;;
    *)
        echo "Unknown event: $EVENT. Exit."
        exit 0
        ;;
esac
