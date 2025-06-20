#!/bin/bash

# Function to print status messages
print_status() {
    echo "[INFO] $1"
}

print_error() {
    echo "[ERROR] $1" >&2
}

print_warning() {
    echo "[WARNING] $1"
}

# Check if the script is run as root
#if [ "$(id -u)" != "0" ]; then
#  echo "This script must be run as root or with sudo." 1>&2
#  exit 1
#fi

current_path=$(pwd)
#bash $current_path/install-go.sh 

source $HOME/.bashrc
ulimit -n 16384

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0

# Get OS and version
OS=$(awk -F '=' '/^NAME/{print $2}' /etc/os-release | awk '{print $1}' | tr -d '"')
VERSION=$(awk -F '=' '/^VERSION_ID/{print $2}' /etc/os-release | awk '{print $1}' | tr -d '"')

# Define the binary and installation paths
BINARY="cintarad"
INSTALL_PATH="/usr/local/bin/"
# INSTALL_PATH="/root/go/bin/"

# Check if the OS is Ubuntu and the version is either 20.04 or 22.04
if [ "$OS" = "Ubuntu" ] && { [ "$VERSION" = "20.04" ] || [ "$VERSION" = "22.04" ]; }; then
    print_status "Starting installation for Ubuntu $VERSION..."
    print_status "Binary: $BINARY"
    print_status "Install path: $INSTALL_PATH"
    print_status "Downloading cintarad binary for Ubuntu $VERSION..."
    
    # Update package lists and install necessary packages
    print_status "Installing system dependencies..."
    sudo apt-get update -y || print_error "Failed to update package lists"
    sudo apt-get install -y build-essential jq wget unzip || print_error "Failed to install dependencies"
    
    # Download the binary
    DOWNLOAD_URL="https://github.com/Cintaraio/cintara-testnet-script/releases/download/ubuntu${VERSION}/cintarad"
    print_status "Download URL: $DOWNLOAD_URL"
    
    # Remove existing binary if present
    if [ -f "$BINARY" ]; then
        rm -f "$BINARY"
    fi
    
    # Download with error checking
    if command -v wget >/dev/null 2>&1; then
        wget "$DOWNLOAD_URL" -O "$BINARY"
    elif command -v curl >/dev/null 2>&1; then
        curl -L "$DOWNLOAD_URL" -o "$BINARY"
    else
        print_error "Neither wget nor curl is installed. Please install one of them."
        exit 1
    fi
    
    # Verify download
    if [ ! -f "$BINARY" ]; then
        print_error "Failed to download binary"
        exit 1
    fi
    
    # Make the binary executable
    chmod +x "$BINARY"
    
    # Verify binary works
    if ./"$BINARY" version >/dev/null 2>&1; then
        print_status "Binary downloaded and verified successfully"
    else
        print_warning "Binary downloaded but version check failed"
    fi
    
    # Check if the installation path exists
    if [ -d "$INSTALL_PATH" ]; then
        sudo cp "$current_path/$BINARY" "$INSTALL_PATH" && sudo chmod +x "${INSTALL_PATH}${BINARY}"
        echo "$BINARY installed or updated successfully!"
    else
        echo "Installation path $INSTALL_PATH does not exist. Please create it."
        exit 1
    fi
else
    echo "Please check the OS version support; at this time, only Ubuntu 20.04 and 22.04 are supported."
    exit 1
fi

#==========================================================================================================================================
echo "============================================================================================================"
echo "Enter the Name for the node:"
echo "============================================================================================================"
read -r MONIKER
KEYS="key3"
CHAINID="cintara_11001-1"
KEYRING="os"
KEYALGO="eth_secp256k1"
LOGLEVEL="info"

# Set dedicated home directory for the cintarad instance
HOMEDIR="/data/.tmp-cintarad"

# Path variables
CONFIG=$HOMEDIR/config/config.toml
APP_TOML=$HOMEDIR/config/app.toml
CLIENT=$HOMEDIR/config/client.toml
GENESIS=$HOMEDIR/config/genesis.json
TMP_GENESIS=$HOMEDIR/config/tmp_genesis.json

# validate dependencies are installed
command -v jq >/dev/null 2>&1 || {
    echo >&2 "jq not installed. More info: https://stedolan.github.io/jq/download/"
    exit 1
}

# used to exit on first error
set -e

# User prompt if an existing local node configuration is found.
if [ -d "$HOMEDIR" ]; then
    printf "\nAn existing folder at '%s' was found. You can choose to delete this folder and start a new local node with new keys from genesis. When declined, the existing local node is started. \n" "$HOMEDIR"
    echo "Overwrite the existing configuration and start a new local node? [y/n]"
    read -r overwrite
