# Tutorial to use the hashicorp vault engine

## Write the config file for vault engine

The config.hcl is used to specify the configuration of the vault engine server

```dotnetcli
storage "file" { 
  path = "/vault-data" 
} 
listener "tcp" { 
  address = "0.0.0.0:8200"
  tls_disable = "true" 
} 
ui = true 
disable_mlock=true 
```

It is a sample config file. Those are the primary configurations:

- **storage** - This is the physical backend that Vault uses for storage. Up to this point the dev server has used "inmem" (in memory), but the example above uses integrated storage (raft), a much more production-ready backend.

- **listener** - One or more listeners determine how Vault listens for API requests. The example above listens on localhost port 8200 without TLS. **If you want to change the port, you need to change the environment variable `VAULT_ADDR` to the same vaule in the `DOCKERFILE` mentioned later.**

    *Note*: keep `tls_disable` false in real practices

- **api_addr** - Specifies the address to advertise to route client requests.

- **cluster_addr** - Indicates the address and port to be used for communication between the Vault nodes in a cluster.

- **disable_mlock** (bool: false) – Disables the server from executing the mlock syscall. mlock prevents memory from being swapped to disk.

    *Note*: Disabling mlock is strongly recommended if using integrated storage due to the fact that mlock does not interact well with memory mapped files such as those created by BoltDB, which is used by Raft to track state. When using mlock, memory-mapped files get loaded into resident memory which causes Vault's entire dataset to be loaded in-memory and cause out-of-memory issues if Vault's data becomes larger than the available RAM. In this case, even though the data within BoltDB remains encrypted at rest, swap should be disabled to prevent Vault's other in-memory sensitive data from being dumped into disk.

## Write the Dockerfile for docker image

Dockerfile specify the OS of the image by `FROM` as a version control tool. It also adds the scrips and vault library to the image. `ENV` sets the environment variable VAULT_ADDR the same as tcp listener address. You may not need to change the sample configuration below

```dotnetcli
FROM ubuntu:latest
RUN mkdir /vault-data
COPY config.hcl .
COPY vault /usr/bin
COPY init.sh .
ENV VAULT_ADDR="http://0.0.0.0:8200"
CMD vault server -config=config.hcl
EXPOSE 8200/tcp
```

You may need to download the vault library for linux from <https://releases.hashicorp.com/vault/1.4.2/vault_1.4.2_linux_amd64.zip> and unzip the file `vault` to the current directory(the same position as Dockerfile and config.hcl)

If you don't mind to let the docker deal with the download and unzip process, you can try the Dockerfile below. However, it will take extra 200MB space to install essential tools

```dotnetcli
FROM ubuntu:latest
RUN apt-get update && apt-get install -y \
    wget \
    zip
RUN wget https://releases.hashicorp.com/vault/1.4.2/vault_1.4.2_linux_amd64.zip
RUN unzip vault_1.4.2_linux_amd64.zip
RUN mv vault /usr/bin/
RUN rm vault_1.4.2_linux_amd64.zip

RUN mkdir /vault-data
COPY config.hcl .
COPY init.sh .
ENV VAULT_ADDR="http://0.0.0.0:8200"
CMD vault server -config=config.hcl
EXPOSE 8200/tcp
```

## Write the initalization script

The sample script `init.sh` specify the secret engine with 3 keys and you need at least 2 keys to unseal the vault. You can change the number depending on the condition

If you want to add more keys, change the arguements of `vault operator init`: `-key-shares=3` and `-key-threshold=2`. `key-shares` should not be smaller than `key-threshold`. You also need to copy and paste the `vault operator unseal`, and replace `sed -n 2p` to `sed -n 3p`, etc.

Overall, you need to unseal with the number of keys as specified by the `key-threshold`.

The code of init.sh:

```dotnetcli
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
echo -e "--------------------"
cat keys
```

The end of script will print the keys and root token. Keep them stored carefully somewhere else. In practice, you need to delete the file `keys` and store the engine info in a secure place.

If you write the script on your own, remember to offer permission to execute it

```dotnetcli
chmod +x init.sh
```

## Build the docker image and run the container

With the script `build.sh`, you can build the docker image, run the container and shell in the docker bash

***Note***: run the script in `Git Bash` rather than `cmd` or `power shell`

The code of `build.sh`:

```dotnetcli
#!/bin/bash
if [[ $# -le 1 ]]
then
    echo -e "The docker image name:"
    read image_name
    docker build -t $image_name .
    echo -e "---------------------------\nThe docker container name:"
    read container_name
    if [[ $# -eq 0 ]]
    then
        docker run --name $container_name -dp 80:8200 $image_name
    else
        docker run --name $container_name -dp $1:8200 $image_name
    fi
    docker exec -it $container_name ./bin/bash
else
    docker build -t $1 .
    if [[ $# -eq 2 ]]
    then
        docker run --name $2 -dp 80:8200 $1
    else
        docker run --name $2 -dp $3:8200 $1
    fi
    docker exec -it $2 ./bin/bash
fi
```

