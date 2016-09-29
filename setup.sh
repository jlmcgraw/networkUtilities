#!/bin/bash
set -eu                # Always put this in Bourne shell scripts
IFS=$(printf '\n\t')  # Always put this in Bourne shell scripts

#Install wireshark, tshark, cpanminus, carton
sudo apt \
        install \
            wireshark \
            tshark \
            cpanminus \
            carton
            
#Set up current user to capture network data            
sudo adduser $USER wireshark

#update local perl libraries
carton install   
