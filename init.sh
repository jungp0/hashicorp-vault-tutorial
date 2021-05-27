#!/bin/bash
touch keys
if [[ ! -s keys ]]
then
    echo "init..."
    vault operator init -key-shares=3 -key-threshold=2 > keys
fi
vault operator unseal $(cat keys | grep -i key | sed -n 1p | cut -d ':' -f2 | tr -d ' ')
vault operator unseal $(cat keys | grep -i key | sed -n 2p | cut -d ':' -f2 | tr -d ' ')
vault login $(cat keys | grep -i token | sed -n 1p | cut -d ':' -f2 | tr -d ' ')
echo -e "---------------------------------------------------------"
cat keys