If you create the script by your own, remember to offer permission to execute it

```dotnetcli
chmod +x build.sh
```

Run the script, and the arguments are optional. The default port is 80. If you don't pass the image name and container name, you can specify them when the script is runnig

```dotnetcli
./build.sh

./build.sh [port]

./build.sh [image name] [container name]

./build.sh [image name] [container name] [port]
```

## Initialize the engine

After the execution of build.sh, you should have been into the bash of the engine. You can run the init.sh to initialize the server that generate the keys and root token

```dotnetcli
./init.sh
```

As mentioned before, securely keep the keys and token. The vault should have been unsealed.

You can reseal the vault by

```dotnetcli
vault operator seal
```

To unseal the vault in the future, you can rerun the init.sh, or run the command

```dotnetcli
vault operator unseal $unseal_key
```

You also need to repeat several times as the same as `key-threshold`. This step can also be implemented by API that will be introduced later.

## Exit the engine bash

You can type `exit` to exit or simply press `ctrl+z`

When you exit the bash, the container is still running in background. You can check it by

```dotnetcli
docker ps
```

The state and port info will be shown as well.

When you want to access the engine in the docker from outside, you need to set your environment vairable as `http://0.0.0.0:$port`, the `port` is the value you specified at build stage. The default value should be 80

```dotnetcli
export VAULT_ADDR="http://0.0.0.0:80"
```

You also need a token to login. You can use the root token, or created token as introduced below

```dotnetcli
vault login s.jVFBWDMeYa4ZMQ85RASYKGkk
```

## Creat vault policies

Enable authentication method: AppRole

*Note*: the URL can not be 0.0.0.0. You can use either localhost or 127.0.0.1, which is the loopback address of your local host

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"type": "approle"}' \
    http://127.0.0.1:80/v1/sys/auth/approle
```

Write a set of [policies](https://www.vaultproject.io/docs/concepts/policies)

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request PUT \
    --data '{"policy":"path \"secret/data/*\" {\n  capabilities = [\"create\", \"update\"]\n}\n\npath \"secret/data/foo\" {\n  capabilities = [\"read\"]\n}\n"}' \
    http://127.0.0.1:80/v1/sys/policies/acl/my-policy
```

The policy specifies the permission under directory of `secret/`. However, it haven't existed yet. You need to create the secret engine `secret/`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{ "type":"kv-v2" }' \
    http://127.0.0.1:80/v1/sys/mounts/secret
```

The following command creates a new role called `my-role` and specifies the token issued under `my-role` should be applied by the policy of `my-policy`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"policies": ["my-policy"]}' \
    http://127.0.0.1:80/v1/auth/approle/role/my-role
```

The AppRole auth method expects a RoleID and a SecretID to issue a token. The RoleID is similar to a username and the SecretID can be thought as the RoleID's password.

The following command fetches the RoleID of `my-role`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
     http://127.0.0.1:80/v1/auth/approle/role/my-role/role-id | jq -r ".data"
```

The response will include the role_id

```dotnetcli
{
  "role_id": "9546663a-e013-a4be-29f5-762a337388b9"
}
```

Generate a new SecretID under `my-role`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    http://127.0.0.1:80/v1/auth/approle/role/my-role/secret-id | jq -r ".data"
```

The response will include the secret_id

```dotnetcli
{
  "secret_id": "24a44d54-ad8e-b02a-935c-8dec75b09d32",
  "secret_id_accessor": "500dc412-8eb5-a1aa-eb4f-484ff31747ff"
}
```

Those two credentials can be used to create a new token at the login endpoint

```dotnetcli
curl --request POST \
       --data '{"role_id": "9546663a-e013-a4be-29f5-762a337388b9", "secret_id": "24a44d54-ad8e-b02a-935c-8dec75b09d32"}' \
       http://127.0.0.1:80/v1/auth/approle/login | jq -r ".auth"
```

The response would be like

```dotnetcli
{
  "client_token": "s.jDwrDgDUJ2jfKn0Ek7fUq50B",
  "accessor": "op9sKY3F61tp5oKIiD1aM7e8",
  "policies": [
    "default",
    "my-policy"
  ],
  "token_policies": [
    "default",
    "my-policy"
  ],
  "metadata": {
    "role_name": "my-role"
  },
  "lease_duration": 2764800,
  "renewable": true,
  "entity_id": "71e0bfd3-e3e7-f05f-85cd-d2c841d08c2c",
  "token_type": "service",
  "orphan": true
}
```

The `client token` can be used to authenticate with vault under `my-policy`

## API interaction

