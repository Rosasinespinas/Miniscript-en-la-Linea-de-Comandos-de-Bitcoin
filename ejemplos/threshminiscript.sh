#!/bin/bash
#En este ejercicio vamos a probar la funcion thresh que permite hacer bloqueos de tiempo al output
#Vamos a utilizar utxoupdatepsbt, metodo 2, no necesitamos descriptors internos
#En el compilador online: thresh(3,pk(A),pk(B),pk(C),older(10))
#Resultado: thresh(3,pk(A),s:pk(B),s:pk(C),sln:older(10))
#Descriptor: wsh(thresh(3,pk(A),s:pk(B),s:pk(C),sln:older(10)))

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
bitcoin-cli -named createwallet wallet_name="Carla"

#Obtenemos los descriptors externos de todos y los privados de Alice y Bob, ya que ellos van a firmar
descAextpriv=$(bitcoin-cli -rpcwallet=Alice listdescriptors true | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc'| grep -Po '(?<=\().*(?=\))')

descAext=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc'| grep -Po '(?<=\().*(?=\))')

descBextpriv=$(bitcoin-cli -rpcwallet=Bob listdescriptors true | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc'| grep -Po '(?<=\().*(?=\))')

descBext=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc'| grep -Po '(?<=\().*(?=\))')

descCext=$(bitcoin-cli -rpcwallet=Carla listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc'| grep -Po '(?<=\().*(?=\))')

#Aqui vemos como combinamos los descriptors publicos con el privado de Alice
descextA="wsh(thresh(3,pk($descAextpriv),s:pk($descBext),s:pk($descCext),sln:older(10)))"

descextB="wsh(thresh(3,pk($descAext),s:pk($descBextpriv),s:pk($descCext),sln:older(10)))"

extsumA=$(bitcoin-cli getdescriptorinfo $descextA | jq -r '.checksum')

extsumB=$(bitcoin-cli getdescriptorinfo $descextB | jq -r '.checksum')

extdescsumA=$descextA#$extsumA

extdescsumB=$descextB#$extsumB

#DescriptorA tiene la clave privada de Alice
bitcoin-cli -named createwallet wallet_name="descriptorA" blank=true
bitcoin-cli  -rpcwallet="descriptorA" importdescriptors "[{\"desc\": \"$extdescsumA\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": false,\"internal\": false,\"range\": [0,999]}]"

#DescriptorB tiene la clave privada de Bob
bitcoin-cli -named createwallet wallet_name="descriptorB" blank=true
bitcoin-cli  -rpcwallet="descriptorB" importdescriptors "[{\"desc\": \"$extdescsumB\",\"timestamp\": \"now\",\"active\": true,\"watching-only\": false,\"internal\": false,\"range\": [0,999]}]"

#Aqui podemos comprobar por curiosidad que descriptorA y descriptorB generan la misma direccion
direccion=$(bitcoin-cli -rpcwallet="descriptorA" getnewaddress)
direccion=$(bitcoin-cli -rpcwallet="descriptorB" getnewaddress)

mineria=$(bitcoin-cli -rpcwallet="Miner" getnewaddress)
bitcoin-cli generatetoaddress 101 $mineria
utxo0txid=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[0] | .txid')
utxo0vout=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[0] | .vout')
rawtxhex=$(bitcoin-cli -named createrawtransaction inputs='''[ { "txid": "'$utxo0txid'", "vout": '$utxo0vout'}]''' outputs='''[{ "'$direccion'": 49.999 }]''')
firmadotx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $rawtxhex | jq -r '.hex')
txid=$(bitcoin-cli sendrawtransaction $firmadotx)
bitcoin-cli generatetoaddress 1 $mineria

#Bob, Alice y Carla pueden gastar firmando los 3, despues de 10 bloques solo necesitan 2 firmas
direccioncambio=$(bitcoin-cli -rpcwallet=Alice getnewaddress)
psbt=$(bitcoin-cli -named createpsbt inputs="[{\"txid\": \"$txid\",\"vout\":0,\"sequence\":10}]" outputs="[{\"$direccioncambio\":49.998}]")

#Voy a utilizar utxoupdate con un descriptor sin clave privada de ningun wallet

descext="wsh(thresh(3,pk($descAext),s:pk($descBext),s:pk($descCext),sln:older(10)))"

extsum=$(bitcoin-cli getdescriptorinfo $descext | jq -r '.checksum')

extdescsum=$descext#$extsum

psbtupdate=$(bitcoin-cli utxoupdatepsbt $psbt "[{\"desc\": \"$extdescsum\",\"range\": [0,10]}]")

#Alice  y Bob firman la transaccion

psbtA=$(bitcoin-cli -rpcwallet="descriptorA" walletprocesspsbt $psbtupdate | jq -r '.psbt')

psbtB=$(bitcoin-cli -rpcwallet="descriptorB" walletprocesspsbt $psbtupdate | jq -r '.psbt')

#Alice y Bob combinan las firmas

combinedpsbt=$(bitcoin-cli combinepsbt "[\"$psbtA\", \"$psbtB\"]")
#Finalizamos psbt
finalizedpsbt=$(bitcoin-cli finalizepsbt $combinedpsbt | jq -r '.hex')
#Enviamos transaccion
bitcoin-cli sendrawtransaction $finalizedpsbt
#Nos da error pero vamos a minar 15 bloqueos
bitcoin-cli generatetoaddress 15 $mineria

bitcoin-cli sendrawtransaction $finalizedpsbt
bitcoin-cli generatetoaddress 1 $mineria
bitcoin-cli -rpcwallet=Alice getbalance
