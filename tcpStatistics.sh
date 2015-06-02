#!/bin/bash
set -eu                # Always put this in Bourne shell scripts
IFS="`printf '\n\t'`"  # Always put this in Bourne shell scripts

#Did we specify an input capture file?
if [ "$#" -ne 1 ] ; then
  echo "Usage: $0 capture_file" >&2
  exit 1
fi

# Take the input capture file as a command-line argument to the script
IN_PCAP_FILE=$1

#Does that capture file exist?
if [ ! -f $IN_PCAP_FILE ]; then
    echo "$IN_PCAP_FILE doesn't exist"
    exit 1
fi

tshark -r $IN_PCAP_FILE -q -z io,stat,0,\
"COUNT(tcp.analysis.retransmission) tcp.analysis.retransmission",\
"COUNT(tcp.analysis.duplicate_ack) tcp.analysis.duplicate_ack",\
"COUNT(tcp.analysis.lost_segment) tcp.analysis.lost_segment",\
"COUNT(tcp.analysis.fast_retransmission) tcp.analysis.fast_retransmission"

tshark -r $IN_PCAP_FILE -q -z conv,tcp