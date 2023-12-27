#!/bin/bash
set -Eeuo pipefail

CADDR=${CADDR:=$( which cardano-address )}
[[ -z "$CADDR" ]] && {
        echo "cardano-address cannot be found, exiting..." >&2 ;
        exit 127
}

CCLI=${CCLI:=$( which cardano-cli )}
[[ -z "$CCLI" ]] && {
        echo "cardano-cli cannot be found, exiting..." >&2
        exit 127
}

BECH32=${BECH32:=$( which bech32 )}
[[ -z "$BECH32" ]] && {
        echo "bech32 cannot be found, exiting..." >&2
        exit 127
}

function cardano-address-testnet-init() {
  NETWORK_TAG=testnet
  MAGIC="--testnet-magic 1097911063"
}

function cardano-address-mainnet-init() {
  NETWORK_TAG=mainnet
  MAGIC="--mainnet"
}

function cardano-address-create-wallet() {
  WALLET_DIR=/data
  ROOT_PRIV_KEY_FILE=${WALLET_DIR}/root.prv
  STAKE_XPRIV_KEY_FILE=${WALLET_DIR}/stake.xpr
  STAKE_XPUB_KEY_FILE=${WALLET_DIR}/stake.xpub
  STAKE_ADDRESS_FILE=${WALLET_DIR}/wallet.staking.addr
  STAKE_CERT_FILE=${WALLET_DIR}/wallet.staking.cert
  STAKE_ESKEY_FILE=${WALLET_DIR}/wallet.staking.eskey
  STAKE_SKEY_FILE=${WALLET_DIR}/wallet.staking.skey
  STAKE_EVKEY_FILE=${WALLET_DIR}/wallet.staking.evkey
  STAKE_VKEY_FILE=${WALLET_DIR}/wallet.staking.vkey
  PAYMENT_XPRV_KEY_FILE=${WALLET_DIR}/payment.xprv
  PAYMENT_XPUB_KEY_FILE=${WALLET_DIR}/payment.xpub
  PAYMENT_ADDRESS_FILE=${WALLET_DIR}/payment.addr
  PAYMENT_ESKEY_FILE=${WALLET_DIR}/wallet.payment.eskey
  PAYMENT_SKEY_FILE=${WALLET_DIR}/wallet.payment.skey
  PAYMENT_EVKEY_FILE=${WALLET_DIR}/wallet.payment.evkey
  PAYMENT_VKEY_FILE=${WALLET_DIR}/wallet.payment.vkey
  DELEGATION_ADDRESS_FILE=${WALLET_DIR}/delegation.addr
  BASE_ADDRESS_CANDIDATE_FILE=${WALLET_DIR}/base.addr_candidate
  BASE_ADDRESS_FILE=${WALLET_DIR}/base.addr

  if [ "${PHRASE:=}" == "" ]; then
    PHRASE=$(cardano-address recovery-phrase generate)
  fi

  if [ "${NETWORK:-mainnet}" == "mainnet" ]; then
    cardano-address-mainnet-init
  else
    cardano-address-testnet-init
  fi

  mkdir $WALLET_DIR

  # Generate root key from recovery phrase
  echo $PHRASE  | cardano-address key from-recovery-phrase Shelley > ${ROOT_PRIV_KEY_FILE}
  # Generate account keys
  cat ${ROOT_PRIV_KEY_FILE} | cardano-address key child 1852H/1815H/0H/0/0 > ${PAYMENT_XPRV_KEY_FILE}
  cat ${PAYMENT_XPRV_KEY_FILE} | cardano-address key public --with-chain-code | tee ${PAYMENT_XPUB_KEY_FILE} | \
    cardano-address address payment --network-tag ${NETWORK_TAG} > ${PAYMENT_ADDRESS_FILE}

  # cat ${PAYMENT_XPRV_KEY_FILE} | cardano-address key inspect > ${PAYMENT_SKEY_FILE}
  PSKEY=$(cat $ROOT_PRIV_KEY_FILE | cardano-address key inspect | jq -r .extended_key | cut -b -64)

  # Generate stake keys
  cat ${ROOT_PRIV_KEY_FILE} | cardano-address key child 1852H/1815H/0H/2/0 > ${STAKE_XPRIV_KEY_FILE}
  cat ${STAKE_XPRIV_KEY_FILE} | \
    cardano-address key public --with-chain-code | tee ${STAKE_XPUB_KEY_FILE} | \
    cardano-address address stake --network-tag ${NETWORK_TAG} > ${STAKE_ADDRESS_FILE}
  cat ${STAKE_XPRIV_KEY_FILE} | cardano-address key inspect > ${STAKE_SKEY_FILE}
  cat ${PAYMENT_XPRV_KEY_FILE} | \
    cardano-address key public --with-chain-code | \
    cardano-address address payment --network-tag ${NETWORK_TAG} | \
    cardano-address address delegation $(cat ${STAKE_XPRIV_KEY_FILE} | cardano-address key public --with-chain-code | tee ${STAKE_XPUB_KEY_FILE}) > ${BASE_ADDRESS_CANDIDATE_FILE}
  # Inspired by https://gist.github.com/ilap/5af151351dcf30a2954685b6edc0039b#script
  SESKEY=$( cat ${STAKE_XPRIV_KEY_FILE} | bech32 | cut -b -128 )$( cat ${STAKE_XPUB_KEY_FILE} | bech32)
  PESKEY=$( cat ${PAYMENT_XPRV_KEY_FILE} | bech32 | cut -b -128 )$( cat ${PAYMENT_XPUB_KEY_FILE} | bech32)

  cat << EOF2 > ${STAKE_ESKEY_FILE}
{
    "type": "StakeExtendedSigningKeyShelley_ed25519_bip32",
    "description": "",
    "cborHex": "5880$SESKEY"
}
EOF2

  cat << EOF3 > ${PAYMENT_ESKEY_FILE}
{
    "type": "PaymentExtendedSigningKeyShelley_ed25519_bip32",
    "description": "Payment Signing Key",
    "cborHex": "5880$PESKEY"
}
EOF3

  cat << EOF4 > ${PAYMENT_SKEY_FILE}
{

    "type": "PaymentSigningKeyShelley_ed25519",
    "description": "Payment Signing Key",
    "cborHex": "5820$PSKEY"
}
EOF4

  cardano-cli key verification-key --signing-key-file ${STAKE_ESKEY_FILE} --verification-key-file ${STAKE_EVKEY_FILE}
  cardano-cli key verification-key --signing-key-file ${PAYMENT_ESKEY_FILE} --verification-key-file ${PAYMENT_EVKEY_FILE}

  cardano-cli key non-extended-key --extended-verification-key-file ${STAKE_EVKEY_FILE} --verification-key-file ${STAKE_VKEY_FILE}
  cardano-cli key non-extended-key --extended-verification-key-file ${PAYMENT_EVKEY_FILE} --verification-key-file ${PAYMENT_VKEY_FILE}

  cardano-cli stake-address build --stake-verification-key-file ${STAKE_VKEY_FILE} $MAGIC > ${STAKE_ADDRESS_FILE}
  cardano-cli stake-address registration-certificate --stake-verification-key-file ${STAKE_VKEY_FILE} --out-file ${STAKE_CERT_FILE}
  cardano-cli address build --payment-verification-key-file ${PAYMENT_VKEY_FILE} $MAGIC > ${PAYMENT_ADDRESS_FILE}
  cardano-cli address build \
      --payment-verification-key-file ${PAYMENT_VKEY_FILE} \
      --stake-verification-key-file ${STAKE_VKEY_FILE} \
      $MAGIC > ${BASE_ADDRESS_FILE}

  echo "========================[RECOVERY PHRASE]========================================"
  echo $PHRASE
  echo "========================[CARDANO NETWORK]========================================"
  echo $NETWORK_TAG | tr '[:lower:]' '[:upper:]'
  echo "========================[PAYMENT ADDRESS]========================================"
  cat $PAYMENT_ADDRESS_FILE
  echo
  echo "======================[PAYMENT SIGNING KEY]======================================"
  cat $PAYMENT_SKEY_FILE | jq
  echo "===================[PAYMENT SIGNING KEY CBOR HEX]======================================"
  cat $PAYMENT_SKEY_FILE | jq -r ".cborHex"
  echo "===================[EXTENDED PAYMENT SIGNING KEY]=================================="
  cat $PAYMENT_ESKEY_FILE | jq
  echo "=====================[PAYMENT VERIFICATION KEY]=================================="
  cat $PAYMENT_VKEY_FILE | jq

  # Clean up and wipe all the data:
  PHRASE=""
  rm -rf $WALLET_DIR
}

