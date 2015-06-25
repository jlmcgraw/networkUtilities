#!/bin/bash
set -eu                # Always put this in Bourne shell scripts
IFS=$(printf '\n\t')  # Always put this in Bourne shell scripts

#Split an input capture file into a separate file for each stream

#Adapted from http://www.appneta.com/blog/how-to-easily-capture-tcp-conversation-streams/

#To-do
#   Compress each new capture file?
#
#Done
#   Removed one read from each loop

#Did we specify an input capture file?
if [ "$#" -ne 1 ] ; then
  echo ""
  echo "Usage: $0 <capture_file>" >&2
  echo ""
  exit 1
fi

# Take the input capture file as a command-line argument to the script
IN_PCAP_FILE=$1

#Does that capture file exist?
if [ ! -f "$IN_PCAP_FILE" ]; then
    echo "$IN_PCAP_FILE doesn't exist"
    exit 1
fi

#All TCP traffic
ALL_TCP_FILTER="tcp";

#tshark filter for SYN-only packets (beginning of new stream)
#Note that these won't include flows started outside of the capture!
SYN_ONLY_FILTER="(tcp.flags.syn == 1 && tcp.flags.ack == 0)"

#SYN and ACK packets (response from server to client for new stream)
#Note that these won't include flows started outside of the capture!
SYN_ACK_FILTER="(tcp.flags.syn == 1 && tcp.flags.ack == 1)"

#tshark filter for fully established tcp streams (bidirectional flows)
#Note that these won't include flows started outside of the capture!
FLOW_ESTABLISHED_FILTER="( $SYN_ONLY_FILTER) || ( $SYN_ACK_FILTER )"

# Obtain the list of unique TCP stream IDs
#Filter on SYN_ACK_FILTER to get only streams that have response from server
#that means that (for example) ip.src below is the IP of the server
#Note that these won't include flows started outside of the capture!
TCP_STREAMS=$(
            tshark \
                -r "$IN_PCAP_FILE" \
                -Y "$SYN_ACK_FILTER" \
                -T fields \
                -e tcp.stream \
                -e ip.src \
                -e tcp.srcport \
                -e ip.dst \
                -e tcp.dstport \
            | sort -n \
            | uniq 
            )
            
#Make an array from that string
#This seems redundant but oh well
tcpStreamsArray=($TCP_STREAMS)

#If you're curious
# echo "Found these streams"
# echo $TCP_STREAMS

#count of all items in array
tcpStreamArrayLength=${#tcpStreamsArray[*]}

#data points for each entry
let points=5

#divided by size of each entry gives number of streams
let numberOfStreams=$tcpStreamArrayLength/$points;

echo Found $numberOfStreams streams


#Loop through all of the streams in our array and process them
for (( i=0; i<=$(( $numberOfStreams-1 )); i++ ))
  do
    #Pull the info for this chart from array
      streamId=${tcpStreamsArray[i*$points+0]}
      serverIp=${tcpStreamsArray[i*$points+1]}
    serverPort=${tcpStreamsArray[i*$points+2]}
      clientIp=${tcpStreamsArray[i*$points+3]}
    clientPort=${tcpStreamsArray[i*$points+4]}

    #Just so we know it's working
    echo    "$streamId | $clientIp : $clientPort -> $serverIp : $serverPort"

    #The filter for only this stream
    STREAM_FILTER="tcp.stream==$streamId"

    #Check that all our variables are set before going any further
    if [[ "$clientIp" && "$clientPort" && "$serverIp" && "$serverPort" ]]; then
        #Set the output file name based on our variables
        OUT_PCAP_FILE="./$streamId-$clientIp-$clientPort-$serverIp-$serverPort.pcapng"
        
#         # Apply the stream ID filter and write out the filtered capture file
#         tshark \
#             -r "$IN_PCAP_FILE" \
#             -Y "$STREAM_FILTER" \
#             -w $OUT_PCAP_FILE

#         #tcpdump seems to be about 10x faster than tshark so let's use it instead
        tcpdump \
            -n \
            -r "$IN_PCAP_FILE" \
            -w "$OUT_PCAP_FILE" \
            "tcp and host $clientIp and host $serverIp and port $clientPort and port $serverPort"
    fi

done
exit 0