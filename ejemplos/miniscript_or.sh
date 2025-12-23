#!/bin/bash

#En este ejercicio vamos a crear un wallet en el que pueda gastar Alice o Bob indistintamente
#En el compilador online introducimos or(pk(A),pk(B)) el resultado es or_b(pk(A),s:pk(B)) utilizaremos para importar el descriptor
#En este caso vamos a utilizar el metodo 1, el cambio quedará bloqueado en una dirección que podrán gastar de nuevo Alice o Bob indistintamente
#para lo que importaremos también los descriptores internos

bitcoin-cli stop
sleep 3

#Borrar el directorio regtest para iniciar desde cero regtest
rm -rf ~/.bitcoin/regtest
#Ejecutar bitcoin
bitcoind -daemon
sleep 3

#Crear wallets Miner, Alice y Bob
bitcoin-cli -named createwallet wallet_name="Miner"
bitcoin-cli -named createwallet wallet_name="Alice"
bitcoin-cli -named createwallet wallet_name="Bob"

descAint=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
descAext=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc'| grep -Po '(?<=\().*(?=\))')

descBint=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
descBext=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc'| grep -Po '(?<=\().*(?=\))')

echo “Descriptor Alice: $descAext”
echo “Descriptor Alice interno: $descAint”
echo “Descriptor Bob: $descBext”
echo “Descriptor Bob interno: $descBint

descext="wsh(or_b(pk($descAext),s:pk($descBext)))"
descint="wsh(or_b(pk($descAint),s:pk($descBint)))"

extdescsum=$(bitcoin-cli getdescriptorinfo $descext | jq -r  '.descriptor')
intdescsum=$(bitcoin-cli  getdescriptorinfo $descint | jq -r '.descriptor')

bitcoin-cli -named createwallet wallet_name="descriptor" disable_private_keys=true blank=true
bitcoin-cli  -rpcwallet="descriptor" importdescriptors "[{\"desc\": \"$extdescsum\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": false,\"range\": [0,999]} , {\"desc\": \"$intdescsum\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": true,\"range\": [0,999]}]"

direccion=$(bitcoin-cli -rpcwallet="descriptor" getnewaddress)
mineria=$(bitcoin-cli -rpcwallet="Miner" getnewaddress)
bitcoin-cli generatetoaddress 101 $mineria
utxo0txid=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[0] | .txid')
utxo0vout=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[0] | .vout')
rawtxhex=$(bitcoin-cli -named createrawtransaction inputs='''[ { "txid": "'$utxo0txid'", "vout": '$utxo0vout'}]''' outputs='''[{ "'$direccion'": 49.999 }]''')
firmadotx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $rawtxhex | jq -r '.hex')
txid=$(bitcoin-cli sendrawtransaction $firmadotx)
bitcoin-cli getrawtransaction $txid 1
bitcoin-cli generatetoaddress 1 $mineria

bitcoin-cli -rpcwallet=Miner getbalance
bitcoin-cli -rpcwallet=Alice getbalance
bitcoin-cli -rpcwallet=Bob getbalance
bitcoin-cli -rpcwallet=descriptor getbalance
#Bob va gastar la salida, es una transacción psbt aunque solo Bob firme
direccionBob=$(bitcoin-cli -rpcwallet=Bob getnewaddress)
psbt=$(bitcoin-cli -rpcwallet="descriptor" -named walletcreatefundedpsbt inputs="[{\"txid\": \"$txid\",\"vout\":0}]" outputs="[{\"$direccionBob\":20}]" | jq -r '.psbt')

bitcoin-cli analyzepsbt $psbt

#Bob firma la transaccion 
psbtB=$(bitcoin-cli -rpcwallet="Bob" walletprocesspsbt $psbt | jq -r '.psbt')

#Finalizamos la transaccion
finalizedpsbt=$(bitcoin-cli finalizepsbt $psbtB | jq -r '.hex')

#Enviamos la transaccion
bitcoin-cli sendrawtransaction $finalizedpsbt
bitcoin-cli generatetoaddress 1 $mineria

echo "Balance de Miner $(bitcoin-cli -rpcwallet=Miner getbalance)"
echo "Balance de Alice $(bitcoin-cli -rpcwallet=Alice getbalance)"
echo "Balance de Bob $(bitcoin-cli -rpcwallet=Bob getbalance)"
echo "Balance que pueden gastar Alice y Bob indistintamente $(bitcoin-cli -rpcwallet=descriptor getbalance)"
echo "Recuerda que cuando usas walletcreatefundedpsbt en mainnet, debes usar el argumento feerate"
