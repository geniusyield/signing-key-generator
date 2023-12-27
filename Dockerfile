FROM ghcr.io/blinklabs-io/cardano-node:8.1.2 as cardano-node

# Install cardano-address binary:
RUN wget https://github.com/IntersectMBO/cardano-addresses/releases/download/3.12.0/cardano-addresses-3.12.0-linux64.tar.gz -O /cardano-addresses.tar.gz &&\
    tar xvfz cardano-addresses.tar.gz &&\
    chmod +x /bin/cardano-address

# Install cardano-wallet binaries:

RUN wget https://github.com/cardano-foundation/cardano-wallet/releases/download/v2023-12-18/cardano-wallet-v2023-12-18-linux64.tar.gz -O /cardano-wallet.tar.gz &&\
    tar xvfz /cardano-wallet.tar.gz &&\
    cp /cardano-wallet-v2023-12-18-linux64/bech32 /bin/bech32 &&\
    chmod +x /bin/bech32

COPY generate.sh generate.sh
RUN chmod +x generate.sh

ENTRYPOINT ["/generate.sh"]

