#!/usr/bin/perl

# Create a bgp ASN map from stored hash data from bgp_asn_path_via_snmp

use strict;
use warnings;
use autodie;
use Getopt::Long;
use FindBin '$Bin';

#Use a local lib directory so users don't need to install modules
use lib "$FindBin::Bin/local/lib/perl5";
use Params::Validate qw(:all);
use Storable;
use Data::Dumper;

# The sort routine for Data::Dumper
$Data::Dumper::Sortkeys = sub {

    #Get all the keys for this hash
    my $keys = join '', keys %{ $_[0] };

    #Are they only numbers?
    if ( $keys =~ /^ [[:alnum:]]+ $/x ) {

        #Sort keys numerically
        return [ sort { $a <=> $b or $a cmp $b } keys %{ $_[0] } ];
    }
    else {
        #Keys are not all numeric so sort by alphabetically
        return [ sort { lc $a cmp lc $b } keys %{ $_[0] } ];
    }
};

#Additional modules
use Modern::Perl '2014';
use GraphViz;
use Math::Round qw(:all);

exit main(@ARGV);

sub main {

    my $asn_info_ref = retrieve( $Bin . '/bgp_asns.stored' )
        or die
        "Unable to open bgp_asns.stored.  Run bgp_asn_path_via_snmp.pl against an SNMP enabled BGP router";

    #Our GraphViz object
    my $asnGraph = GraphViz->new(
        directed    => 0,
        layout      => 'sfdp',
        overlap     => 'scalexy',
        splines     => 'true',
        colorscheme => 'ylorrd9',
    );
    my %colors = (
        0  => 'gray',
        5  => 'blue',
        10 => 'green',
        15 => 'yellow',
        20 => 'orange',
        25 => 'red',
        60 => 'indigo',
    );

    for my $asn ( sort keys %{$asn_info_ref} ) {

        #Add all hosts in the AS to the AS node label
        my $label = $asn . "\n";

        #         #Make a sorted list of all hosts in this AS
        #         foreach my $hostKey ( @{ $asn_info_ref->{$asn}{'advertises'}} ) {
        #             $label .= $hostKey . "\n";
        #         }

        #In case you're curious
        #         say $label;

        #Create a node for this ASN
        #Make it bigger relative to number of hosts advertised or number of peers

        my $host_count = $asn_info_ref->{$asn}{'host_count'} // 1;
        $host_count = nearest_ceil( 5, log10($host_count)**1.9 );

        my $peer_count = $asn_info_ref->{$asn}{'peer_count'} // 1;

        $peer_count = nearest_ceil( 5, $peer_count / 25 + 10 );

        my $scaling_number
            = $host_count >= $peer_count ? $host_count : $peer_count;

        #             say "scaling: $scaling_number, host: $host_count, peer: $peer_count";

        #           #BUG TODO: Need to do a better job of knowing $scaling_number min/max
        #and mapping that to 1-9
        #Use the ylorrd9 color scheme, (http://graphviz.org/content/color-names#brewer)
        #Map our number into a range 1-9
        my $color = ( ( nearest_ceil( 10, $scaling_number ) ) / 10 ) + 1;
        say $color;

        $asnGraph->add_node(
            $asn,
            label       => "$label",
            shape       => 'ellipse',
            style       => 'filled',
            fontsize    => $scaling_number,
            rank        => $scaling_number,
            color       => "$color",
            colorscheme => 'ylorrd9',
        );

        #Add edges for all neighbor ASNs of this AS
        while ( my ( $neighborAsn, $neighborHashReference )
            = each %{ $asn_info_ref->{$asn}{'connects_to'} } )

        {
            #Debuggery
            #             say "key: $neighborAsn, value:  $neighborHashReference";

            $asnGraph->add_edge( $asn => $neighborAsn );

            #}
        }

    }

    #     #Save the graphiz objects
    #     open my $out_file_txt, '>', "twAsn.dot" or croak $!;
    #     print $out_file_txt $asnGraph->as_text;
    #     close $out_file_txt;

    #PNG output tends to make GraphViz barf
    #     open my $out_file_png, '>', "$0.png"
    #         or croak $!;
    #     print $out_file_png $asnGraph->as_png;
    #     close $out_file_png;

    open my $out_file_svg, '>', "$0.svg"
        or croak $!;
    print $out_file_svg $asnGraph->as_svg;
    close $out_file_svg;

    return 0;
}

sub log10 {
    my $n = shift;
    return log($n) / log(10);
}
