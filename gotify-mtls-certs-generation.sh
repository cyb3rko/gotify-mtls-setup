#!/usr/bin/env bash

set -e

KEYSTORE_FILENAME="gotify-client.jks"
KEYSTORE_FILENAME_P12="gotify-client.p12"
VALIDITY_IN_DAYS=3650
DEFAULT_TRUSTSTORE_FILENAME="gotify-truststore.jks"
CA_WORKING_DIRECTORY="ca"
KEYSTORE_WORKING_DIRECTORY="keystore"
CA_CERT_KEY="gotify-ca.key"
CA_CERT_FILE="gotify-ca.crt"
CA_CERT_SIGN_REQUEST="gotify-ca.csr"
CA_CERT_SIGN_REQUEST_SRL="gotify-ca.srl"
KEYSTORE_SIGN_REQUEST="gotify-client-cert.csr"
KEYSTORE_SIGNED_CERT="gotify-client-cert-signed.crt"

function file_exists_and_exit() {
  echo "> '$1' cannot exist. Move or delete it before re-running this script."
  exit 1
}

if [ -e "$KEYSTORE_WORKING_DIRECTORY" ]; then
  file_exists_and_exit $KEYSTORE_WORKING_DIRECTORY
fi

if [ -e "$CA_CERT_FILE" ]; then
  file_exists_and_exit $CA_CERT_FILE
fi

if [ -e "$KEYSTORE_SIGN_REQUEST" ]; then
  file_exists_and_exit $KEYSTORE_SIGN_REQUEST
fi

if [ -e "$KEYSTORE_SIGN_REQUEST_SRL" ]; then
  file_exists_and_exit $KEYSTORE_SIGN_REQUEST_SRL
fi

if [ -e "$KEYSTORE_SIGNED_CERT" ]; then
  file_exists_and_exit $KEYSTORE_SIGNED_CERT
fi

echo
echo "> Welcome to the Gotify mTLS certificate generator script."
echo "> First, do you need to generate a CA and associated private key, or do you already have a CA file and private key?"
echo ">"
echo -n "> Do you need to generate a CA and associated private key? [yn] "
read generate_trust_store

ca_file=""
ca_private_key_file=""

if [ "$generate_trust_store" == "y" ]; then
  if [ -e "$CA_WORKING_DIRECTORY" ]; then
    file_exists_and_exit $CA_WORKING_DIRECTORY
  fi

  mkdir $CA_WORKING_DIRECTORY
  echo
  echo "> OK, let's generate a CA and associated private key."
  echo "> First, the private key."
  echo ">"
  echo "> You will be prompted for:"
  echo ">  - certificate attributes"
  echo ">  - a password for the private key. Remember this."
  echo

  openssl genpkey -algorithm ED25519 -out $CA_WORKING_DIRECTORY/$CA_CERT_KEY
  openssl req -new -key $CA_WORKING_DIRECTORY/$CA_CERT_KEY -out $CA_WORKING_DIRECTORY/$CA_CERT_SIGN_REQUEST
  openssl x509 -req -days $VALIDITY_IN_DAYS -in $CA_WORKING_DIRECTORY/$CA_CERT_SIGN_REQUEST \
    -signkey $CA_WORKING_DIRECTORY/$CA_CERT_KEY -out $CA_WORKING_DIRECTORY/$CA_CERT_FILE

  echo
  echo "> Two files were created:"
  echo ">  - $CA_WORKING_DIRECTORY/$CA_CERT_KEY -- the private key used later to sign certificates"
  echo ">  - $CA_WORKING_DIRECTORY/$CA_CERT_FILE -- the certificate that will serve as the CA."
  echo ">"
  echo "> Now the truststore will be generated from the CA certificate."
  echo ">"
  echo "> You will be prompted for:"
  echo ">  - the truststore's password (labeled 'keystore'). Remember this"
  echo ">  - a confirmation that you want to import the certificate."
  echo

  keytool -keystore $CA_WORKING_DIRECTORY/$DEFAULT_TRUSTSTORE_FILENAME \
    -alias CARoot -import -file $CA_WORKING_DIRECTORY/$CA_CERT_FILE

  ca_file="$CA_WORKING_DIRECTORY/$DEFAULT_TRUSTSTORE_FILENAME"
  ca_private_key_file="$CA_WORKING_DIRECTORY/$CA_CERT_KEY"

  echo
  echo "$CA_WORKING_DIRECTORY/$DEFAULT_TRUSTSTORE_FILENAME was created."

  # don't need the cert because it's in the truststore.
  #rm $CA_WORKING_DIRECTORY/$CA_CERT_FILE
