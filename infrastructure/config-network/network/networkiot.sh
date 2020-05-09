#!/bin/bash


printHelp() {
    echo "Uso: networkiot.sh [help, up, down, generate, restart, remove]"
    echo
    echo "Comandos:"
    echo "  help        Mostrar esta ayuda"
    echo "  up          Activar red"
    echo "  start       Comenzar red"
    echo "  stop        Parar red"
    echo "  generate    Generar red"
    echo "  restart     Reiniciar red"
    echo "  remove      Eliminar red"
    echo
}


generateNetwork() {        
    # generamos crypto material
    ../bin/cryptogen generate --config=./crypto-config.yaml
    if [ "$?" -ne 0 ]; then
    echo "Fallo al generar crypto material..."
    exit 1
    fi

    # generamos bloque genesis para el orderer
    ../bin/configtxgen -profile OrdererGenesis -outputBlock ./channel-artifacts/genesis.block
    if [ "$?" -ne 0 ]; then
    echo "Fallo al generar el orderer genesis block..."
    exit 1
    fi

    # generamos la configuracion del canal Sensor
    ../bin/configtxgen -profile SensorChannel -outputCreateChannelTx ./channel-artifacts/sensorChannel.tx -channelID sensorchannel
    if [ "$?" -ne 0 ]; then
    echo "Fallo al generar la configuración del canal Sensor..."
    exit 1
    fi

    # generamos la configuracion del canal Linkage
    ../bin/configtxgen -profile LinkageChannel -outputCreateChannelTx ./channel-artifacts/linkageChannel.tx -channelID linkagechannel
    if [ "$?" -ne 0 ]; then
    echo "Fallo al generar la configuración del canal Linkage..."
    exit 1
    fi

    echo
    echo
    echo "Copiando archivos de configuracion a los nodos de trabajo..."
    rsync -r channel-artifacts/ ubuntu@192.168.0.31:$PWD/channel-artifacts
    rsync -r crypto-config/ ubuntu@192.168.0.31:$PWD/crypto-config

    rsync -r channel-artifacts/ ubuntu@192.168.0.32:$PWD/channel-artifacts
    rsync -r crypto-config/ ubuntu@192.168.0.32:$PWD/crypto-config
    echo "Done"

    echo
    echo "Creando red networkiot..."
    docker network create -d overlay --attachable networkiot
    echo "Done"
}


upNetwork() {
    set -ev

    BASE=/opt/gopath/src/github.com/hyperledger/fabric/peer/

    ORDERER_CA=${BASE}crypto/ordererOrganizations/networkiot.com/orderers/orderer.networkiot.com/msp/tlscacerts/tlsca.networkiot.com-cert.pem
    CHANNELS=${BASE}channel-artifacts

    startNetwork

    CLISERVICE=`docker ps --format='{{.Names}}' | grep cli`

    echo
    # Crear canal sensor
    echo "Creando canal sensorchannel"
    docker exec -it $CLISERVICE peer channel create -o orderer.networkiot.com:7050 -c sensorchannel -f ${CHANNELS}/sensorChannel.tx --tls true --cafile $ORDERER_CA
    
    sleep 5
    echo "Done"
    
    echo
    #Unir handler al canal sensor
    echo "Uniendo Peer Handler..."
    docker exec -it $CLISERVICE peer channel join -b sensorchannel.block
    echo "Done"

    echo
    # Crear canal linkage
    echo "Creando canal sensorchannel"
    docker exec -it $CLISERVICE peer channel create -o orderer.networkiot.com:7050 -c linkagechannel -f ${CHANNELS}/linkageChannel.tx --tls true --cafile $ORDERER_CA

    sleep 5
    echo "Done"

    echo
    #Unir handler al canal linkage
    echo "Uniendo Peer Handler..."
    docker exec -it $CLISERVICE peer channel join -b linkagechannel.block
    echo "Done"

    echo
    echo "Uniendo Peer Sensor..."
    docker exec -e "CORE_PEER_LOCALMSPID=SensorMSP" \
    -e "CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/sensor.networkiot.com/peers/peer0.sensor.networkiot.com/tls/ca.crt" \
    -e "CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/sensor.networkiot.com/users/Admin@sensor.networkiot.com/msp" \
    -e "CORE_PEER_TLS_CERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/sensor.networkiot.com/peers/peer0.sensor.networkiot.com/tls/server.crt" \
    -e "CORE_PEER_TLS_KEY_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/sensor.networkiot.com/peers/peer0.sensor.networkiot.com/tls/server.key" \
    -e "CORE_PEER_ADDRESS=peer0.sensor.networkiot.com:7051" \
    -it $CLISERVICE peer channel join -b sensorchannel.block
    echo "Done"

    echo
    echo "Uniendo Peer Linkage..."
    docker exec -e "CORE_PEER_LOCALMSPID=LinkageMSP" \
    -e "CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/linkage.networkiot.com/peers/peer0.linkage.networkiot.com/tls/ca.crt" \
    -e "CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/linkage.networkiot.com/users/Admin@linkage.networkiot.com/msp" \
    -e "CORE_PEER_TLS_CERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/linkage.networkiot.com/peers/peer0.linkage.networkiot.com/tls/server.crt" \
    -e "CORE_PEER_TLS_KEY_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/linkage.networkiot.com/peers/peer0.linkage.networkiot.com/tls/server.key" \
    -e "CORE_PEER_ADDRESS=peer0.linkage.networkiot.com:7051" \
    -it $CLISERVICE peer channel join -b linkagechannel.block
    echo "Done"
}


startNetwork() {
    set -ev

    echo "Iniciando servicios..."
    docker stack deploy --compose-file docker-compose.yaml blockchainIoT
    
    sleep 10
    
    docker service ls
}


stopNetwork() {
    set -ev

    echo "Parando servicios..."
    docker stack rm blockchainIoT
    echo "Done"
}


removeNetwork() {
    stopNetwork

    echo "Eliminando red networkiot..."
    docker network rm networkiot
    echo "Done"

    # eliminamos cualquier configuracion
    echo
    echo "Eliminando configuracion previa..."
    rm -fr channel-artifacts/*
    rm -fr crypto-config
    ssh ubuntu@192.168.0.31 rm -fr $PWD/channel-artifacts/*
    ssh ubuntu@192.168.0.31 rm -fr $PWD/crypto-config
    
    ssh ubuntu@192.168.0.32 rm -fr $PWD/channel-artifacts/*
    ssh ubuntu@192.168.0.32 rm -fr $PWD/crypto-config
    echo "Done"
}


MODE=$1

if [ "${MODE}" == "up" ]; then                              # Activar red
    upNetwork
elif [ "${MODE}" == "start" ]; then                           # Comenzar red
    startNetwork
elif [ "${MODE}" == "stop" ]; then                          # Parar red
    stopNetwork
elif [ "${MODE}" == "generate" ]; then                      # Generar red
    generateNetwork
elif [ "${MODE}" == "restart" ]; then                       # Reiniciar red
    startNetwork
    stopNetwork
elif [ "${MODE}" == "remove" ]; then                        # Eliminar red
    removeNetwork
elif [ "${MODE}" == "" ] || [ "${MODE}" == "help" ]; then   # Mostrar la ayuda 
    printHelp
    exit 0
fi