else
    overwrite="Y"
fi

# Setup local node if overwrite is set to Yes, otherwise skip setup
if [[ $overwrite == "y" || $overwrite == "Y" ]]; then
    # Remove the previous folder
    file_path="/etc/systemd/system/cintarachain.service"

    # Check if the file exists
    if [ -e "$file_path" ]; then
        sudo systemctl stop cintarachain.service
        echo "The file $file_path exists."
    fi
    sudo rm -rf "$HOMEDIR"

    # Set client config
    cintarad config set client chain-id "$CHAINID" --home "$HOMEDIR"
    cintarad config set client keyring-backend "$KEYRING" --home "$HOMEDIR"

    echo "===========================Copy these keys with mnemonics and save it in safe place ==================================="
    cintarad keys add $KEYS --keyring-backend $KEYRING --algo $KEYALGO --home "$HOMEDIR"
    echo "========================================================================================================================"
    echo "========================================================================================================================"
    cintarad init $MONIKER -o --chain-id $CHAINID --home "$HOMEDIR"
    
    # Allocate genesis accounts (cosmos formatted addresses)
    cintarad add-genesis-account $KEYS 100000000000000000000000000000cint --keyring-backend $KEYRING --home "$HOMEDIR"

    # Sign genesis transaction
    cintarad gentx ${KEYS} 1000000000000000000000000cint --keyring-backend $KEYRING --chain-id $CHAINID --home "$HOMEDIR"
    
    # Collect genesis tx
    cintarad collect-gentxs --home "$HOMEDIR"
    
    # Change parameter token denominations to cint
    jq '.app_state["staking"]["params"]["bond_denom"]="cint"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["crisis"]["constant_fee"]["denom"]="cint"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["gov"]["deposit_params"]["min_deposit"][0]["denom"]="cint"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["gov"]["params"]["min_deposit"][0]["denom"]="cint"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["mint"]["params"]["mint_denom"]="cint"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

    jq '.consensus_params["block"]["max_bytes"]="8388608"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["mint"]["params"]["blocks_per_year"]="31536000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["mint"]["minter"]["inflation"]="0.080000000000000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["mint"]["params"]["inflation_rate_change"]="0.080000000000000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["mint"]["params"]["inflation_max"]="0.080000000000000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["mint"]["params"]["inflation_min"]="0.080000000000000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

    # jq '.app_state["feemarket"]["params"]["base_fee"]="182855642857142"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    # Set gas limit in genesis
    jq '.consensus_params["block"]["max_gas"]="10000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.consensus_params["block"]["max_bytes"]="5242880"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["mint"]["params"]["blocks_per_year"]="5256000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["gov"]["deposit_params"]["max_deposit_period"]="1800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["gov"]["params"]["max_deposit_period"]="1800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["gov"]["voting_params"]["voting_period"]="1800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["gov"]["params"]["voting_period"]="1800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["staking"]["params"]["unbonding_time"]="1800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["slashing"]["params"]["downtime_jail_duration"]="600s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
    jq '.app_state["gov"]["params"]["expedited_voting_period"]="1200s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

    #changes status in app,config files
    sed -i 's/timeout_commit = "3s"/timeout_commit = "6s"/g' "$CONFIG"
    #sed -i 's/pruning = "default"/pruning = "custom"/g' "$APP_TOML"
    sed -i 's/pruning-keep-recent = "0"/pruning-keep-recent = "100000"/g' "$APP_TOML"
    sed -i 's/pruning-interval = "0"/pruning-interval = "100"/g' "$APP_TOML"
    sed -i 's/seeds = ""/seeds = ""/g' "$CONFIG"
    sed -i 's/prometheus = false/prometheus = true/' "$CONFIG"
    sed -i 's/experimental_websocket_write_buffer_size = 200/experimental_websocket_write_buffer_size = 600/' "$CONFIG"
    sed -i 's/prometheus-retention-time  = "0"/prometheus-retention-time  = "1000000000000"/g' "$APP_TOML"
    sed -i 's/enabled = false/enabled = true/g' "$APP_TOML"
    sed -i 's/minimum-gas-prices = "0cint"/minimum-gas-prices = "0.25cint"/g' "$APP_TOML"
    sed -i 's/enable = false/enable = true/g' "$APP_TOML"
    sed -i 's/swagger = false/swagger = true/g' "$APP_TOML"
    sed -i 's/enabled-unsafe-cors = false/enabled-unsafe-cors = true/g' "$APP_TOML"
    sed -i 's/enable-unsafe-cors = false/enable-unsafe-cors = true/g' "$APP_TOML"
    sed -i '/\[rosetta\]/,/^\[.*\]/ s/enable = true/enable = false/' "$APP_TOML"
    sed -i 's/localhost/0.0.0.0/g' "$APP_TOML"
    sed -i 's/localhost/0.0.0.0/g' "$CONFIG"
    sed -i 's/:26660/0.0.0.0:26660/g' "$CONFIG"
    sed -i 's/localhost/0.0.0.0/g' "$CLIENT"
    sed -i 's/127.0.0.1/0.0.0.0/g' "$APP_TOML"
    sed -i 's/127.0.0.1/0.0.0.0/g' "$CONFIG"
    sed -i 's/127.0.0.1/0.0.0.0/g' "$CLIENT"
    sed -i 's/\[\]/["*"]/g' "$CONFIG"
    sed -i 's/\["\*",\]/["*"]/g' "$CONFIG"

    # sed -i 's/enable = false/enable = true/g' "$CONFIG"
    # sed -i 's/rpc_servers \s*=\s* ""/rpc_servers = ""/g' "$CONFIG"
    # sed -i 's/trust_hash \s*=\s* ""/trust_hash = "8223EF205275D355369D43391DA33A7AD7355932B50E50A7C092A0729084C739"/g' "$CONFIG"
    # sed -i 's/trust_height = 0/trust_height = 5063000/g' "$CONFIG"
    # sed -i 's/trust_period = "112h0m0s"/trust_period = "168h0m0s"/g' "$CONFIG"
    # sed -i 's/flush_throttle_timeout = "100ms"/flush_throttle_timeout = "10ms"/g' "$CONFIG"
    # sed -i 's/peer_gossip_sleep_duration = "100ms"/peer_gossip_sleep_duration = "10ms"/g' "$CONFIG"

    # these are some of the node ids help to sync the node with p2p connections
    sed -i 's/persistent_peers \s*=\s* ""/persistent_peers = "556fb5330315d3f2b6169fe810a87d26376a42e7@35.155.113.160:26656,d827e98de74dc25aada3b0bb4f7e78fbf3de75dd@35.82.72.170:26656,19675c9f2711234238d10233b10cacbe5576be27@52.32.249.156:26656"/g' "$CONFIG"

    # remove the genesis file from binary
    rm -rf $HOMEDIR/config/genesis.json

    # paste the genesis file
    cp $current_path/genesis.json $HOMEDIR/config

    # Run this to ensure everything worked and that the genesis file is setup correctly
    cintarad validate-genesis --home "$HOMEDIR"

    echo "export DAEMON_NAME=cintarad" >> ~/.profile
    echo "export DAEMON_HOME=\"$HOMEDIR\"" >> ~/.profile
    source ~/.profile
    echo $DAEMON_HOME
    echo $DAEMON_NAME

    cosmovisor init "${INSTALL_PATH}${BINARY}"

    TENDERMINTPUBKEY=$(cintarad tendermint show-validator --home $HOMEDIR | grep "key" | cut -c12-)
    NodeId=$(cintarad tendermint show-node-id --home $HOMEDIR --keyring-backend $KEYRING)
    BECH32ADDRESS=$(cintarad keys show ${KEYS} --home $HOMEDIR --keyring-backend $KEYRING| grep "address" | cut -c12-)

    echo "========================================================================================================================"
    echo "tendermint Key==== "$TENDERMINTPUBKEY
    echo "BECH32Address==== "$BECH32ADDRESS
    echo "NodeId ===" $NodeId
    echo "========================================================================================================================"

fi

#========================================================================================================================================================
sudo tee /etc/systemd/system/cintarachain.service > /dev/null <<EOF
[Unit]
Description=cintara Node
Wants=network-online.target
After=network-online.target

[Service]
User=$(whoami)
Group=$(whoami)
Type=simple
ExecStart=/home/$(whoami)/go/bin/cosmovisor run start --home $HOMEDIR
Restart=always
RestartSec=3
LimitNOFILE=4096
Environment="DAEMON_NAME=cintarad"
Environment="DAEMON_HOME=$HOMEDIR"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_LOG_BUFFER_SIZE=512"
Environment="UNSAFE_SKIP_BACKUP=false"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable cintarachain.service
# cintarad tendermint unsafe-reset-all --home $HOMEDIR
sudo systemctl start cintarachain.service