Before switch to the new token, you can try to interact with the vault by [API](https://www.vaultproject.io/api-docs/secret/kv/kv-v2) with root privilege

*Note*: We use the k/v version 2 to interact

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{ "data": {"url": "http://mywebsite.com/abc"} }' \
    http://127.0.0.1:80/v1/secret/data/foo | jq -r ".data"
```

Then you can list the entry under `secret/`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request LIST \
    http://127.0.0.1:80/v1/secret/metadata | jq -r ".data"
```

Sample output:

```dotnetcli
{
  "keys": [
    "creds"
  ]
}
```

You can see `creds` is shown under `secret/metadata`. Generally, if you want to get/delete/create/update an entry, the path should be `engine_path/data/:path`; if you want to list the entries, the path should be `engine_path/metadata/:path`. You can check the [API](https://www.vaultproject.io/api-docs/secret/kv/kv-v2) for more details

Here are tricky examples to interact with vault with payload

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data @- \
    http://127.0.0.1:80/v1/secret/data/test/a << eof | jq -r ".data"
{
    "data": {
      "foo": "bar",
      "zip": "zap"
    }
}
eof
```

```dotnetcli
cat << eof | curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data @payload.json \
    http://127.0.0.1:80/v1/secret/data/test/a | jq -r ".data"
{
    "data": {
      "foo": "bar",
      "zip": "zap"
    }
}
eof
```

```dotnetcli
cat > payload.json << eof
{
    "data": {
      "foo": "bar",
      "zip": "zap"
    }
}
eof
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data @payload.json \
    http://127.0.0.1:80/v1/secret/data/test/a | jq -r ".data"
```

Those 3 methods are the same to the vault, and you can choose one based on your demands

You can list the entries under `secret/test/`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request LIST \
    http://127.0.0.1:80/v1/secret/metadata/test | jq -r ".data"
```

Get the key/secret in `secret/test/a`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request GET \
    http://127.0.0.1:80/v1/secret/data/test/a | jq -r ".data"
```

Sample response:

```dotnetcli
{
  "data": {
    "foo": "bar",
    "zip": "zap"
  },
  "metadata": {
    "created_time": "2021-05-27T06:52:15.7473318Z",
    "deletion_time": "",
    "destroyed": false,
    "version": 3
  }
}
```

The `metadata` tells the created time, and modified times(version). The version can also be used to realize version control like rolling back. You can change the version control settings by update metadata (Check [API](https://www.vaultproject.io/api-docs/secret/kv/kv-v2)).

If you don't want to get the metadata in the response, you can modify the command as

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request GET \
    http://127.0.0.1:80/v1/secret/data/test/a | jq -r ".data.data"
```

Sample response:

```dotnetcli
{
  "foo": "bar",
  "zip": "zap"
}
```

If you don't know `jq`, you may still find the string after `-r` specifies the object in the json response: `res.data.data`. You can modify it depends on your demands

To delete the entry, replace DELETE to GET in the RETS command

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request DELETE \
    http://127.0.0.1:80/v1/secret/data/test/a
```

This request has no response. If you list the entries under `secret/test`, you should find `a` is still there. However, if you try to get `a`, the response is

```dotnetcli
{
  "data": null,
  "metadata": {
    "created_time": "2021-05-27T07:19:36.9940852Z",
    "deletion_time": "2021-05-27T07:19:52.4875828Z",
    "destroyed": false,
    "version": 4
  }
}
```

You can see the data is deleted, but the entry is still there. As we talked before, the version control system keeps the entry after the deletion. You can still roll back to previous version

If you rewrite the data, `created_time` will be updated; `deletion_time` will be empty; `version` will increase by one

## Token under policies constraint

You can switch to the new token and check the permission under `my-policy`

```dotnetcli
export VAULT_TOKEN=s.jDwrDgDUJ2jfKn0Ek7fUq50B
```

Here is a quick remind of `my-policy`

```dotnetcli
{"policy":
"path \"secret/data/*\" {
  capabilities = [\"create\", \"update\"]
}

path \"secret/data/foo\" {
  capabilities = [\"read\"]
}"
}
```

You can create a secret under `creds` with a key `password` and its vaule set to `my-long-password` in `secret/creds`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{ "data": {"password": "my-long-password"} }' \
    http://127.0.0.1:80/v1/secret/data/creds | jq -r ".data"
```

You should receive

```dotnetcli
{
  "created_time": "2021-05-27T01:24:07.7979282Z",
  "deletion_time": "",
  "destroyed": false,
  "version": 1
}
```

If you try to access the secrets under creds, you will get `null`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request GET \
    http://127.0.0.1:80/v1/secret/data/creds | jq -r ".data"
```

If you resend the request without jq, you see the error message

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request GET \
    http://127.0.0.1:80/v1/secret/data/creds

{"errors":["1 error occurred:\n\t* permission denied\n\n"]}
```

It is because the new token is permitted to create, but not to read entries or list path under `secret/`. One exception is that you can read `secret/foo`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request GET \
    http://127.0.0.1:80/v1/secret/data/foo | jq -r ".data"
```

Sample response:

```dotnetcli
{
  "data": {
    "url": "http://mywebsite.com/abc"
  },
  "metadata": {
    "created_time": "2021-05-27T03:10:17.4148797Z",
    "deletion_time": "",
    "destroyed": false,
    "version": 1
  }
}
```

## Log out

You can log out by unseting the environment variable if you are using the terminal

```dotnetcli
unset VAULT_TOKEN
```
