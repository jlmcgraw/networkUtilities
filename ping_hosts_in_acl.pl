#!/usr/bin/perl
# Copyright (C) 2015  Jesse McGraw (jlmcgraw@gmail.com)
#
# Ping hosts (and smaller subnets) mentioned in ACL to see what's still viable
#
# Snip out your ACL from your config and save it to a text file, supply this
# text file as a parameter to this utility
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
# Provide color-coded HTML output
# Process all hosts in subnets.  Should probably limit the size of subnets procesed
# Quit processing a subnet on the first active response since that indicates
#   the subnet is still valid
# IPv6
# Groups
# More config formats
#
#BUGS

#DONE

#Standard modules
use strict;
use warnings;
use autodie;
use Socket;
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

use Storable;

# use File::Basename;
use threads;
use Thread::Queue;

# Use Share
use threads::shared;

# use Benchmark qw(:hireswallclock);
use Getopt::Std;
use FindBin '$Bin';
use vars qw/ %opt /;
use Net::Ping;

#Use a local lib directory so users don't need to install modules
use lib "$FindBin::Bin/lib";

#Additional modules
use Modern::Perl '2014';
use Regexp::Common;
use Params::Validate qw(:all);
use NetAddr::IP;

#Smart_Comments=0 perl my_script.pl
# to run without smart comments, and
#Smart_Comments=1 perl my_script.pl
use Smart::Comments;

#Use this to not print warnings
no if $] >= 5.018, warnings => "experimental";

#Define the valid command line options
my $opt_string = '';
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

my $known_networks_filename = 'known_networks.dumper';

my %known_networks;

#Load a hash of our known networks, if it exists
if ( -e $Bin . "/$known_networks_filename" ) {

    #This is a Data::Dumper output from "bgp_asn_path_via_snmp.pl"
    #with the default route manually removed
    say "Loading $known_networks_filename ...";
    %known_networks = do $Bin . "/$known_networks_filename";
}

# print Dumper \%known_networks;

#Call main routine
exit main(@ARGV);

sub main {

    #Loop through every file provided on command line
    foreach my $filename (@ARGV) {

        #Note which file we're working on
        say $filename;

        #Open the input and output files
        open my $filehandle, '<', $filename or die $!;

        # open my $filehandleTested, '>', $filename . '.tested' or die $!;

        #Read in the whole file
        my @array_of_lines = <$filehandle>
            or die $!;    # Reads all lines into array

        #A hash to collect data in, shared for multi-threading
        my %found_networks_and_hosts : shared;

        # Make sure the two base keys are shared for multi-threading
        $found_networks_and_hosts{'hosts'}    = &share( {} );
        $found_networks_and_hosts{'networks'} = &share( {} );

        #Process each line of the file separately
        foreach my $line (@array_of_lines) {

            chomp $line;

            #Remove linefeeds
            $line =~ s/\R//gx;

            #Pull target hosts and networks from this line
            #and populate the shared hash with that info (while sharing each new key)
            gather_hosts_from_this_line( $line, \%found_networks_and_hosts );
            gather_networks_from_this_line( $line,
                \%found_networks_and_hosts );

            # say $line;
        }

        #Make one long string out of the array
        my $scalar_of_lines = join "\n", @array_of_lines;

        # For future HTML output
        # say {$filehandleTested} $line;

        #Gather info about each found host and put back into ACL
        parallel_process_hosts( \%found_networks_and_hosts,
            \$scalar_of_lines );

        #Gather info about each found network and put back into ACL
        parallel_process_networks( \%found_networks_and_hosts,
            \$scalar_of_lines );

        #Print out the annotated ACL
        say $scalar_of_lines;

    }
    return 0;
}

