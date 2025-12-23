#!/bin/bash

#En este ejercicio vamos a utilicar miniscript para hacer un bloqueo sencillo al output
#Alice no podrá gastar hasta pasados 10 bloques
#En el compilador online de miniscript and(keyA, older(10))
#Resultando en miniscript and_v(v:pk(keyA,older(10)))
#Descriptor wsh(and_v(v:pk($descAext),older(10))

bitcoin-cli stop
sleep 3

#Borrar el directorio regtest para iniciar desde cero regtest
rm -rf ~/.bitcoin/regtest
#Ejecutar bitcoin
bitcoind -daemon
sleep 3

#Crear wallets Miner, Alice
bitcoin-cli -named createwallet wallet_name="Miner"
bitcoin-cli -named createwallet wallet_name="Alice"

#Seleccionar descriptors de Alice
descAext=$(bitcoin-cli -rpcwallet=Alice listdescriptors true | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc'| grep -Po '(?<=\().*(?=\))')

echo “Descriptor Alice: $descAext”

#Crear descriptors para el nuevo wallet usando el resultado del compilador
descext="wsh(and_v(v:pk($descAext),older(10)))"

extsum=$(bitcoin-cli getdescriptorinfo $descext | jq -r  '.checksum')

extdescsum=$descext#$extsum

#Crear nuevo wallet
bitcoin-cli -named createwallet wallet_name="descriptor" blank=true

#Importar descriptors
bitcoin-cli  -rpcwallet="descriptor" importdescriptors "[{\"desc\": \"$extdescsum\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": false,\"range\": [0,999]}]" #, {\"desc\": \"$intdescsum\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": true,\"internal\": true,\"range\": [0,999]}]"

#Obtener dirección del wallet descriptor y enviar 50BTC desde Miner
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

#Vemos el balance de Alice y el wallet descriptor antes
bitcoin-cli -rpcwallet=Alice getbalance
bitcoin-cli -rpcwallet=descriptor getbalance

#Alice tiene un bloqueo de tiempo, va a intentar gastar la salida
direccionAlice=$(bitcoin-cli -rpcwallet=Alice getnewaddress)
rawtxhex=$(bitcoin-cli -named createrawtransaction inputs="[{\"txid\": \"$txid\",\"vout\":0,\"sequence\":10}]" outputs="[{\"$direccionAlice\":49.998}]")

#Alice firma la transaccion
firmadotx=$(bitcoin-cli -rpcwallet=descriptor signrawtransactionwithwallet $rawtxhex | jq -r '.hex')
bitcoin-cli sendrawtransaction $firmadotx

echo "Nos da un error, vamos a minar 15 bloques y repetimos el proceso"

bitcoin-cli generatetoaddress 15 $mineria

txid=$(bitcoin-cli sendrawtransaction $firmadotx)

#Enviamos la transaccion

bitcoin-cli generatetoaddress 1 $mineria

bitcoin-cli -rpcwallet=Alice getbalance
bitcoin-cli -rpcwallet=descriptor getbalance

