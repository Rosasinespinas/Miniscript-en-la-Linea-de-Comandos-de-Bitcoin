#!/bin/bash

#Ejemplo transaccion multifirma metodo 1
#------------------------------
#Parte uno: Crear direccion multifirma con los descriptors de Alice y Bob
#------------------------------
bitcoin-cli stop
rm -rf ~/.bitcoin/regtest
bitcoind -daemon

sleep 3

bitcoin-cli createwallet "Alice"
bitcoin-cli createwallet "Bob"

#Extraigo los descriptors internos y externos de Alice y Bob

descAint=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("pkh") and contains("/1/*"))][0] | .desc')
descAext=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("pkh") and contains("/0/*"))][0] | .desc')

descAint=$(echo $descAint | awk '{ print substr( $0, 1, length($0)-10 ) }')
descAint=$(echo $descAint | awk '{ print substr ($0, 25 ) }')
descAext=$(echo $descAext | awk '{ print substr( $0, 1, length($0)-10 ) }')
descAext=$(echo $descAext | awk '{ print substr ($0, 25 ) }')

descBint=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("pkh") and contains("/1/*"))][0] | .desc')
descBext=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("pkh") and contains("/0/*"))][0] | .desc')

descBint=$(echo $descBint | awk '{ print substr( $0, 1, length($0)-10 ) }')
descBint=$(echo $descBint | awk '{ print substr ($0, 25 ) }')
descBext=$(echo $descBext | awk '{ print substr( $0, 1, length($0)-10 ) }')
descBext=$(echo $descBext | awk '{ print substr ($0, 25 ) }')

#Los combino para la multifirma
extdesc="wsh(multi(2,$descAext,$descBext))"
intdesc="wsh(multi(2,$descAint,$descBint))"

#obtengo el che ksum
extdescsum=$(bitcoin-cli getdescriptorinfo $extdesc | jq -r  '.descriptor')
intdescsum=$(bitcoin-cli  getdescriptorinfo $intdesc | jq -r '.descriptor')

#Creo un nuevo wallet
bitcoin-cli -named createwallet wallet_name="multi" disable_private_keys=true blank=true

bitcoin-cli  -rpcwallet="multi" importdescriptors "[{\"desc\": \"$extdescsum\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": false,\"range\": [0,999]} , {\"desc\": \"$intdescsum\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": true,\"range\": [0,999]}]"

#Genero una nueva direccion
direccionmulti=$(bitcoin-cli -rpcwallet="multi" getnewaddress)

bitcoin-cli -rpcwallet="multi" getwalletinfo

#------------------------------
#Parte 2. Generar Bitcoin en regtest en la direccion multifirma
#------------------------------

bitcoin-cli generatetoaddress 101 "$direccionmulti"
echo "Nuestra cartera Multifirma tiene ahora un saldo de: $(bitcoin-cli -rpcwallet=multi getbalance) BTC"
identtx=$(bitcoin-cli -rpcwallet="multi" listunspent | jq -r '.[0] | .txid')

#------------------------------
#Parte 3: Gastar de Wallet Multi
#------------------------------

direccionAlice=$(bitcoin-cli -rpcwallet="Alice" getnewaddress)

psbt=$(bitcoin-cli -rpcwallet="multi" -named walletcreatefundedpsbt inputs="[{\"txid\": \"$identtx\",\"vout\":0}]" outputs="[{\"$direccionAlice\":20}]" | jq -r '.psbt') #{\"$cambiomulti\":10},

bitcoin-cli analyzepsbt $psbt
#Firma Alice
psbtA=$(bitcoin-cli -rpcwallet="Alice" walletprocesspsbt $psbt | jq -r '.psbt')
#Firma Bob
psbtB=$(bitcoin-cli -rpcwallet="Bob" walletprocesspsbt $psbt | jq -r '.psbt')
#Combinamos  firmas
combinedpsbt=$(bitcoin-cli combinepsbt "[\"$psbtA\", \"$psbtB\"]")
#Finalizamos transaccion psbt
finalizedpsbt=$(bitcoin-cli finalizepsbt $combinedpsbt | jq -r '.hex')
#Enviamos la transaccion
bitcoin-cli sendrawtransaction $finalizedpsbt

bitcoin-cli generatetoaddress 1 "$direccionmulti"

echo "Balance de wallet multi: $(bitcoin-cli -rpcwallet="multi" getbalance)BTC"
echo "Balance de wallet Alice: $(bitcoin-cli -rpcwallet="Alice" getbalance)BTC"
echo "Balance de wallet Bob: $(bitcoin-cli -rpcwallet="Bob" getbalance)BTC"