sub parallel_process_hosts {
    my ( $found_networks_and_hosts_ref, $scalar_of_lines_ref )
        = validate_pos( @_, { type => HASHREF }, { type => SCALARREF }, );

    #Now prepare to get DNS names and responsiveness for each host/network
    #in a parallel fashion so it doesn't take forever

    # A new empty queue
    my $q = Thread::Queue->new();

    # Queue up all of the hosts for the threads
    $q->enqueue($_) for keys $found_networks_and_hosts_ref->{'hosts'};

    #Nothing else to queue
    $q->end();

    #How many hosts we queued
    say $q->pending() . " hosts queued";

    # Maximum number of worker threads
    # BUG TODO Adjust this dynamically based on number of CPUs
    my $thread_limit = 70;

    #Create $thread_limit worker threads calling "process_hosts_thread"
    my @thr = map {
        threads->create(
            sub {
                while ( defined( my $host_ip = $q->dequeue_nb() ) ) {
                    process_hosts_thread( $host_ip,
                        $found_networks_and_hosts_ref, );
                }
            }
        );
    } 1 .. $thread_limit;

    # Wait for all of the threads in @thr to terminate
    $_->join() for @thr;

    #Smart comment for debug
    ## %found_networks_and_hosts;

    #Substitute info we found back into the lines of the ACL
    foreach my $host_key ( keys $found_networks_and_hosts_ref->{'hosts'} ) {

        #Get the info we found for this host
        my $host_name
            = $found_networks_and_hosts_ref->{'hosts'}{$host_key}{'dns_name'};
        my $host_status
            = $found_networks_and_hosts_ref->{'hosts'}{$host_key}{'status'};

        #If there's no DNS entry for this host don't include IP in substitution
        if ( $host_name eq $host_key ) {

            #Substitute it back into the ACL
            ${$scalar_of_lines_ref}
                =~ s/host $host_key/host $host_key [$host_status]/g;
        }
        else {
            #Substitute it back into the ACL
            ${$scalar_of_lines_ref}
                =~ s/host $host_key/host $host_key [$host_name: $host_status]/g;
        }

    }
}

sub parallel_process_networks {
    my ( $found_networks_and_hosts_ref, $scalar_of_lines_ref )
        = validate_pos( @_, { type => HASHREF }, { type => SCALARREF }, );

    #Now prepare to process info network
    #in a parallel fashion so it doesn't take forever

    # A new empty queue
    my $q = Thread::Queue->new();

    # Queue up all of the networks for the threads
    $q->enqueue($_) for keys $found_networks_and_hosts_ref->{'networks'};

    #No more data to queue
    $q->end();

    #How many networks did we queue
    say $q->pending() . " networks queued";

    # Maximum number of worker threads
    # BUG TODO Adjust this dynamically based on number of CPUs
    my $thread_limit = 70;

    #Create $thread_limit worker threads calling "process_networks_thread"
    my @thr = map {
        threads->create(
            sub {
                while ( defined( my $network_and_mask = $q->dequeue_nb() ) ) {
                    process_networks_thread( $network_and_mask,
                        $found_networks_and_hosts_ref, );
                }
            }
        );
    } 1 .. $thread_limit;

    # Wait for all of the threads in @thr to terminate
    $_->join() for @thr;

    #Smart comment for debugging
    # ## %found_networks_and_hosts;

    #Substitute info we found back into the lines of the ACL
    foreach
        my $network_key ( keys $found_networks_and_hosts_ref->{'networks'} )
    {

        #Get the info we found for this host
        my $number_of_hosts
            = $found_networks_and_hosts_ref->{'networks'}{$network_key}
            {'number_of_hosts'};

        my $status
            = $found_networks_and_hosts_ref->{'networks'}{$network_key}
            {'status'};

        #Substitute it back into the ACL
        ${$scalar_of_lines_ref}
            =~ s/$network_key/$network_key [ $number_of_hosts hosts $status]/g;
    }

}

sub gather_hosts_from_this_line {
    my ( $line, $found_networks_and_hosts_ref )
        = validate_pos( @_, { type => SCALAR }, { type => HASHREF }, );

    #Find all "host x.x.x.x" entries
    while (
        $line =~ /
                        host \s+ 
                        (?<host> $RE{net}{IPv4})
                        /ixsmg
        )
    {
        my $host_ip = $+{host};

        #Save the hosts we find on this line

        #Make sure this new key is shared
        if ( !exists $found_networks_and_hosts_ref->{hosts}{$host_ip} ) {

            #Share the key, which deletes existing data
            $found_networks_and_hosts_ref->{hosts}{$host_ip} = &share( {} );

            #Set the initial data for this host
            $found_networks_and_hosts_ref->{'hosts'}{$host_ip}{'dns_name'}
                = 'unknown';
            $found_networks_and_hosts_ref->{'hosts'}{$host_ip}{'status'}
                = 'unknown';

        }
        else {
            say
                "$host_ip already exists!-------------------------------------------------------------------";
        }

    }
}

