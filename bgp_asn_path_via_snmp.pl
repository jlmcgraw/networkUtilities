#!/usr/bin/perl
# Copyright (C) 2015  Jesse McGraw (jlmcgraw@gmail.com)
#
# Get a list of known networks in BGP and their ASN paths
# output as CSV and a dumped hash
# Copied, and then modified, from SNMP_Session
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

#TODO
#BUGS
#DONE

use strict;
use warnings;
use SNMP_Session;
use BER;
use Socket;
use Getopt::Long;
use FindBin '$Bin';

#Use a local lib directory so users don't need to install modules
use lib "$FindBin::Bin/lib";

use Params::Validate qw(:all);

use Storable;
use Data::Dumper;

#Look into using this so users don't need to install modules
use lib "$FindBin::Bin/lib";

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

sub usage ();

my $snmp_version = '2';

GetOptions( "version=i" => \$snmp_version );

#OID for BGP networks
my $bgp4PathAttrASPathSegment = [ 1, 3, 6, 1, 2, 1, 15, 6, 1, 5 ];

#Pull in command line parameters
my $hostname  = $ARGV[0] || usage();
my $community = $ARGV[1] || "public";

my $session;
my %networks;

die "Couldn't open SNMP session to $hostname"
    unless (
    $session = (
        $snmp_version eq '1'
        ? SNMP_Session->open( $hostname, $community, 161 )
        : SNMPv2c_Session->open( $hostname, $community, 161 )
    )
    );

#Print CSV header
print "dest_net, preflen, peer, asPath, lastAsn\n";

$session->map_table(
    [$bgp4PathAttrASPathSegment],
    sub () {
        my ( $index, $as_path_segment ) = @_;
        my ( $dest_net, $preflen, $peer ) = (
            $index =~ /( [0-9]+ \. [0-9]+ \. [0-9]+ \. [0-9]+)
			  \.
			  ( [0-9]+ )
			  \.
			  ( [0-9]+ \. [0-9]+ \. [0-9]+ \. [0-9]+ )/x
        );

        grep ( defined $_ && ( $_ = pretty_print $_), ($as_path_segment) );

        my ($asPath) = pretty_as_path($as_path_segment);

        my ($lastAsn) = $asPath =~ /\b (\d+)$/x;

        unless ($lastAsn) {

            #There won't be an ASN for routes that this device is advertising,
            #so let's insert something
            $lastAsn = "self";
        }

        #print out what we found for this network
        print "$dest_net, $preflen, $peer, $asPath, $lastAsn\n";

        #and save it in the hash
        $networks{ $dest_net . '/' . $preflen }{'network'}       = $dest_net;
        $networks{ $dest_net . '/' . $preflen }{'prefix_length'} = $preflen;
    }
);
$session->close();

#Save the networks to a hash file (used by ping_hosts_in_acl)
dump_to_file( 'known_networks.dumper', \%networks );

#Save the hash back to disk
store( \%networks, 'known_networks.stored' )
    || die "can't store to 'known_networks.stored'\n";
1;

sub pretty_as_path () {
    my ($aps) = validate_pos( @_, { type => SCALAR }, );

    my $start  = 0;
    my $result = '';

    while ( length($aps) > $start ) {
        my ( $type, $length ) = unpack( "CC", substr( $aps, $start, 2 ) );

        my $pretty_ases;

        $start += 2;
        if ( $length == 0 ) {
            print "------------------------------------------------------\n";

            # next;
        }
        ( $pretty_ases, $start ) = pretty_ases( $length, $aps, $start );

        $result .= ( $type == 1 ? "SET " : $type == 2 ? "" : "type $type??" )
            . $pretty_ases;

    }
    return $result;
}

sub pretty_ases () {
    my ( $length, $aps, $start ) = validate_pos(
        @_,
        { type => SCALAR },
        { type => SCALAR },
        { type => SCALAR },
    );
    my $result = undef;

    #Return immediately if nothing left to process, and bump up iterator
    return ( '', 2 ) if $length == 0;

    while ( $length-- > 0 ) {
        my $as
            = unpack( "S", pack 'S', unpack 'n', substr( $aps, $start, 2 ) );

        $start += 2;
        $result
            = defined $result
            ? $result . " " . $as
            : $as;
    }
    return ( $result, $start );
}

sub usage () {
    die "usage: $0 host [community]";
}

sub dump_to_file {
    my ( $file, $aoh_ref )
        = validate_pos( @_, { type => SCALAR },
        { type => HASHREF | ARRAYREF } );

    open my $fh, '>', $file
        or die "Can't write '$file': $!";

    local $Data::Dumper::Terse = 1;    # no '$VAR1 = '
    local $Data::Dumper::Useqq = 1;    # double quoted strings

    print $fh Dumper $aoh_ref;
    close $fh or die "Can't close '$file': $!";
}
