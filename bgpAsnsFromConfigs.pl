#!/usr/bin/perl

#You can all the configs you're interested in into one bundle like this:
#   for each in *.config; do cat $each; echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"; done > allconfigs.txt
#
#or do it in command substituion:
#   bgpAsnsFromConfigs.pl < <(for each in *.config; do cat $each; echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"; done)

use Modern::Perl '2014';
use autodie;

# use NetAddr::IP;
# use File::Slurp;
# use Getopt::Std;
# use vars qw/ %opt /;
# use Params::Validate qw(:all);
use Data::Dumper;
$Data::Dumper::Indent   = 2;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Purity   = 1;
use GraphViz;

# #don't buffer stdout
# $| = 1;

exit main(@ARGV);

sub main {

    #Check that we're redirecting stdin from a file
    if (-t) {
        say "You must redirect input from one or more configs ";
        say "Usage: $0 < configFile";
        exit 1;
    }

    my %asnHash;
    my $asNumber;
    my $bgpNeighbor;
    my $remoteAsn;
    my $remoteAsnHitCount;
    my $bgpNetwork;
    my $bgpNetworkMask;
    my $hostName;

    #an octet is a number between 0 and 255
    my $octetRegex = qr/(?:
                            [0-9]{1,2}      #0-99
                        |  1[0-9]{2}        #100-199
                        |  2[0-4][0-9]      #200-249
                        | 25[0-5])          #250-255
                        /mx;

    #An IP address consists of 4 octets
    my $ipv4SubnetRegex = qr/(?:$octetRegex)\.
			     (?:$octetRegex)\.
			     (?:$octetRegex)\.
			     (?:$octetRegex)/x;

    my $asnGraph =
      GraphViz->new( directed => 0, layout => 'sfdp', overlap => 'scalexy' );

    open( out_file,     ">./twAsn.dot" );
    open( out_file_png, ">./twAsn.png" );
    open( out_file_svg, ">./twAsn.svg" );

    #read from STDIN
    while (<>) {

        #Find bgp config section
        if (
            $_ =~ /
            ^
                \s*
                    router 
                \s+
                    bgp
                \s+
                    (?<asNumber>\d+)
                \s*
            $
            /ix
          )
        {
            $asNumber = $bgpNeighbor = $remoteAsn = undef;
            $asNumber = $+{asNumber};

            if ( $asNumber && $hostName ) {
                $asnHash{$asNumber}{"hosts"}{$hostName} = 1;
            }
        }
        elsif (
            $_ =~ /
            ^
                \s*
                    hostname
                \s+ 
                    (?<hostName> [\w-]+ )
            /ix
          )
        {
            $hostName = $+{hostName};

            #If we have an active ASN add this hostname to it
            if ( $asNumber && $hostName ) {
                $asnHash{$asNumber}{"hosts"}{$hostName} = 1;
            }
        }
        elsif (
            $_ =~ /
            ^
                \s*
                    router
                \s+
                    (?:rip | eigrp | ospf | isis)
            /ix
          )
        {
            #Clear variables on a new section of cisco config
            $asNumber = $bgpNeighbor = $remoteAsn = undef;
        }

        elsif (
            $_ =~ /
            ^
                !
            $
            /ix
          )
        {
            #Clear variables between config files in a long stream
            $asNumber = $bgpNeighbor = $remoteAsn = undef;
        }
        #
        elsif (
            $_ =~ /
                XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
            /ix
          )
        {
            #Clear variables between files
            $asNumber = $bgpNeighbor = $remoteAsn = $hostName = undef;
        }

        #find neigbors
        elsif (
            $_ =~ /
            ^                                                   #beginning of line
                \s*                                             #maybe some whitespace
                neighbor
                \s+
                (?<bgpNeighbor> $ipv4SubnetRegex)                                #ACL entry number
                \s+ 
                remote-as                                            #followed by whitespace
                \s+
                (?<remoteAsn> \d+ )                          #The ACL up to the possible  "matches" portion
                \s*                                         # zero or more whitespace
            $
            /ix
          )
        {
            if ($asNumber) {
                $remoteAsn         = $+{remoteAsn};
                $bgpNeighbor       = $+{bgpNeighbor};
                $remoteAsnHitCount = $+{remoteAsnHitCount};

                #How many different times have we seen this ASN
                $asnHash{$asNumber}{"devicesUsedOn"} += 1;
                $asnHash{$asNumber}{"neighbors"}{$bgpNeighbor}{"remoteAsn"} =
                  $remoteAsn;

                #Add an entry for the remote asn
                #How many different times have we seen the remote ASN
                $asnHash{$remoteAsn}{"devicesUsedOn"} += 1;
            }

        }

        #find networks
        elsif (
            $_ =~ /
            ^                                                   #beginning of line
                \s*                                             #maybe some whitespace
                network
                \s+
                (?<bgpNetwork> $ipv4SubnetRegex)                                #ACL entry number
                \s+ 
                mask                                        #followed by whitespace
                \s+
                (?<bgpNetworkMask> $ipv4SubnetRegex )         #The ACL up to the possible  "matches" portion
                \s*                                         # zero or more whitespace
            $
            /ix
          )
        {
            $bgpNetwork     = $+{bgpNetwork};
            $bgpNetworkMask = $+{bgpNetworkMask};

            if ($asNumber) {
                $asnHash{$asNumber}{"networks"}
                  { $bgpNetwork . " " . $bgpNetworkMask } = 1;
            }

        }
        else {
            #Any lines that don't match fall through to here, just so we can check that we're covering all desirable inputs
            #say $_;
        }

    }

    #Debuggery
    #say Dumper \%asnHash;
    
    #For every ASN we found
    while ( my ( $bgpAsn, $bgpAsnHashRef ) = each %asnHash ) {

        #Add all hosts in the AS to the label
        my $label = $bgpAsn . "\n";
        
        
        #Make a list of all hosts in this AS
        while ( my ( $hostKey, $hostValue ) =
            each %{ $bgpAsnHashRef->{"hosts"} } )

        {
            $label = $label . $hostKey . "\n";
        }
     
        #In case you're curious
        #say $label;
        
        #Create a node for this ASN
        #Make it bigger relative to how often it was mentioned
        $asnGraph->add_node(
            $bgpAsn,
            label    => "$label",
            shape    => 'ellipse',
            style    => 'filled',
            fontsize => $asnHash{$bgpAsn}{"devicesUsedOn"} * 1.5 + 10,
            color    => 'red'
        );

        #Debuggery
        #say "key: $bgpAsn, value:  $bgpAsnHashRef";
        #print Dumper $bgpAsnHashRef;

        #Add edges for all neighbor ASNs
        while ( my ( $neighborKey, $neighborHashReference ) =
            each %{ $bgpAsnHashRef->{"neighbors"} } )

        {
            #Debuggery
            #say "key: $neighborKey, value:  $neighborHashReference";
            #print Dumper $neighborHashReference;

            my $remoteAsn = $neighborHashReference->{"remoteAsn"};

            #say $remoteAsn;

            #For now don't include iBGP peers
            if ( ( $bgpAsn && $remoteAsn ) && ( $bgpAsn != $remoteAsn ) ) {
                $asnGraph->add_edge( $bgpAsn => $remoteAsn );
            }
        }

    }

    #Save the graphiz objects
    print out_file $asnGraph->as_text;
    print out_file_png $asnGraph->as_png;
    print out_file_svg $asnGraph->as_svg;
}