sub gather_networks_from_this_line {
    my ( $line, $found_networks_and_hosts_ref )
        = validate_pos( @_, { type => SCALAR }, { type => HASHREF }, );

    #Find all "x.x.x.x y.y.y.y" entries (eg host and wildcard_mask)
    while (
        $line =~ /
                        (?<network> $RE{net}{IPv4}) \s+
                        (?<wildcard_mask> $RE{net}{IPv4}) 
                        (\s* | $)
                        /ixsmg
        )
    {
        my $address       = $+{network};
        my $wildcard_mask = $+{wildcard_mask};

        #Get a list of all addresses that match this host/wildcard_mask combination
        my $possible_matches_ref
            = list_of_matches_acl( $address, $wildcard_mask );

        #Save that array reference to another array
        my @one = @{$possible_matches_ref};

        #Get a count of how many elements in that array
        my $number_of_hosts = @{$possible_matches_ref};

        #Make sure this new key is shared
        if ( !exists $found_networks_and_hosts_ref->{'networks'}
            { $address . ' ' . $wildcard_mask } )
        {
            #Share the key, which deletes existing data
            $found_networks_and_hosts_ref->{'networks'}
                { $address . ' ' . $wildcard_mask } = &share( {} );

            #How many hosts in the possible matches list
            $found_networks_and_hosts_ref->{'networks'}
                { $address . ' ' . $wildcard_mask }{'number_of_hosts'}
                = "$number_of_hosts";

            #Default having no specific route for this network
            $found_networks_and_hosts_ref->{'networks'}
                { $address . ' ' . $wildcard_mask }{'status'}
                = "NO SPECIFIC ROUTE";

            #All possible matches to the mask
            $found_networks_and_hosts_ref->{'networks'}
                { $address . ' ' . $wildcard_mask }{'list_of_hosts'} = "@one";
        }
        else {
            say
                "$address $wildcard_mask already exists!-------------------------------------------------------------------";
        }
    }
}

sub process_hosts_thread {
    my ( $host_ip, $found_networks_and_hosts_ref )
        = validate_pos( @_, { type => SCALAR }, { type => HASHREF }, );

    # Get the thread id. Allows each thread to be identified.
    my $id = threads->tid();

    # say "Thread $id: $host_ip";

    #Do a DNS lookup for the host
    my $name = pretty_addr($host_ip);

    # say "Thread $id: $host_ip -> $name";

    # lock($found_networks_and_hosts_ref)->{'hosts'};
    $found_networks_and_hosts_ref->{'hosts'}{$host_ip}{'dns_name'} = "$name";

    # unlock($found_networks_and_hosts_ref)->{'hosts'};

    my $timeout = 3;

    #This needs to be 'tcp' or 'udp' on unix systems (or run as root)
    my $p = Net::Ping->new( 'icmp', $timeout )
        or die "Thread $id: Unable to create Net::Ping object ";

    #Default status is not responding
    my $status = 'NOT RESPONDING';

    if ( $p->ping($host_ip) ) {

        #If the host responded, change its status
        $status = 'UP';
    }

    # say "Thread $id: $host_ip -> $status";
    #Update the hash for this host
    $found_networks_and_hosts_ref->{'hosts'}{$host_ip}{'status'} = "$status";
    $p->close;

}

sub process_networks_thread {
    my ( $network_and_mask, $found_networks_and_hosts_ref )
        = validate_pos( @_, { type => SCALAR }, { type => HASHREF }, );

    #Test if a route for this network even exists in %known_networks hash

    # Get the thread id. Allows each thread to be identified.
    my $id = threads->tid();

    # say "Thread $id: $network_and_mask";

    #Split into components
    my ( $network, $network_mask ) = split( ' ', $network_and_mask );

    #This little bit of magic inverts the wildcard mask to a netmask.  Copied from somewhere on the net
    my $mask_wild_dotted = $network_mask;
    my $mask_wild_packed = pack 'C4', split /\./, $mask_wild_dotted;

    my $mask_norm_packed = ~$mask_wild_packed;
    my $mask_norm_dotted = join '.', unpack 'C4', $mask_norm_packed;

    #Create a new subnet from captured info
    my $acl_subnet = NetAddr::IP->new("$network/$mask_norm_dotted");

    #If we could create the subnet...
    if ($acl_subnet) {

        # say "acl_subnet: $network / $mask_norm_dotted";
        # $ip_addr = $acl_subnet->addr;
        # $network_mask = $acl_subnet->mask;
        # $network_masklen = $subnet->masklen;
        # $ip_addr_bigint  = $subnet->bigint();
        # $isRfc1918         = $acl_subnet->is_rfc1918();
        # $range           = $subnet->range();

        #Test it against all known networks...
        foreach my $known_network ( keys %known_networks ) {

            #Create a subnet for the known network
            my $known_subnet = NetAddr::IP->new($known_network);

            #If that worked...
            #(which it won't with some wildcard masks)
            if ($known_subnet) {

                #Is the ACL subnet within the known network?
                if ( $acl_subnet->within($known_subnet) ) {

                    #Update the status of this network
                    $found_networks_and_hosts_ref->{'networks'}
                        {$network_and_mask}{'status'} = '';
                }
            }
            else {
                say
                    "Network w/ wildcard mask: Couldn't create subnet for $known_network";
            }
        }
    }
    else {

        say
            "Network w/ wildcard mask: Couldn't create subnet for $network $network_mask";
    }

    #Test how many of this network's hosts respond
    #......
}

