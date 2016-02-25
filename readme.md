#Some small network related scripts
	To get started:
		#Install Carton dependency manager
		cpanm Carton

		#update local libraries
		carton install    

	Look at setup.sh for how to add wireshark user, globally install 
	dependencies etc.

##iosToHtml.pl
	Convert an IOS/NXOS/ACE/ASA config file into very basic HTML, creating links 
	between commands referencing lists and that list (e.g. access lists, 
	route maps, prefix lists, service-policies etc etc).
	
	Will also link between files for various things (route next hop, interface
	subnets etc) for all files in the set you're analyzing

	Very useful for trying to follow the flow of complex configurations

	e.g.:
		./iosToHtml.pl -e -h -f -s ./sample_configs/*.cfg
		
	Items highlighted in orange are unused in this config
	
[Example 1](http://htmlpreview.github.com/?https://github.com/jlmcgraw/networkUtilities/blob/master/ios_to_html_examp;es/html_test_case_1.cfg.html)
	
[Example 2](http://htmlpreview.github.com/?https://github.com/jlmcgraw/networkUtilities/blob/master/ios_to_html_examp;es/html_test_case_10.cfg.html)

##annotate_hosts_and_networks_in_file.pl
	Parse a text file (router config, ACL etc etc) containing host and/or 
	wildcard mask entries and test reachability for each host and network 
	mentioned in it.  Create simple HTML output with in-line color coded 
	anotations for everything found (status, host count etc)

	Can also use a list of known BGP networks (see bgp_asn_path_via_snmp.pl to create it) 
	to test whether a network is specifically known 

##create_host_info_hashes.pl
	Create a hash used by iosToHtml.pl to allow linking between configurations
	Automatically called by iosToHtml.pl as needed.  
	Delete "host_info_hash.stored" to recreate it for new or additional files

##tcpSplit.pl
	Splits an input pcap capture file into a separate file for each stream using
	tcpdump
	Much faster than extractTcpStreams.sh

##tcpStatistics.sh
	Use tshark to print some statistics about a given pcap network capture file.
	
##aclUsage.pl
	Tally up overall ACL hits from Solarwinds Network Configuration manager 
	output of Cisco IOS "show ip access-lists" for multiple devices

##splitNcmOutputIntoFilePerDevice.pl
	Split an input Solarwinds Network Configuration manager output log into a 
	separate file for each device
        
##bgpAsnsFromConfigs.pl
	Make a graphviz diagram of how BGP ASNs interconnect from a bunch of Cisco 
	config files (sorry, no Juniper etc. yet)

##parseMlsQosInterfaceStatistics.pl
	Parse the output of "show mls qos interface statistics" from a Cisco Catalyst
	 3560/3750 switch	
	Combines the counts of all of the interfaces to get an idea of the overall
	 mix of incoming/outgoing COS/DSCP values and which queues are queuing and 
   	 dropping the most packets

##parseRiverbedInterceptorRules.pl
	Parse some rules from Riverbed Interceptor configurations into an Excel 
	spreadsheet to make reading/organizing them easier


##extractTcpStreams.sh
	Splits an input pcap capture file into a separate file for each stream using tshark
	Currently the name format is "stream ID - source IP - destination IP - destination port"
