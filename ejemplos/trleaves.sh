#!/bin/bash

#Ejemplo uso descriptors en taproot con un key path Alice y dos scripts path
#Alice puede gastar siempre, Bob, Carla y Diego tienen una firma dos de 3, Diego puede gastar despues de 10 bloques
#Por sencillez estoy reusando direcciones, nunca hacer esto en la red principal
#------------------------------
#Parte uno: Crear direccion con los x-pub de Alice, Bob, Carla y Diego
#------------------------------
bitcoin-cli stop
rm -rf ~/.bitcoin/regtest
bitcoind -daemon

sleep 3

#Creo los wallets
bitcoin-cli createwallet "Alice"
bitcoin-cli createwallet "Bob"
bitcoin-cli createwallet "Carla"
bitcoin-cli createwallet "Diego"

#generamos una dirección
dirAlice=$(bitcoin-cli -rpcwallet=Alice getnewaddress)
dirBob=$(bitcoin-cli -rpcwallet=Bob getnewaddress)
dirCarla=$(bitcoin-cli -rpcwallet=Carla getnewaddress)
dirDiego=$(bitcoin-cli -rpcwallet=Diego getnewaddress)

#Obtengo la pubkey (esto es la coordenada x de la clave publica con 02 o 03)
xpubkA=$(bitcoin-cli -rpcwallet=Alice getaddressinfo $dirAlice | jq -r '.pubkey')
xpubkB=$(bitcoin-cli -rpcwallet=Bob getaddressinfo $dirBob | jq -r '.pubkey')
xpubkC=$(bitcoin-cli -rpcwallet=Carla getaddressinfo $dirCarla | jq -r '.pubkey')
xpubkD=$(bitcoin-cli -rpcwallet=Diego getaddressinfo $dirDiego | jq -r '.pubkey')

#Elimino el 02 o 03
xpubkA=${xpubkA:2}
xpubkB=${xpubkB:2}
xpubkC=${xpubkC:2}
xpubkD=${xpubkD:2}

#Descriptor:
desc="tr($xpubkA,{multi_a(2,$xpubkB,$xpubkC,$xpubkD),and_v(v:pk($xpubkD),older(10))})"
#Checksum del descriptor
descsum=$(bitcoin-cli getdescriptorinfo $desc | jq -r  '.descriptor')
#Obtengo una dirección del descriptor
dirdesc=$(bitcoin-cli deriveaddresses $descsum | jq -r '.[0]')

#Creo un wallet tr para importar el descriptor
bitcoin-cli -named createwallet wallet_name="tr" disable_private_keys=true blank=true

bitcoin-cli -rpcwallet="tr" importdescriptors "[{\"desc\": \"$descsum\",\"timestamp\": \"now\",\"active\": false,\"watching-only\": true,\"internal\": false}]" #,\"range\": [0,999]}]" # , {\"desc\": \"$intdescsum\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": true,\"range\": [0,999]}]"

#------------------------------
#Parte 2. Generar Bitcoin en regtest
#------------------------------

bitcoin-cli generatetoaddress 101 $dirdesc
echo "Nuestra cartera tiene ahora un saldo de: $(bitcoin-cli -rpcwallet=tr getbalance) BTC"
identtx=$(bitcoin-cli -rpcwallet="tr" listunspent | jq -r '.[0] | .txid')

#------------------------------
#Parte 3: Alice va a gastar de Wallet tr y enviar 49.998BTC a su propia cartera
#------------------------------

direccionAlice=$(bitcoin-cli -rpcwallet="Alice" getnewaddress)

#Crear psbt
psbt=$(bitcoin-cli -named createpsbt inputs="[{\"txid\": \"$identtx\",\"vout\":0}]" outputs="[{\"$direccionAlice\":49.998}]") #{\"$cambio\":10},
#Update
psbtupdate=$(bitcoin-cli utxoupdatepsbt $psbt "[{\"desc\": \"$descsum\"}]")
#Firma
psbtA=$(bitcoin-cli -rpcwallet="Alice" walletprocesspsbt $psbtupdate | jq -r '.psbt')
#Finalizamos
finalizedpsbt1=$(bitcoin-cli finalizepsbt $psbtA | jq -r '.hex')
#Enviamos
bitcoin-cli sendrawtransaction $finalizedpsbt1

