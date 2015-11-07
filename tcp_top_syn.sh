#!/bin/bash
set -eu                # Always put this in Bourne shell scripts
IFS=$(printf '\n\t')  # Always put this in Bourne shell scripts

TOP_X=10

#List the top sources and destination of SYN packets
#Yes, it's reading the capture file twice currently
#Inspiration from http://serverfault.com/questions/217605/how-to-capture-ack-or-syn-packets-by-tcpdumpv

#Did we specify an input capture file?
if [ "$#" -ne 1 ] ; then
  echo "Usage: $0 capture_file" >&2
  exit 1
fi

# Take the input capture file as a command-line argument to the script
IN_PCAP_FILE=$1

#Does that capture file exist?
if [ ! -f "$IN_PCAP_FILE" ]; then
    echo "$IN_PCAP_FILE doesn't exist"
    exit 1
fi

echo "Top $TOP_X sources"
tcpdump -r $IN_PCAP_FILE -n  \
  'tcp[tcpflags] & (tcp-syn) != 0' and 'tcp[tcpflags] & (tcp-ack) == 0' 2> /dev/null \
  | awk '{ print $3}' \
  | sort | uniq -c | sort -g -r | head -$TOP_X

echo "Top $TOP_X destinations"
tcpdump -r $IN_PCAP_FILE -n  \
  'tcp[tcpflags] & (tcp-syn) != 0' and 'tcp[tcpflags] & (tcp-ack) == 0' 2> /dev/null \
  | awk '{ print $5}' \
  | sort | uniq -c | sort -g -r | head -$TOP_X
  
  
# while :; do
#   date; 
#   tcpdump -i eth1 -n -c 100 \
#   'tcp[tcpflags] & (tcp-syn) != 0' and 
#   'tcp[tcpflags] & (tcp-ack) == 0' 2> /dev/null \
#   | awk '{ print $3}' \
#   | sort | uniq -c | sort | tail -5;
#   echo;
#   sleep 1
# done
