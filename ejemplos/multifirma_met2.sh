#!/bin/bash

#Ejemplo transaccion miltifirma metodo 2
#------------------------------
#Parte uno: Crear direccion multifirma con los descriptors de Alice y Bob
#------------------------------
bitcoin-cli stop
rm -rf ~/.bitcoin/regtest
bitcoind -daemon

sleep 3

#Crear wallets
bitcoin-cli createwallet "Alice"
bitcoin-cli createwallet "Bob"

#Extraer los descritpors, solo los externos, ya que no vamos a utilizar walletcreatefundedpsbt
descAext=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("pkh") and contains("/0/*"))][0] | .desc')
descAext=$(echo $descAext | awk '{ print substr( $0, 1, length($0)-10 ) }')
descAext=$(echo $descAext | awk '{ print substr ($0, 25 ) }')

descBext=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("pkh") and contains("/0/*"))][0] | .desc')
descBext=$(echo $descBext | awk '{ print substr( $0, 1, length($0)-10 ) }')
descBext=$(echo $descBext | awk '{ print substr ($0, 25 ) }')

#Descriptor multifirma
extdesc="wsh(multi(2,$descAext,$descBext))"
#Descriptor con el checksum
extdescsum=$(bitcoin-cli getdescriptorinfo $extdesc | jq -r  '.descriptor')

#Nuevo wallet multifirma
bitcoin-cli -named createwallet wallet_name="multi" disable_private_keys=true blank=true

#Importamos descriptors nuevo wallet
bitcoin-cli  -rpcwallet="multi" importdescriptors "[{\"desc\": \"$extdescsum\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": false,\"range\": [0,999]}]"

#Generamos nueva direccion multifirma
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

echo "Bob y Alice se reparten el saldo de Multifirma 39.99 a Alice y 10 a Bob"
direccionAlice=$(bitcoin-cli -rpcwallet="Alice" getnewaddress)
direccionBob=$(bitcoin-cli -rpcwallet="Bob" getnewaddress)

#Ya tenemos los UTXOS y las direcciones de envio, creamos una transaccion psbt
psbt=$(bitcoin-cli -rpcwallet="multi" -named createpsbt inputs="[{\"txid\": \"$identtx\",\"vout\":0}]" outputs="[{\"$direccionBob\":10},{\"$direccionAlice\":39.999}]")

#Usamos el descriptor obtenido para el comando utxoupdatepsbt
psbtupdate=$(bitcoin-cli utxoupdatepsbt $psbt "[{\"desc\": \"$extdescsum\"}]")

#Firma Alice
psbtA=$(bitcoin-cli -rpcwallet="Alice" walletprocesspsbt $psbtupdate | jq -r '.psbt')
#Firma Bob
psbtB=$(bitcoin-cli -rpcwallet="Bob" walletprocesspsbt $psbtupdate | jq -r '.psbt')
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