function generate-random-wallet-keys() {
  WALLET_DIR=/data
  mkdir $WALLET_DIR

  if [ "${NETWORK:-mainnet}" == "mainnet" ]; then
    cardano-address-mainnet-init
  else
    cardano-address-testnet-init
  fi

  cardano-cli address key-gen \
    --verification-key-file $WALLET_DIR/key.vkey \
    --signing-key-file $WALLET_DIR/key.skey

  cardano-cli address build \
    --payment-verification-key-file $WALLET_DIR/key.vkey \
    --out-file $WALLET_DIR/payment.addr \
    $MAGIC

  echo "========================[CARDANO NETWORK]========================================"
  echo $NETWORK_TAG | tr '[:lower:]' '[:upper:]'
  echo "============================[ADDRESS]============================================="
  cat $WALLET_DIR/payment.addr
  echo
  echo "=======================[PAYMENT SIGNING KEY]======================================"
  cat $WALLET_DIR/key.skey | jq
  echo "====================[PAYMENT VERIFICATION KEY]======================================"
  cat $WALLET_DIR/key.vkey | jq

  # Clean up and wipe all the data:
  PHRASE=""
  rm -rf $WALLET_DIR
}

if [ "${ADVANCED:=false}" == "false" ]; then
  generate-random-wallet-keys
else
  cardano-address-create-wallet
fi
