#Some small network related scripts

##tcpSplit.pl
	Splits an input pcap capture file into a separate file for each stream using tcpdump
	Much faster than extractTcpStreams.sh

##extractTcpStreams.sh
	Splits an input pcap capture file into a separate file for each stream using tshark
	Currently the name format is "stream ID - source IP - destination IP - destination port"

##tcpStatistics.sh
	Use tshark to print some statistics about a given pcap network capture file.
	
##aclUsage.pl
	Tally up overall ACL hits from Solarwinds Network Configuration manager output of Cisco IOS "show ip access-lists"

##splitNcmOutputIntoFilePerDevice.pl
	Split an input Solarwinds Network Configuration manager output log into a separate file for each device
        
##bgpAsnsFromConfigs.pl
	Make a graphviz diagram of how BGP ASNs interconnect from a bunch of Cisco config files
	(sorry, no Juniper etc. yet)