sub usage {
    say "";
    say " Usage : ";
    say " $0 <ACL_file1 > <ACL_file 2> <*.acl> etc ";
    say "";
    exit 1;
}

sub pretty_addr {
    my ($addr) = validate_pos( @_, { type => SCALAR }, );

    my ( $hostname, $aliases, $addrtype, $length, @addrs )
        = gethostbyaddr( inet_aton($addr), AF_INET );

    #Return $hostname if defined, else $addr
    return ( $hostname // $addr );
}

sub hostname {
    my ($addr) = validate_pos( @_, { type => SCALAR }, );

    my ( $hostname, $aliases, $addrtype, $length, @addrs )
        = gethostbyaddr( inet_aton($addr), AF_INET );
    return $hostname || "[" . $addr . "]";
}

sub list_of_matches_acl {

    #Generate a list of all hosts that would match this network/wildcard_mask pair
    #
    #This routine is completely unoptimized at this point

    #Pass in the variables of ACL network and wildcard mask
    #eg 10.200.128.0 0.0.0.255

    my ( $acl_address, $acl_mask )
        = validate_pos( @_, { type => SCALAR }, { type => SCALAR }, );

    #The array of possible matches
    my @potential_matches;

    #Split the incoming parameters into 4 octets
    my @acl_address_octets = split /\./, $acl_address;
    my @acl_mask_octets    = split /\./, $acl_mask;

    #Test the 1st octet
    my $matches_octet_1_ref
        = test_octet( $acl_address_octets[0], $acl_mask_octets[0] );

    #Copy the referenced array into a new one
    my @one = @{$matches_octet_1_ref};

    #Test the 2nd octet
    my $matches_octet_2_ref
        = test_octet( $acl_address_octets[1], $acl_mask_octets[1] );

    #Copy the referenced array into a new one
    my @two = @{$matches_octet_2_ref};

    #Test the 3rd octet
    my $matches_octet_3_ref
        = test_octet( $acl_address_octets[2], $acl_mask_octets[2] );

    #Copy the referenced array into a new one
    my @three = @{$matches_octet_3_ref};

    #Test the 4th octet
    my $matches_octet_4_ref
        = test_octet( $acl_address_octets[3], $acl_mask_octets[3] );

    #Copy the referenced array into a new one
    my @four = @{$matches_octet_4_ref};

    #Assemble the list of possible matches
    #Iterating over all options for each octet
    foreach my $octet1 (@one) {
        foreach my $octet2 (@two) {
            foreach my $octet3 (@three) {
                foreach my $octet4 (@four) {

                    #Save this potential match to the array of matches
                    #say "$octet1.$octet2.$octet3.$octet4"
                    push( @potential_matches,
                        "$octet1.$octet2.$octet3.$octet4" );
                }
            }
        }
    }
    return \@potential_matches;
}

sub test_octet {

    #Test all possible numbers in an octet (0..255) against octet of ACL and mask

    my ( $acl_octet, $acl_wildcard_octet )
        = validate_pos( @_, { type => SCALAR }, { type => SCALAR }, );

    my @matches;

    #Short circuit here for a mask value of 0 since it matches only the $acl_octet
    if ( $acl_wildcard_octet eq 0 ) {
        push @matches, $acl_octet;
    }
    else {
        for my $test_octet ( 0 .. 255 ) {
            if (wildcard_mask_test(
                    $test_octet, $acl_octet, $acl_wildcard_octet
                )
                )
            {
                #If this value is a match, save it
                push @matches, $test_octet;
            }

        }
    }

    #Return array of which values from 0..255 match
    return \@matches;
}

sub wildcard_mask_test {

    #Test one number against acl address and mask

    my ( $test_octet, $acl_octet, $acl_wildcard_octet ) = validate_pos(
        @_,
        { type => SCALAR },
        { type => SCALAR },
        { type => SCALAR },
    );

    #Bitwise OR of test_octet and acl_octet against the octet of the wildcard mask
    my $test_result = $test_octet | $acl_wildcard_octet;
    my $acl_result  = $acl_octet | $acl_wildcard_octet;

    #Return value is whether they match
    return ( $acl_result eq $test_result );
}

sub dump_to_file {
    my ( $file, $aoh_ref ) = @_;

    open my $fh, '>', $file
        or die "Can't write '$file': $!";

    local $Data::Dumper::Terse = 1;    # no '$VAR1 = '
    local $Data::Dumper::Useqq = 1;    # double quoted strings

    print $fh Dumper $aoh_ref;
    close $fh or die "Can't close '$file': $!";
}