bitcoin-cli generatetoaddress 1 $dirdesc

echo "Balance de wallet taproot: $(bitcoin-cli -rpcwallet="tr" getbalance)BTC"
echo "Balance de wallet Alice: $(bitcoin-cli -rpcwallet="Alice" getbalance)BTC"
#------------------------------
#Parte 4: Bob y Carla van a enviar a Alice 49.998 con su firma 2 de 3
#------------------------------
#Obtenemos el UTXO
identtx=$(bitcoin-cli -rpcwallet=tr listunspent | jq -r '.[0] | .txid')
#Creamos psbt
psbt=$(bitcoin-cli -named createpsbt inputs="[{\"txid\": \"$identtx\",\"vout\":0}]" outputs="[{\"$direccionAlice\":49.998}]")
#Update
psbtupdate=$(bitcoin-cli utxoupdatepsbt $psbt "[{\"desc\": \"$descsum\"}]")
#Firma Bob
psbtB=$(bitcoin-cli -rpcwallet="Bob" walletprocesspsbt $psbtupdate | jq -r '.psbt')
#Firma Carla
psbtC=$(bitcoin-cli -rpcwallet="Carla" walletprocesspsbt $psbtupdate | jq -r '.psbt')
#Combinamos psbt
combinedpsbt=$(bitcoin-cli combinepsbt "[\"$psbtB\", \"$psbtC\"]")
#Finalizamos
finalizedpsbt2=$(bitcoin-cli finalizepsbt $combinedpsbt | jq -r '.hex')
#Enviamos
bitcoin-cli sendrawtransaction $finalizedpsbt2

bitcoin-cli generatetoaddress 1 $dirdesc

echo "Balance de wallet taproot: $(bitcoin-cli -rpcwallet="tr" getbalance)BTC"
echo "Balance de wallet Alice: $(bitcoin-cli -rpcwallet="Alice" getbalance)BTC"

#------------------------------
#Parte 5: Diego gasta pero tiene que dejar pasar 10 bloques, va a enviar 9.998BTC a su propia dirección
#------------------------------

#Necesito una transaccion que no tenga mas de 10 bloques de minada, voy a enviar a la direccion 10 BTC de Alice

identtx=$(bitcoin-cli -rpcwallet=Alice sendtoaddress $dirdesc 10)

bitcoin-cli generatetoaddress 1 $dirdesc

dirDiego=$(bitcoin-cli -rpcwallet=Diego getnewaddress)

vout=$(bitcoin-cli -rpcwallet=tr listunspent | jq '.[] | select(.amount == 10) | .vout')

#Creo psbt
psbt=$(bitcoin-cli -named createpsbt inputs="[{\"txid\": \"$identtx\",\"vout\":$vout,\"sequence\":10}]" outputs="[{\"$dirDiego\":9.998}]")
#Update
psbtupdate=$(bitcoin-cli utxoupdatepsbt $psbt "[{\"desc\": \"$descsum\"}]")
#Firma Diego
psbtD=$(bitcoin-cli -rpcwallet="Diego" walletprocesspsbt $psbtupdate | jq -r '.psbt')
#Finaliza
finalizedpsbt3=$(bitcoin-cli finalizepsbt $psbtD | jq -r '.hex')
#Envia
bitcoin-cli sendrawtransaction $finalizedpsbt3
#No puedo enviar, genero 11 bloques
bitcoin-cli generatetoaddress 11 $dirdesc
#Envio de nuevo
bitcoin-cli sendrawtransaction $finalizedpsbt3

bitcoin-cli generatetoaddress 1 $dirdesc

echo "Balance de wallet taproot: $(bitcoin-cli -rpcwallet="tr" getbalance)BTC"
echo "Balance de wallet Alice: $(bitcoin-cli -rpcwallet="Alice" getbalance)BTC"
echo "Balance de wallet Diego: $(bitcoin-cli -rpcwallet="Diego" getbalance)BTC"

#Observa la diferencia entre las 3 transacciones
bitcoin-cli decoderawtransaction $finalizedpsbt1
bitcoin-cli decoderawtransaction $finalizedpsbt2
bitcoin-cli decoderawtransaction $finalizedpsbt3

