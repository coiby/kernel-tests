#!/bin/bash

command_arguments=""

if [ -n "${SEED+1}" ]; then
	command_arguments="$command_arguments --randomSeed $SEED"
fi

if [ -n "${PRESET+1}" ]; then
	command_arguments="$command_arguments --connectionPreset $PRESET"
fi

if [ -n "${SSID+1}" ]; then
	command_arguments="$command_arguments --customSSID $SSID"
fi

if [ -n "${KEY_MANAGEMENT_TYPE+1}" ]; then
	command_arguments="$command_arguments --customKeyManagementType $KEY_MANAGEMENT_TYPE"
fi

if [ -n "${PAIRWISE+1}" ]; then
	command_arguments="$command_arguments --customPairwise $PAIRWISE"
fi

if [ -n "${GROUP+1}" ]; then
	command_arguments="$command_arguments --customGroup $GROUP"
fi

if [ -n "${PROTO+1}" ]; then
	command_arguments="$command_arguments --customProto $PROTO"
fi

if [ -n "${PSK+1}" ]; then
	command_arguments="$command_arguments --customPSK $PSK"
fi

if [ -n "${EAP+1}" ]; then
	command_arguments="$command_arguments --customEAP $EAP"
fi

if [ -n "${IDENTITY+1}" ]; then
	command_arguments="$command_arguments --customIdentity $IDENTITY"
fi

if [ -n "${PRIVATE_KEY_PASSWORD+1}" ]; then
	command_arguments="$command_arguments --customPrivateKeyPassword $PRIVATE_KEY_PASSWORD"
fi

if [ -n "${AUTH_ALG+1}" ]; then
	command_arguments="$command_arguments --customAuthAlg $AUTH_ALG"
fi

if [ -n "${PASSWORD+1}" ]; then
	command_arguments="$command_arguments --customPassword $PASSWORD"
fi

if [ -n "${PHASE2_AUTHEAP+1}" ]; then
	command_arguments="$command_arguments --customPhase2AuthEAP $PHASE2_AUTHEAP"
fi

if [ -n "${WEP_KEY_TYPE+1}" ]; then
	command_arguments="$command_arguments --customWEPKeyType $WEP_KEY_TYPE"
fi

if [ -n "${WEP_KEY0+1}" ]; then
	command_arguments="$command_arguments --customWEPKey0 $WEP_KEY0"
fi

if [ -n "${WEP_KEY1+1}" ]; then
	command_arguments="$command_arguments --customWEPKey1 $WEP_KEY1"
fi

if [ -n "${WEP_KEY2+1}" ]; then
	command_arguments="$command_arguments --customWEPKey2 $WEP_KEY2"
fi

if [ -n "${WEP_KEY3+1}" ]; then
	command_arguments="$command_arguments --customWEPKey3 $WEP_KEY3"
fi

if [ -n "${HIDDEN_NETWORK+1}" ]; then
	command_arguments="$command_arguments --customHiddenNetwork $HIDDEN_NETWORK"
fi

if [ -n "${CA_CERT_PATH+1}" ]; then
	command_arguments="$command_arguments --caCertPath $CA_CERT_PATH"
fi

if [ -n "${CLIENT_CERT_PATH+1}" ]; then
	command_arguments="$command_arguments --clientCertPath $CLIENT_CERT_PATH"
fi

if [ -n "${PRIVATE_KEY_PATH+1}" ]; then
	command_arguments="$command_arguments --privateKeyPath $PRIVATE_KEY_PATH"
fi

if [ -n "${PREFERRED_COMMAND+1}" ]; then
	command_arguments="$command_arguments --preferredCommand $PREFERRED_COMMAND"
fi

if [ -n "${TEST_INTERFACE+1}" ]; then
	command_arguments="$command_arguments --testInterface $TEST_INTERFACE"
fi

sh test_launcher.sh "$TEST" "test.py $command_arguments $*"

rhts-submit-log -l /var/log/wpa_supplicant.log --port=8081
rhts-submit-log -l ./test.log --port=8081
rhts-submit-log -l /var/log/messages --port=8081
