#!/bin/bash
set -eu                # Always put this in Bourne shell scripts
IFS="`printf '\n\t'`"  # Always put this in Bourne shell scripts

#Split an input capture file into a separate file for each stream

#Adapted from http://www.appneta.com/blog/how-to-easily-capture-tcp-conversation-streams/

#To-do
#   Compress each new capture file?
#   
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

#tshark filter for established flows
FLOW_ESTABLISHED_FILTER="(tcp.flags.syn == 1 && tcp.flags.ack == 0) || (tcp.flags.syn == 1 && tcp.flags.ack == 1)"

#tshark filter for SYN-only packets (beginning of new flows)
FLOW_START_FILTER="(tcp.flags.syn == 1 && tcp.flags.ack == 0)"

# Obtain the list of unique TCP stream IDs
TCP_STREAMS=$(tshark \
                -r $IN_PCAP_FILE \
                -Y "$FLOW_ESTABLISHED_FILTER" \
                -T fields \
                -e tcp.stream \
            | sort -n \
            | uniq)

# echo "Found these stream IDs for fully established flows"
# echo $TCP_STREAMS

#For each stream, pull out its packets and save to separate file
for stream in $TCP_STREAMS; do
    #The filter for only this stream
    STREAM_FILTER="tcp.stream==${stream}"
    
#         echo $stream
    
    #Get the source IP, destination IP and destination port from the initial SYN-only packet of each stream
    STREAM_INFO=$(tshark \
                    -r $IN_PCAP_FILE \
                    -Y "$FLOW_START_FILTER && $STREAM_FILTER" \
                    -T fields \
                    -e ip.src \
                    -e ip.dst \
                    -e tcp.dstport )
    
#         echo "STREAM_INFO: $STREAM_INFO"

    #Read that data into separate variables
    read -r IP_SOURCE IP_DESTINATION TCP_DESTINATION_PORT <<< "$STREAM_INFO"
    
    
#         echo "IP_SOURCE: $IP_SOURCE"
#         echo "IP_DESTINATION: $IP_DESTINATION"
#         echo "TCP_DESTINATION_PORT: $TCP_DESTINATION_PORT"

    #Check that all our variables are set before going any further
    if [[ "$IP_SOURCE" && "$IP_DESTINATION" && "$TCP_DESTINATION_PORT" ]]; then
        #Set the output file name based on our variables
        OUT_PCAP_FILE="./$stream-$IP_SOURCE-$IP_DESTINATION-$TCP_DESTINATION_PORT.pcapng"
        
        # Apply the stream ID filter and write out the filtered capture file
        tshark -r $IN_PCAP_FILE -Y "${STREAM_FILTER}" -w $OUT_PCAP_FILE
    fi

done