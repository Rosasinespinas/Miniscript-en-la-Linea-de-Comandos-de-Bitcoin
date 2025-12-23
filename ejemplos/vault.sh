#!/bin/bash

#Ejemplo uso miniscript vault
#------------------------------
#Parte uno: Crear direccion vault con los descriptors de Alice, Bob, Carla y Diego con la plantilla de miniscript
#------------------------------
bitcoin-cli stop
sleep 3
rm -rf ~/.bitcoin/regtest
bitcoind -daemon

sleep 3

#Creamos los wallets
bitcoin-cli createwallet "Miner"
bitcoin-cli createwallet "Alice"
bitcoin-cli createwallet "Bob"
bitcoin-cli createwallet "Carla"
bitcoin-cli createwallet "Diego"

#Entraemos los descriptors
descAext=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*") )][0] | .desc' | grep -Po '(?<=\().*(?=\))')

descBext=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*") )][0] | .desc' | grep -Po '(?<=\().*(?=\))')

descCext=$(bitcoin-cli -rpcwallet=Carla listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*") )][0] | .desc' | grep -Po '(?<=\().*(?=\))')

descDext=$(bitcoin-cli -rpcwallet=Diego listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*") )][0] | .desc' | grep -Po '(?<=\().*(?=\))')

#Creamos el descriptor con las condiciones de gasto
extdesc="wsh(or_d(pk($descAext),and_v(v:multi(2,$descBext,$descCext,$descDext),older(10))))"
#Añado el checksum
extdescsum=$(bitcoin-cli getdescriptorinfo $extdesc | jq -r  '.descriptor')

#Creamos un nuevo wallet al que llamamos vault
bitcoin-cli -named createwallet wallet_name="vault" disable_private_keys=true blank=true
#Importamos descriptors
bitcoin-cli  -rpcwallet="vault" importdescriptors "[{\"desc\": \"$extdescsum\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": false,\"range\": [0,999]}]" # , {\"desc\": \"$intdescsum\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": true,\"range\": [0,999]}]"
#Obtenemos una direccion
direccion=$(bitcoin-cli -rpcwallet="vault" getnewaddress)

#------------------------------
#Parte 2. Generar Bitcoin en regtest
#------------------------------

mineria=$(bitcoin-cli -rpcwallet="Miner" getnewaddress)
bitcoin-cli generatetoaddress 101 $mineria

#Envio unos BTC de mineria al wallet Vault
utxo0txid=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[0] | .txid')
utxo0vout=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[0] | .vout')
rawtxhex=$(bitcoin-cli -named createrawtransaction inputs='''[ { "txid": "'$utxo0txid'", "vout": '$utxo0vout'}]''' outputs='''[{ "'$direccion'": 49.999 }]''')
firmadotx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $rawtxhex | jq -r '.hex')
txid=$(bitcoin-cli sendrawtransaction $firmadotx)
bitcoin-cli getrawtransaction $txid 1
bitcoin-cli generatetoaddress 1 $mineria

echo "Nuestra cartera Vault tiene ahora un saldo de: $(bitcoin-cli -rpcwallet=vault getbalance) BTC"
identtx=$(bitcoin-cli -rpcwallet="vault" listunspent | jq -r '.[0] | .txid')

#------------------------------
#Parte 3: Gastar de Wallet vault
#------------------------------

#Vamos a enviar a Bob
direccionBob=$(bitcoin-cli -rpcwallet="Bob" getnewaddress)

#Creamos psbt
psbt=$(bitcoin-cli -named createpsbt inputs="[{\"txid\": \"$identtx\",\"vout\":0,\"sequence\":10}]" outputs="[{\"$direccionBob\":49.998}]")
#Creamos dos wallets para poder firmar combinando los descriptors externos publicos y los privados de Bob y Carla
bitcoin-cli -named createwallet wallet_name="vaultB" blank=true
bitcoin-cli -named createwallet wallet_name="vaultC" blank=true

descBextpriv=$(bitcoin-cli -rpcwallet=Bob listdescriptors true | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc'| grep -Po '(?<=\().*(?=\))')

descCextpriv=$(bitcoin-cli -rpcwallet=Carla listdescriptors true | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc'| grep -Po '(?<=\().*(?=\))')

descextB="wsh(or_d(pk($descAext),and_v(v:multi(2,$descBextpriv,$descCext,$descDext),older(10))))"

descextC="wsh(or_d(pk($descAext),and_v(v:multi(2,$descBext,$descCextpriv,$descDext),older(10))))"

extsumB=$(bitcoin-cli getdescriptorinfo $descextB | jq -r '.checksum')

extsumC=$(bitcoin-cli getdescriptorinfo $descextC | jq -r '.checksum')

extdescsumB=$descextB#$extsumB

extdescsumC=$descextC#$extsumC

bitcoin-cli  -rpcwallet="vaultB" importdescriptors "[{\"desc\": \"$extdescsumB\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": false,\"range\": [0,999]}]"

bitcoin-cli  -rpcwallet="vaultC" importdescriptors "[{\"desc\": \"$extdescsumC\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": false,\"range\": [0,999]}]"
#####
#preparar descriptor sin clave privada para utxoupdate
descext="wsh(or_d(pk($descAext),and_v(v:multi(2,$descBext,$descCext,$descDext),older(10))))"

extsum=$(bitcoin-cli getdescriptorinfo $descext | jq -r '.checksum')

extdescsum=$descext#$extsum

#Update
psbtupdate=$(bitcoin-cli utxoupdatepsbt $psbt "[{\"desc\": \"$extdescsum\",\"range\": [0,10]}]")

#Firmar
psbtB=$(bitcoin-cli -rpcwallet="vaultB" walletprocesspsbt $psbtupdate | jq -r '.psbt')

psbtC=$(bitcoin-cli -rpcwallet="vaultC" walletprocesspsbt $psbtupdate | jq -r '.psbt')

#Combinar y finalizar
combinedpsbt=$(bitcoin-cli combinepsbt "[\"$psbtB\", \"$psbtC\"]")

finalizedpsbt=$(bitcoin-cli finalizepsbt $combinedpsbt | jq -r '.hex')

bitcoin-cli sendrawtransaction $finalizedpsbt

echo "Nos da error, vamos a minar 15 bloques"

bitcoin-cli generatetoaddress 15 "$mineria"

bitcoin-cli sendrawtransaction $finalizedpsbt

bitcoin-cli generatetoaddress 1 "$mineria"

echo "Balance de wallet vault: $(bitcoin-cli -rpcwallet="vault" getbalance)BTC"
echo "Balance de wallet Bob: $(bitcoin-cli -rpcwallet="Bob" getbalance)BTC"

