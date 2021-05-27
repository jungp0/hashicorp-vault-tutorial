FROM ubuntu:latest
RUN apt-get update && apt-get install -y \
net-tools
RUN mkdir /vault-data
COPY config.hcl .
COPY vault /usr/bin
COPY init.sh .
ENV VAULT_ADDR="http://0.0.0.0:8200"
CMD vault server -config=config.hcl
EXPOSE 8200/tcp