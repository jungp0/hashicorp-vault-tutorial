# Instructions to set up a HashiCorp secret engine

## Contents

- [Installization](#Installization)
- [Initialization](#initialization)
- [Unseal](#unseal)
- [Docker Implementation](#docker-implementation)

## Installization

<https://learn.hashicorp.com/tutorials/vault/getting-started-install?in=vault/getting-started>

*Note*: Remember to check `Path` if using Windows

## Initialization

Create `config.hcl` on the host server to sepcify the storage and listener settings

```dotnetcli
storage "file" {
  path = "vault-data"
}

listener "tcp" {
  tls_disable = "true"
}
```

Here is a more detailed version:

```dotnetcli
storage "raft" {
  path    = "./vault/data"
  node_id = "node1"
}

listener "tcp" {
  address     = "http://127.0.0.1:8200"
  tls_disable = "true"
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
ui = true
```

Those are the primary configurations:

- **storage** - This is the physical backend that Vault uses for storage. Up to this point the dev server has used "inmem" (in memory), but the example above uses integrated storage (raft), a much more production-ready backend.

- **listener** - One or more listeners determine how Vault listens for API requests. The example above listens on localhost port 8200 without TLS. In your environment set VAULT_ADDR=`http://127.0.0.1:8200` so the Vault client will connect without TLS.

    *Note*: keep `tls_disable` false in real practices

- **api_addr** - Specifies the address to advertise to route client requests.

- **cluster_addr** - Indicates the address and port to be used for communication between the Vault nodes in a cluster.

- **disable_mlock** (bool: false) – Disables the server from executing the mlock syscall. mlock prevents memory from being swapped to disk.

    *Note*: Disabling mlock is strongly recommended if using integrated storage due to the fact that mlock does not interact well with memory mapped files such as those created by BoltDB, which is used by Raft to track state. When using mlock, memory-mapped files get loaded into resident memory which causes Vault's entire dataset to be loaded in-memory and cause out-of-memory issues if Vault's data becomes larger than the available RAM. In this case, even though the data within BoltDB remains encrypted at rest, swap should be disabled to prevent Vault's other in-memory sensitive data from being dumped into disk.

The config.hcl file stores the configuration information. Based on config.hcl, you can setup the secret engine on the host server. If you prefer to use CLI, you can either set environment variable `VAULT_ADDR` to the server IP address or add `-address=$VAULT_ADDR` after the subcommand.

CLI:

```dotnetcli
export VAULT_ADDR='http:127.0.0.1:8200'
vault server -config=config.hcl
```

or

```dotnetcli
vault server -config=config.hcl -address='http:127.0.0.1:8200'
```

*Note*: No API option for this step

Example output:

```dotnetcli
==> Vault server configuration:

             Api Address: http://127.0.0.1:8200
                     Cgo: disabled
         Cluster Address: https://127.0.0.1:8201
              Go Version: go1.16.2
              Listener 1: tcp (addr: "127.0.0.1:8200", cluster address: "127.0.0.1:8201", max_request_duration: "1m30s", max_request_size: "33554432", tls: "disabled")
               Log Level: info
                   Mlock: supported: true, enabled: true
           Recovery Mode: false
                 Storage: raft (HA available)
                 Version: Vault v1.7.0
             Version Sha: 4e222b85c40a810b74400ee3c54449479e32bb9f

==> Vault server started! Log data will stream in below:
```

*Note*: Mlock may be missed in some OS, it is better to set it up for security concern. Otherwise, hackers can read the secret because the info may leak to local memory.

The server is initializedf:

API:

```dotnetcli
curl \
    --request POST \
    --data '{"secret_shares": 1, "secret_threshold": 1}' \
    http://127.0.0.1:8200/v1/sys/init | jq
```

Example output: (`keys_base64` is the unseal key)

```dotnetcli
{
  "keys": [
    "af3f49b1793a4200f0e52f045d4688972d933a744e7d6bbe8c9878537c5b39b1"
  ],
  "keys_base64": [
    "rz9JsXk6QgDw5S8EXUaIly2TOnROfWu+jJh4U3xbObE="
  ],
  "root_token": "s.4fypdoPS6BEwQ5YppD44SfTA"
}
```

CLI:

```dotnetcli
vault operator init \
-key-shares=3 \
-key-threshold=2
```

Example output:

```dotnetcli
Unseal Key 1: 4jYbl2CBIv6SpkKj6Hos9iD32k5RfGkLzlosrrq/JgOm
Unseal Key 2: B05G1DRtfYckFV5BbdBvXq0wkK5HFqB9g2jcDmNfTQiS
Unseal Key 3: Arig0N9rN9ezkTRo7qTB7gsIZDaonOcc53EHo83F5chA

Initial Root Token: s.KkNJYWF5g0pomcCLEmDdOVCW

Vault initialized with 3 key shares and a key threshold of 2. Please securely
distribute the key shares printed above. When the Vault is re-sealed,
restarted, or stopped, you must supply at least 2 of these keys to unseal it
before it can start servicing requests.

Vault does not store the generated master key. Without at least 3 key to
reconstruct the master key, Vault will remain permanently sealed!

It is possible to generate new unseal keys, provided you have a quorum of
existing unseal keys shares. See "vault operator rekey" for more information.
```

The initialization step can take 2 optional parameters: shares and threshold. (default 5 shares and 3 threshold)

- **shares**: the number of generated unsealed keys
- **threshold**: the minimum keys required to unseal the secret engine

*Note*: the generated unseal keys must be securely kept

## Unseal

When the vault is just initialized, it is sealed and unable to be accessed. You can use the unseal key to unseal the vault. In the previous CLI example, you need 2 unseal keys(corresponding to the threshold).

The unseal operation can be completed by CLI or API. If you use CLI to unseal the vault, you need to login in advance. Each example indicates the one unseal key contribution. To complete the unsealing, you may need to repeat the step.

CLI:

```dotnetcli
vault operator unseal /ye2PeRrd/qruh9Ppu9EyUjk1vLqIflg1qqw6w9OE5E=
```

API:

```dotnetcli
curl \
    --request POST \
    --data '{"key": "/ye2PeRrd/qruh9Ppu9EyUjk1vLqIflg1qqw6w9OE5E="}' \
    http://127.0.0.1:8200/v1/sys/unseal | jq
```

When you successfully login, the token will be stored locally at `~/.vault-token`

***

## Docker implementation

The secret engine needs a configuratoin file to know how to build itself. You can create a `config.hcl` file to specifiy

```dotnetcli
touch config.hcl
cat > config.hcl << EOF
storage "file" {
  path = "/vault-data"
}

listener "tcp" {
  tls_disable = "true"
}
ui = true
disable_mlock=true
EOF
```

*Note*: The address under tcp is set in DOCKERFILE as an environment variable.

To create a linux docker image, you need to write a Dockerfile locally

CLI:

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
//COPY vault /usr/bin
COPY init.sh .
ENV VAULT_ADDR="http://0.0.0.0:8200"
CMD vault server -config=config.hcl
EXPOSE 8200/tcp
```

Right now, the docker config file is completed. You need to build the docker image. You can replace `dockv` to any other *image name* you prefer

```dotnetcli
docker build -t dockv .
```

*Note*: ABBGLOBAL doesn't  allow the connection to the alpine website

You can see the images created by

```dotnetcli
docker images
```

Sample ouput:

```dotnetcli
REPOSITORY   TAG       IMAGE ID       CREATED       SIZE
dockv        latest    cca66b32b9fd   3 hours ago   24.1MB
```

Then run the image to create a container instance. Replace `dockv-test` to your *container name*, and `dockv` to your *image name*

```dotnetcli
docker run --name dockv-test -dt -p 8200:8200 dockv
```

The command above creates a container run on the background and you need to close it manually. If you only want to test it temporarily, you can try this

```dotnetcli
docker run --name dockv-test -it dockv
```

The the meaning of those configurations is listed below:

- **-d** datached on the background
- **-i** interactive
- **-t** terminal typing style

If you choose to run the container on the background, you will need the following command to get in the bash shell

```dotnetcli
docker exec -it dockv-test /bin/bash
```

*Note*: the command above can not be run in the Git Bash; Windows users need to run it in the power shell. If you are wondering how to run it in Git Bash, I found the solution as below

Git Bash:

```dotnetcli
(winpty) docker exec -it dockv-test ./bin/bash
```

### CLI

Initialize the server by specifing the key-shares and key-threshold

```dotnetcli
vault operator init \
-key-shares=3 \
-key-threshold=2
```

You should get the response like

```dotnetcli
Unseal Key 1: TtYt/olbGzr2RXNc0QDR2uRtaZaznrRgLU2pk9SEPdcD
Unseal Key 2: PA5x5iIyr9Eo3+KfhNSCBlmxiS6oHhXnvfi3kfs0fAFZ
Unseal Key 3: y1IiVZpD3cUeCZlFXFwwFqChMIguXRPd1Zlut0wKw69g

Initial Root Token: s.DqXcpH9l85vwAuXxW1SmTyFs
```

Securely keep the keys and the token in another place carefully.

You will need the unseal keys to unseal the vault

```dotnetcli
vault operator unseal TtYt/olbGzr2RXNc0QDR2uRtaZaznrRgLU2pk9SEPdcD

vault operator unseal PA5x5iIyr9Eo3+KfhNSCBlmxiS6oHhXnvfi3kfs0fAFZ
```

*Note*: You will need two keys to unseal the vault. In practice, the two operations should be executed by two seperate persons.

Then use the token you got with the keys to log in the vault

```dotnetcli
vault login s.DqXcpH9l85vwAuXxW1SmTyFs
```

If you got the response below, you have successfully logged in

```dotnetcli
Key                  Value
---                  -----
token                s.DqXcpH9l85vwAuXxW1SmTyFs
token_accessor       R0rCyedYCqcyAU0cAxbj7SBK
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```

*Note*: If you set the environment `VAULT_TOKEN` as `s.DqXcpH9l85vwAuXxW1SmTyFs`, it has the same effect of login:

```dotnetcli
export VAULT_TOKEN="s.DqXcpH9l85vwAuXxW1SmTyFs"
```

But you will need to use unset command to exit, and you cannot use login to switch the token if `VAULT_TOKEN` is set

```dotnetcli
unset VAULT_TOKEN
```

If you want to reseal the vault, simply use the command

```dotnetcli
vault operator seal
```

Enable authentication method: AppRole

```dotnetcli
vault auth enable -output-curl-string approle
```

### API

You can use HTTP request to finsh the previous steps

```dotnetcli
curl \
    --request POST \
    --data '{"secret_shares": 1, "secret_threshold": 1}' \
    http://127.0.0.1:8200/v1/sys/init | jq
```

Example output: (`keys_base64` is the unseal key)

```dotnetcli
{
  "keys": [
    "af3f49b1793a4200f0e52f045d4688972d933a744e7d6bbe8c9878537c5b39b1"
  ],
  "keys_base64": [
    "rz9JsXk6QgDw5S8EXUaIly2TOnROfWu+jJh4U3xbObE="
  ],
  "root_token": "s.4fypdoPS6BEwQ5YppD44SfTA"
}
```

Set the environment variable VAULT_TOKEN to prove the accessibility

```dotnetcli
export VAULT_TOKEN="s.4fypdoPS6BEwQ5YppD44SfTA"
```

Unseal

```dotnetcli
curl \
    --request POST \
    --data '{"key": "/ye2PeRrd/qruh9Ppu9EyUjk1vLqIflg1qqw6w9OE5E="}' \
    http://127.0.0.1:8200/v1/sys/unseal | jq
```

Enable authentication method: AppRole

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"type": "approle"}' \
    http://127.0.0.1:8200/v1/sys/auth/approle
```

Write a set of [policies](https://www.vaultproject.io/docs/concepts/policies)

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request PUT \
    --data '{"policy":"# Dev servers have version 2 of KV secrets engine mounted by default, so will\n# need these paths to grant permissions:\npath \"secret/data/*\" {\n  capabilities = [\"create\", \"update\"]\n}\n\npath \"secret/data/foo\" {\n  capabilities = [\"read\"]\n}\n"}' \
    http://127.0.0.1:8200/v1/sys/policies/acl/my-policy
```

The policy specifies the permission under directory of secret/data. However, it haven't existed yet. You need to create the secret engine at secret/

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{ "type":"kv-v2" }' \
    http://127.0.0.1:8200/v1/sys/mounts/secret
```

The following command specifies the token issued under the AppRole `my-role` should be applied by the policy of `my-policy` created before

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"policies": ["my-policy"]}' \
    http://127.0.0.1:8200/v1/auth/approle/role/my-role
```

The AppRole auth method expects a RoleID and a SecretID as its input. The RoleID is similar to a username and the SecretID can be thought as the RoleID's password.

The following command fetches the RoleID of the role named `my-role`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
     http://127.0.0.1:8200/v1/auth/approle/role/my-role/role-id | jq -r ".data"
```

The response will include the role_id

```dotnetcli
{
  "role_id": "3c301960-8a02-d776-f025-c3443d513a18"
}
```

To create a new SecretID under `my-role`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    http://127.0.0.1:8200/v1/auth/approle/role/my-role/secret-id | jq -r ".data"
```

The response will include the secret_id

```dotnetcli
{
  "secret_id": "22d1e0d6-a70b-f91f-f918-a0ee8902666b",
  "secret_id_accessor": "726ab786-70d0-8cc4-e775-c0a75070e5e5",
  "secret_id_ttl": 0
}
```

Those two credentials can be used to create a new token at the login endpoint

```dotnetcli
curl --request POST \
       --data '{"role_id": "3c301960-8a02-d776-f025-c3443d513a18", "secret_id": "22d1e0d6-a70b-f91f-f918-a0ee8902666b"}' \
       http://127.0.0.1:8200/v1/auth/approle/login | jq -r ".auth"
```

The response would be like

```dotnetcli
{
  "client_token": "s.p5NB4dTlsPiUU94RA5IfbzXv",
  "accessor": "EQTlZwOD4yIFYWIg5YY6Xr29",
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
  "entity_id": "4526701d-b8fd-3c39-da93-9e17506ec894",
  "token_type": "service",
  "orphan": true
}
```

The `client token` can be used to authenticate with vault under `my-policy`

You can create a secret named `creds` with a key `password` and its vaule set to `my-long-password`

```dotnetcli
curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{ "data": {"password": "my-long-password"} }' \
    http://127.0.0.1:8200/v1/secret/data/creds | jq -r ".data"
```

You should receive

```dotnetcli
{
  "created_time": "2020-02-05T16:51:34.0887877Z",
  "deletion_time": "",
  "destroyed": false,
  "version": 1
}
```

You can log out by unseting the environment variable if you are using the terminal

```dotnetcli
unset VAULT_TOKEN
```

export key1=$(cat key | grep -i key | sed -n 1p | cut -d ':' -f2 | tr -d ' ')

replace `1p` to `np` for the nth key

export token=$(cat key | grep -i token | sed -n 1p | cut -d ':' -f2 | tr -d ' ')

It is important to use `eval cat` to write the bash script with variables. The variable also need to be prefixed by `/$` rather than `$`

```dotnetcli
eval cat > init.sh <<EOF
#!/bin/bash
touch keys
if [[ ! -s keys ]]
then
    echo "init..."
    vault operator init -key-shares=3 -key-threshold=2 > keys
fi
export vault_key1=\$(cat keys | grep -i key | sed -n 1p | cut -d ':' -f2 | tr -d ' ')
export vault_key2=\$(cat keys | grep -i key | sed -n 2p | cut -d ':' -f2 | tr -d ' ')
export vault_token=\$(cat keys | grep -i token | sed -n 1p | cut -d ':' -f2 | tr -d ' ')
vault operator unseal \$vault_key1
vault operator unseal \$vault_key2
vault login \$vault_token
EOF
```
