#!/bin/bash
set -eu                # Always put this in Bourne shell scripts
IFS=$(printf '\n\t')  # Always put this in Bourne shell scripts

#Install wireshark, tshark, cpanminus, carton
sudo apt \
        install \
            wireshark \
            tshark \
            cpanminus \
            carton \
            build-essential
            
#Set up current user to capture network data
set +e
sudo adduser $USER wireshark
set -e

#update local perl libraries
carton install   