else
  echo
  echo -n "> Enter the path to the CA file: "
  read -e ca_file

  if ! [ -f $ca_file ]; then
    echo "> $ca_file isn't a file. Exiting."
    exit 1
  fi

  echo -n "> Enter the path to the CA's private key: "
  read -e ca_private_key_file

  if ! [ -f $ca_private_key_file ]; then
    echo "> $ca_private_key_file isn't a file. Exiting."
    exit 1
  fi
fi

echo
echo "> Continuing with:"
echo ">  - CA file:        $ca_file"
echo ">  - CA private key: $ca_private_key_file"
echo ">"
echo "> Now, a keystore will be generated. Each client should use its own keystore."
echo "> This script will create only one keystore. Run this script multiple times for multiple keystores."
echo ">"
echo "> You will be prompted for the following:"
echo ">  - a keystore password. Remember it"
echo ">  - certificate attributes"
echo ">  - a key password, for the key being generated within the keystore. Remember this."
echo

mkdir $KEYSTORE_WORKING_DIRECTORY

keytool -keystore $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_FILENAME \
  -alias GotifyClient -validity $VALIDITY_IN_DAYS -genkey -keyalg RSA

echo
echo "> $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_FILENAME now contains a key pair and a self-signed certificate."
echo "> Again, this keystore should only be used for one client. Other clients should use their own keystores."
echo ">"
echo "> Fetching the certificate from the truststore and storing in $CA_WORKING_DIRECTORY/$CA_CERT_FILE."
echo ">"
echo "> You will be prompted for the truststore's password (labeled 'keystore')."
echo

keytool -keystore $ca_file -export -alias CARoot -rfc -file $CA_WORKING_DIRECTORY/$CA_CERT_FILE

echo
echo "> Now a certificate signing request will be made to the keystore."
echo ">"
echo "> You will be prompted for the keystore's password."
echo

keytool -keystore $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_FILENAME -alias GotifyClient \
  -certreq -file $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_SIGN_REQUEST

echo
echo "> Now the truststore's private key (CA) will sign the keystore's certificate."
echo ">"
echo "> You will be prompted for the truststore's private key password."
echo

openssl x509 -req -CA $CA_WORKING_DIRECTORY/$CA_CERT_FILE -CAkey $CA_WORKING_DIRECTORY/$CA_CERT_KEY \
  -in $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_SIGN_REQUEST -out $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_SIGNED_CERT \
  -days $VALIDITY_IN_DAYS -CAcreateserial

echo
echo "> Now the CA will be imported into the keystore."
echo ">"
echo "> You will be prompted for the keystore's password and a confirmation that you want to import the certificate."
echo

keytool -keystore $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_FILENAME -alias CARoot \
  -import -file $CA_WORKING_DIRECTORY/$CA_CERT_FILE
#rm $CA_CERT_FILE # delete the truststore cert because it's stored in the truststore.

echo
echo "> Now the keystore's signed certificate will be imported back into the keystore."
echo ">"
echo "> You will be prompted for the keystore's password."
echo

keytool -keystore $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_FILENAME -alias GotifyClient \
  -import -file $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_SIGNED_CERT

echo
echo "> Finally the keystore will be converted to the format PKCS#12 (.p12)."
echo ">"
echo "> You will be prompted for the keystore's password twice."
echo

keytool -importkeystore -srcstoretype JKS -deststoretype PKCS12 \
  -srckeystore $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_FILENAME -destkeystore $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_FILENAME_P12

echo
echo "> All done!"
echo ">"
echo "> Delete intermediate files? They are:"
echo ">  - '$CA_WORKING_DIRECTORY/$CA_CERT_SIGN_REQUEST': the CA's certificate signing request (that was fulfilled)"
echo ">  - '$CA_WORKING_DIRECTORY/$CA_CERT_SIGN_REQUEST_SRL': the CA's serial number"
echo ">  - '$KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_SIGN_REQUEST': the keystore's certificate signing request (that was fulfilled)"
echo ">  - '$KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_FILENAME': the keystore in previous format (.jks)"
echo -n "> Delete? [yn] "
read delete_intermediate_files

if [ "$delete_intermediate_files" == "y" ]; then
  rm $CA_WORKING_DIRECTORY/$CA_CERT_SIGN_REQUEST
  rm $CA_WORKING_DIRECTORY/$CA_CERT_SIGN_REQUEST_SRL
  rm $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_SIGN_REQUEST
  rm $KEYSTORE_WORKING_DIRECTORY/$KEYSTORE_FILENAME
fi
