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
    my $asnNumber;
    my $bgpNeighbor;
    my $remoteAsn;
    my $remoteAsnHitCount;
    my $bgpNetwork;
    my $bgpNetworkMask;

    my $octetRegex = qr/(?:[0-9]{1,2} | 1[0-9]{2} | 2[0-4][0-9] | 25[0-5])/mx;

    my $ipv4SubnetRegex = qr/(?:$octetRegex)\.
			     (?:$octetRegex)\.
			     (?:$octetRegex)\.
			     (?:$octetRegex)/x;

    my $ipv4NetmaskRegex = qr/(?:25[0-5] | 2[0-4]\d | [01]?\d\d? )\.
			      (?:25[0-5] | 2[0-4]\d | [01]?\d\d? )\.
			      (?:25[0-5] | 2[0-4]\d | [01]?\d\d? )\.
			      (?:25[0-5] | 2[0-4]\d | [01]?\d\d? )/x;

    my $asnGraph = GraphViz->new( directed => 0, layout => 'neato' );

    open( out_file,     ">./twAsn.dot" );
    open( out_file_png, ">./twAsn.png" );

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
                    (?<asnNumber>\d+)
                \s*
            $
            /ix
          )
        {
            $asnNumber = $bgpNeighbor = $remoteAsn = undef;
            $asnNumber = $+{asnNumber};
        }
        elsif (
            $_ =~ /
            ^
                \s*
                    router 
            /ix
          )
        {
            #Clear variables on a new section of cisco config
            $asnNumber = $bgpNeighbor = $remoteAsn = undef;
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
            $asnNumber = $bgpNeighbor = $remoteAsn = undef;
        }
        #
        elsif (
            $_ =~ /
                XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
            /ix
          )
        {
            #Clear variables on any other routing process type
            $asnNumber = $bgpNeighbor = $remoteAsn = undef;
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
            if ($asnNumber) {
                $remoteAsn         = $+{remoteAsn};
                $bgpNeighbor       = $+{bgpNeighbor};
                $remoteAsnHitCount = $+{remoteAsnHitCount};

                #How many different times have we seen this ASN
                $asnHash{$asnNumber}{"devicesUsedOn"} += 1;
                $asnHash{$asnNumber}{"neighbors"}{$bgpNeighbor}{"remoteAsn"} =
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
            if ($asnNumber) {
                $asnHash{$asnNumber}{"networks"}
                  { $bgpNetwork . " " . $bgpNetworkMask } = 1;
            }

        }
        else {
            #Any lines that don't match fall through to here, just so we can check that we're covering all desirable inputs
            #say $_;
        }

    }

    #     say Dumper \%asnHash;

    while ( my ( $bgpAsn, $bgpAsnHashRef ) = each %asnHash ) {

        if ( 'HASH' eq ref $bgpAsnHashRef ) {

            #             say "key: $bgpAsn, value:  $bgpAsnHashRef";

            #             print Dumper $bgpAsnHashRef;

            while ( my ( $neighborKey, $neighborHashReference ) =
                each %{ $bgpAsnHashRef->{"neighbors"} } )

            {
                #                 say "key: $neighborKey, value:  $neighborHashReference";
                #                 print Dumper $neighborHashReference;

                my $remoteAsn = $neighborHashReference->{"remoteAsn"};

                #                 say $remoteAsn;

                $asnGraph->add_edge( $bgpAsn => $remoteAsn );

            }
        }

        #
        #             #         foreach my $neighborKey ( sort keys %{ $bgpAsnHashRef {"neighbors"} } ) {
        #             #
        #
        #                               say "key: $neighborKey value:  $remoteAsnHashRef";
        #             #
        #             #             # #             say ref $neighborHashReference;
        #             #             # #
        #             #             #             say "key: $neighborKey, value: " . %{$neighborHashReference{"remoteAsn"};
        #             #             # #             $asnGraph->add_node(
        #             #             # #                 $bgpAsn,
        #             #             # #                 label    => "$bgpAsn",
        #             #             # #                 shape    => 'ellipse',
        #             #             # #                 style    => 'filled',
        #             #             # #                 fontsize => $asnHash{$bgpAsn}{"devicesUsedOn"} * 1.5 + 10,
        #             #             # #                 color    => 'red',
        #             #             # #             );
        #         }
    }

    #     while ( $line = <peer_file> ) {
    #         if ( $line =~ m/^#/i ) {
    #             next;
    #         }
    #         @split_line = split( /\|/, $line );
    #         $as_relation = $split_line[2];
    #         if (
    #             !(
    #                    exists $as_hash{ $split_line[0] }
    #                 || exists $as_hash{ $split_line[1] }
    #             )
    #           )
    #         {
    #             next;
    #         }
    #
    #         for ( $i = 0 ; $i < 2 ; ++$i ) {
    #             if ( exists $as_hash{ $split_line[$i] } ) {
    #                 $g->add_node(
    #                     $split_line[$i],
    #                     label => "$as_hash{$split_line[$i]}",
    #                     shape => 'box',
    #                     style => 'filled',
    #                     color => 'green',
    #                     URL   => "http://bgp.he.net/AS$split_line[$i]"
    #                 );
    #             }
    #             else {
    #                 $as_name = &as_to_n( $split_line[$i] );
    #                 $g->add_node(
    #                     $split_line[$i],
    #                     label => "$as_name",
    #                     shape => 'ellipse',
    #                     style => 'filled',
    #                     color => 'red',
    #                     URL   => "http://bgp.he.net/AS$split_line[$i]"
    #                 );
    #             }
    #         }
    #         if ( $as_relation == -1 ) {
    #             $g->add_edge( $split_line[0] => $split_line[1] );
    #         }
    #     }
    print out_file $asnGraph->as_text;
    print out_file_png $asnGraph->as_png;
}
