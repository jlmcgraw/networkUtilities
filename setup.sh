#!/bin/bash
set -eu                # Always put this in Bourne shell scripts
IFS="`printf '\n\t'`"  # Always put this in Bourne shell scripts

sudo apt-get install wireshark tshark
sudo adduser $USER wireshark

sudo apt-get install libmodern-perl-perl libgraphviz-perl
