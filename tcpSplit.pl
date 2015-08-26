#!/usr/bin/perl

#Based on code from https://ask.wireshark.org/questions/16690/split-pcap-file-into-smaller-pcap-file-according-to-tcp-flow

# Copyright (C) 2015  Jesse McGraw (jlmcgraw@gmail.com)
#
#-------------------------------------------------------------------------------
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see [http://www.gnu.org/licenses/].
#-------------------------------------------------------------------------------

#todo
#
#done
# switch to decide whether to pick up only streams started during the capture or pre-existing ones

use Modern::Perl '2014';
use Data::Dumper;
use Params::Validate qw(:all);
use Carp;
use Getopt::Std;
use vars qw/ %opt /;

#Define the valid command line options
my $opt_string = 's';
my $arg_num    = scalar @ARGV;

#We need at least one argument
if ( $arg_num < 1 ) {
    usage();
    exit(1);
}

#This will fail if we receive an invalid option
unless ( getopts( "$opt_string", \%opt ) ) {
    usage();
    exit(1);
}

exit main(@ARGV);

sub main {

    #Get command line parameters
    my $inputCaptureFilename = $ARGV[0] || usage();

    #Find conversations in the supplied capture file
    my $flowHashReference = identifyTcpConversations($inputCaptureFilename);

    #In case you're curious what was found
    #     say Dumper $flowHashReference;

    #For each conversation, extract its packets to a unique file
    for my $conversationDataKey ( keys %{$flowHashReference} ) {

        #What we want to call the new capture file
        my $filename = $flowHashReference->{$conversationDataKey}{id} . "-"
            . $conversationDataKey;

        #Construct the tcpdump command to only emit the packets for this
        #conversation
        my $tcpDumpCommand = "
        tcpdump 
            -n 
            -r \"$inputCaptureFilename\"
            -w \"$filename.pcap\" 
            \"
            tcp 
            and host $flowHashReference->{$conversationDataKey}{src_ip} 
            and host $flowHashReference->{$conversationDataKey}{dst_ip} 
            and port $flowHashReference->{$conversationDataKey}{src_port} 
            and port $flowHashReference->{$conversationDataKey}{dst_port} 
            \"
        ";

        #Execute it
        mySystem($tcpDumpCommand);
    }
    return 0;
}

sub identifyTcpConversations {

    #Find unique streams in the capture file
    my ($inputCaptureFilename) = validate_pos( @_, { type => SCALAR } );

    #Hash of bidirectional streams from this capture
    my %streams;

    #A timestamp regex
    my $timeStampRegex = qr/\d{2} :
                            \d{2} :
                            \d{2} [\.] \d+/mx;

    #An octet
    my $octetRegex = qr/(?:25[0-5]|2[0-4]\d|[01]?\d\d?)/mx;

    #An IP address is made of octets
    my $ipv4AddressRegex = qr/$octetRegex\.
			      $octetRegex\.
			      $octetRegex\.
			      $octetRegex/mx;

    #Counter of unique streams
    my $streamCounter;

    #All TCP traffic
    my $tcpDumpAllTcpFilter = "tcp";

    #Only packets with a SYN flag set
    my $tcpDumpOnlySynFilter = "\"tcp[tcpflags] & (tcp-syn) != 0\"
                            and \"tcp[tcpflags] & (tcp-ack) == 0\"
                                ";

    #Choose the tcp filter based on command line option
    #Default is to get all tcp traffic
    my $chosenFilter = $tcpDumpAllTcpFilter;
    if ( $opt{s} ) { $chosenFilter = $tcpDumpOnlySynFilter; }

    #Construct the tcpdump command
    my $tcpDumpCommand = "tcpdump 
                            -n 
                            -r \"$inputCaptureFilename\"
                            $chosenFilter
                            ";

    #and execute it
    my $tcpdumpOutput = mySystem($tcpDumpCommand);

    #Go through each line of the output
    for ( split /^/, $tcpdumpOutput ) {
        if (m/
                \A
                    $timeStampRegex
                \s+
                    IP 
                \s+
                    (?<src_ip> $ipv4AddressRegex )
                    [\.]
                    (?<src_port> \d+) 
                \s+
                    >
                \s+
                    (?<dst_ip> $ipv4AddressRegex )
                    [\.]
                    (?<dst_port> \d+ )
            /xms
            )
        {
            #             say "$+{src_ip} $+{src_port} $+{dst_ip} $+{dst_port}";

            #Add a new stream entry only if an entry for either direction doesn't exist
            if ((   !exists $streams{
                        "$+{dst_ip}:$+{dst_port}-$+{src_ip}:$+{src_port}"}
                )
                && (!exists $streams{
                        "$+{src_ip}:$+{src_port}-$+{dst_ip}:$+{dst_port}"} )
                )
            {
                #Found a new stream so increment counter
                $streamCounter++;

                #Add a hash for it
                $streams{"$+{src_ip}:$+{src_port}-$+{dst_ip}:$+{dst_port}"}
                    = {
                    id       => $streamCounter,
                    src_ip   => $+{src_ip},
                    src_port => $+{src_port},
                    dst_ip   => $+{dst_ip},
                    dst_port => $+{dst_port},
                    };
            }

        }
        else {
            #say "Unmatched output: $_";
        }
    }

    #Return a reference to this hash
    return \%streams;
}

sub mySystem {

    #Execute an external command
    my ($myExternalCommand)
        = validate_pos( @_, { type => SCALAR } );

    #Remove linefeeds from the command (done so that I could break up long commands for legibility
    $myExternalCommand =~ s/\R//g;

    #Execute it
    my $externalCommandOutput = qx($myExternalCommand);

    my $retval = $? >> 8;

    croak "External command:
        $myExternalCommand \n Return code was $retval"
        if ( $retval != 0 );

    return $externalCommandOutput;
}

sub usage {
    say "";
    say "Usage:";
    say "   $0 [-s] <capture file>";
    say "       -s     Only capture conversations begun during the capture";
    say "";
    exit 1;
}
