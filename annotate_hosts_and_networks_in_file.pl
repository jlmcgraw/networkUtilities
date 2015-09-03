#!/usr/bin/perl
# Copyright (C) 2015  Jesse McGraw (jlmcgraw@gmail.com)
#
# Ping hosts mentioned in config to see what's still viable, annotate with DNS name and status
# Enumerate count of hosts in subnets, normalize wildcard and CIDR entries to subnet form
# ( eg 10.0.0.1/255.255.255.0) to prevent confusion (but note this makes shown config invalid)
#
# Point this utility to your router/switch/firewall config, or snip out an ACl of interest
# to a separate text file
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
# Normalize how subnets are shown in config
# Process all hosts in subnets.
#   Should probably limit the size of subnets processed
#   Quit processing a subnet on the first active response since that indicates
#       the subnet is still valid
# IPv6
# Groups
# More config formats
#
#BUGS
#   (FIXED) Freaks out on normal host/subnet masks
#DONE
#   Provide color-coded HTML output
#   Option for type of ping test
#   Option for number of threads

#Standard modules
use strict;
use warnings;
use autodie;
use Socket;
use Config;
use Data::Dumper;
use Storable;
use threads;
use Thread::Queue;
use threads::shared;
use Getopt::Std;
use FindBin '$Bin';
use vars qw/ %opt /;

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

#Use a local lib directory so users don't need to install modules
use lib "$FindBin::Bin/local/lib/perl5";

#Additional modules
use Modern::Perl '2014';
use Params::Validate qw(:all);
use NetAddr::IP;
use Net::Ping;
use Hash::Merge qw(merge);

#Smart_Comments=1 perl my_script.pl to show smart comments
use Smart::Comments -ENV;

#Use this to not print warnings
#no if $] >= 5.018, warnings => "experimental";

#Define the valid command line options
my $opt_string = 'dp:t:';
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

#Default method of testing remote connectivity
my $ping_method = 'tcp';

#Set ping method depending on OS
#Expand wildcards on command line since windows doesn't do it for us
if ( $Config{archname} =~ m/win/ix ) {

    #Expand wildcards on command line
    say "Expanding wildcards for Windows";
    @ARGV = map {glob} @ARGV;

    #     print "$Config{osname}\n";
    #     print "$Config{archname}\n";

    #You can ping without root on windows
    $ping_method = 'icmp';
}

#What method does the user want to ping via?
if ( $opt{p} ) {

    #If something  provided on the command line use it instead
    if ( $opt{p} =~ /icmp|udp|tcp|external/ix ) {
        $ping_method = $opt{p};
        say "Supplied ping method: $ping_method";
    }
    else { say "Supplied invalid ping method"; }
}
say "Testing connectivity by method: $ping_method";

#The maximum number of simultaneous threads
my $max_threads = 32;

#Does the user want to use more or less threads?
if ( $opt{t} ) {
    $max_threads = $opt{t};
    say "Using $max_threads threads";
}

#Does the user want to show duplicates?
my $should_show_duplicates = $opt{d};

#Where known networks are stored (created by bgp_asn_path_via_snmp.pl)
my $known_networks_filename = "$FindBin::Bin/known_networks.stored";

#a hash reference for those networks
my $known_networks_ref;

#A number from 0 - 255
my $ipOctetRegex = qr/(?: 25[0-5] | 2[0-4]\d | [01]?\d\d? )/x;

#an IP address is 4 octets separated by .
my $ipv4AddressRegex = qr/$ipOctetRegex\.
                          $ipOctetRegex\.
			  $ipOctetRegex\.
			  $ipOctetRegex/mx;

#Load a hash of our known networks, if it exists
if ( -e "/$known_networks_filename" ) {
    say "Loading $known_networks_filename ...";

    #Read in hash from 'storable' format
    $known_networks_ref = retrieve($known_networks_filename);
}

##Smart_comment known_networks_ref: $known_networks_ref

#Call main routine
exit main(@ARGV);

sub main {

    #A hash to collect data in, shared for multi-threading
    #Accumulated for every file so we don't work on a given host or network more than once
    my %found_networks_and_hosts : shared;

    # Make sure the two base keys are shared for multi-threading
    $found_networks_and_hosts{'hosts'}    = &share( {} );
    $found_networks_and_hosts{'networks'} = &share( {} );

    # A new empty queue
    my $q = Thread::Queue->new();

    # Queue up all of the files for the threads
    $q->enqueue($_) for @ARGV;
    $q->end();
    say $q->pending() . " files queued";

    # Maximum number of worker threads
    # BUG TODO Adjust this dynamically based on number of CPUs
    my $thread_limit = 4;

    #Create $thread_limit worker threads calling "annotate_file"
    my @thr = map {
        threads->create(
            sub {
                while ( defined( my $filename = $q->dequeue_nb() ) ) {
                    annotate_file( $filename, \%found_networks_and_hosts, );
                }
            }
        );
    } 1 .. $thread_limit;

    # terminate all of the threads in @thr
    $_->join() for @thr;

    return 0;
}

sub annotate_file {

    # One of these threads for every file
    # #Loop through every file provided on command line
    # foreach my $filename (@ARGV)
    my ( $filename, $found_networks_and_hosts_ref )
        = validate_pos( @_, { type => SCALAR }, { type => HASHREF }, );

    # Get the thread id. Allows each thread to be identified.
    my $id = threads->tid();

    say "Thread $id: $filename";

    #Note which file we're working on
    # say $filename;

    #Open the input file
    open my $filehandle, '<', $filename or die $!;

    #Read in the whole file
    my @array_of_lines = <$filehandle>
        or die $!;    # Reads all lines into array

    #Remove newlines from whole array
    chomp(@array_of_lines);

    #Process each line of the file separately
    foreach my $line (@array_of_lines) {

        #Remove linefeeds
        $line =~ s/\R//g;

        #Find hosts and networks in this line
        my ( $hosts_in_line_ref, $nets_in_line_ref )
            = find_hosts_and_nets_in_line($line);

        #Populate the shared hash with that info (while sharing each new key)
        add_found_hosts_to_shared_hash( $hosts_in_line_ref,
            $found_networks_and_hosts_ref );

        #Populate the shared hash with that info (while sharing each new key)
        add_found_networks_to_shared_hash( $nets_in_line_ref,
            $found_networks_and_hosts_ref );

    }

    ##Smart_Comments found_networks_and_hosts: %found_networks_and_hosts
    #         print Dumper \%found_networks_and_hosts;

    #Make one long string out of the array
    #This is probably unecessary but I haven't bothered to change code yet
    my $scalar_of_lines = join "\n", @array_of_lines;

    #Do we want to see things that were mentioned multiple times?
    show_duplicates($found_networks_and_hosts_ref)
        if $should_show_duplicates;

    #Gather info about each found host and annotate original text with that info
    parallel_process_hosts( $found_networks_and_hosts_ref,
        \$scalar_of_lines );

    #Gather info about each found network and annotate original text with that info
    parallel_process_networks( $found_networks_and_hosts_ref,
        \$scalar_of_lines );

    #Print out the annotated ACL
    # say $scalar_of_lines;

    #Very basic HTML output
    open my $filehandleHtml, '>', $filename . '-annotated.html' or die $!;

    #Print a simple html beginning to output
    print $filehandleHtml <<"END";
<!DOCTYPE html>
<html>
    <head>
        <meta charset="UTF-8">
        <title>
        $filename
        </title>
    </head>
    <body>
        <pre>
END

    #The html-ized output
    say {$filehandleHtml} $scalar_of_lines;

    #Close out the file with very basic html ending
    print $filehandleHtml <<"END";
        </pre>
    </body>
</html>
END
    close $filehandleHtml;

}

sub find_hosts_and_nets_in_line {

    #Find hosts and networks in this line
    #net_matches array elements are normalized to n.n.n.n/m.m.m.m

    my ( $line, )
        = validate_pos( @_, { type => SCALAR }, );

    #Save unmodified version of the line
    my $original_line = $line;

    ##Smart comment line: $line
    #     #For debugging
    #     if ( $line =~ /$ipv4AddressRegex/ ) {
    #
    #         #Remove leading space
    #         $line =~ s/^\s+//g;
    #         say $line;
    #     }

    my ( @host_matches, @net_mask_matches, @net_cidr_matches, @net_matches );

    my ( %hosts, %nets_mask, %nets_cidr );

    #BUG Make it work with something like "permit ip host 192.1681.100 10.0.0.0 0.255.255.255"

    #Match what looks like IP and subnet/wildcard mask
    (@net_mask_matches) = (
        $line =~ / 
                \s+ 
                ( $ipv4AddressRegex \s+ 
                (?: mask \s+)? 
		$ipv4AddressRegex)
                /ixmsg
    );

    #Make a hash from all results
    my %temp_nets_mask = map { $_ => 1 } @net_mask_matches;

    #Match what looks like IP followed CIDR mask length
    (@net_cidr_matches) = (
        $line =~ /
                    \s+ 
                    ( $ipv4AddressRegex \s* \/ \d+)
                    /ixmsg
    );

    #Make a hash from all results
    my %temp_nets_cidr = map { $_ => 1 } @net_cidr_matches;

    #Remove all found networks from the line
    #This helps avoid false matches for host regex below
    foreach my $net_to_remove ( @net_mask_matches, @net_cidr_matches ) {
        $line =~ s/$net_to_remove//g;
    }

    #Now normalize what networks we found
    #Convert all of @net_mask_matches "n.n.n.n m.m.m.m" -> "n.n.n.n/m.m.m.m"
    for my $key ( keys %temp_nets_mask ) {

        #Key is exactly what we found in text, clean it up
        my $normalized_key = $key;

        #Remove "mask"
        $normalized_key =~ s/ mask //ix;

        #Replace spaces with /
        $normalized_key =~ s/ \s+ /\//ix;

        #Store the normalized text
        $nets_mask{$key}{'normalized'} = $normalized_key;
    }

    # #Convert all of net_cidr_matches  "n.n.n.n /mm" -> "n.n.n.n/m.m.m.m"
    for my $key ( keys %temp_nets_cidr ) {

        #Key is unnormalized text we found in config, clean it up
        #Remove whitespace
        $key =~ s/\s+//igx;

        #Split out components
        my ( $net, $cidr ) = split( /[\/]/, $key );

        #Convert the CIDR length to a bigint
        my $mask = ( 2**$cidr - 1 ) << ( 32 - $cidr );

        #Convert the bigint to dotted format
        $mask = join( ".", unpack( "C4", pack( "N", $mask ) ) );
        $nets_cidr{$key}{'normalized'} = "$net/$mask";
    }

    #And now try to match hosts (after n.n.n.n m.m.m.m and "mask" are removed from $line)
    (@host_matches) = (
        $line =~ /
                [^ \. \- a]                            #NOT proceeded by . or - (eg part of snmp mib)
                                                       # HACK: or trailing "a" from "ospf area"
                \s+
                ( $ipv4AddressRegex ) (?: \s* | $)     #just an IP address by itself (a host)
                (?! \. | $ipv4AddressRegex | mask)     #NOT followed by what looks like a mask
                /ixmsg
    );

    #Populate hosts hash from array of matches
    %hosts = map { $_ => 1 } @host_matches;

    #Merge the network hashes
    my $merged_networks_hash_ref = merge( \%nets_mask, \%nets_cidr );

    #Return two hash references
    return ( \%hosts, $merged_networks_hash_ref );
}

sub add_found_hosts_to_shared_hash {

    #Put the hosts we found into a hash
    my ( $hosts_in_line_ref, $found_networks_and_hosts_ref )
        = validate_pos( @_, { type => HASHREF }, { type => HASHREF }, );

    foreach my $host_ip ( keys %{$hosts_in_line_ref} ) {

        #Make sure this new key is shared
        if ( !exists $found_networks_and_hosts_ref->{'hosts'}{$host_ip} ) {

            #Share the key, which deletes existing data
            $found_networks_and_hosts_ref->{'hosts'}{$host_ip}
                = &share( {} );

            #Set the initial data for this host
            $found_networks_and_hosts_ref->{'hosts'}{$host_ip}{'dns_name'}
                = 'unknown';
            $found_networks_and_hosts_ref->{'hosts'}{$host_ip}{'status'}
                = 'untested';
            $found_networks_and_hosts_ref->{'hosts'}{$host_ip}{'count'} = 1;

        }
        else {
            #Increment the count of times we've seen this object
            $found_networks_and_hosts_ref->{'hosts'}{$host_ip}{'count'}++;
        }

    }
}

sub add_found_networks_to_shared_hash {

    #Put the subnets we found into a hash
    my ( $nets_in_line_ref, $found_networks_and_hosts_ref )
        = validate_pos( @_, { type => HASHREF }, { type => HASHREF }, );

    foreach my $network_and_mask_as_found ( keys %{$nets_in_line_ref} ) {

        #Split normalized network ("n.n.n.n/m.m.m.m") into address and mask
        my $network_and_mask_normalized
            = $nets_in_line_ref->{$network_and_mask_as_found}{'normalized'};

        my ( $address, $mask )
            = split( '/',
            $nets_in_line_ref->{$network_and_mask_as_found}{'normalized'} );

        my ( $all_possible_matches_ref, $ranged_possible_matches_ref, @one,
            $number_of_hosts, $range );

        #Does this look like a subnet mask?
        if ( is_subnet_mask($mask) ) {

            #Try to make a NetAddr object from it
            my $acl_subnet = NetAddr::IP->new("$address/$mask");

            #If we could create the subnet...
            if ($acl_subnet) {

                #This is the number of hosts in that subnet
                $number_of_hosts = $acl_subnet->num();
                $range           = $acl_subnet->range();
                push( @one, $range );

                #These are other bits of information about this subnet we may
                # want to save at some point
                # say "acl_subnet: $network / $mask_norm_dotted";
                # $ip_addr = $acl_subnet->addr;
                # $network_mask = $acl_subnet->mask;
                # $network_masklen = $subnet->masklen;
                # $ip_addr_bigint  = $subnet->bigint();
                # $isRfc1918         = $acl_subnet->is_rfc1918();

            }
            else {
                $number_of_hosts = "0";
                say "Couldn't create $address/$mask";
            }

        }
        else {
            #We're guessing this is a wildcard mask
            #Get a list of all addresses that match this host/wildcard_mask combination
            ( $all_possible_matches_ref, $ranged_possible_matches_ref )
                = list_of_matches_wildcard( $address, $mask );

            #Save that array reference to another array
            #We'll use ranges for now
            #@one = @{$all_possible_matches_ref};
            @one = @{$ranged_possible_matches_ref};

            #Get a count of how many elements in that array
            $number_of_hosts = @{$all_possible_matches_ref};
        }

        #Make sure this new key is shared
        if ( !exists $found_networks_and_hosts_ref->{'networks'}
            {$network_and_mask_as_found} )
        {
            #Share the key, which deletes existing data
            $found_networks_and_hosts_ref->{'networks'}
                {$network_and_mask_as_found} = &share( {} );

            #How many hosts in the possible matches list
            $found_networks_and_hosts_ref->{'networks'}
                {$network_and_mask_as_found}{'address'} = "$address";

            #How many hosts in the possible matches list
            $found_networks_and_hosts_ref->{'networks'}
                {$network_and_mask_as_found}{'mask'} = "$mask";

            #How many hosts in the possible matches list
            $found_networks_and_hosts_ref->{'networks'}
                {$network_and_mask_as_found}{'number_of_hosts'}
                = "$number_of_hosts";

            #Default having no specific route for this network
            $found_networks_and_hosts_ref->{'networks'}
                {$network_and_mask_as_found}{'status'} = "via DEFAULT";

            #What did this network look like in the source text
            $found_networks_and_hosts_ref->{'networks'}
                {$network_and_mask_as_found}{'as_found'}
                = "$network_and_mask_as_found";

            #What did this network look like in the source text
            $found_networks_and_hosts_ref->{'networks'}
                {$network_and_mask_as_found}{'normalized'}
                = "$network_and_mask_normalized";

            $found_networks_and_hosts_ref->{'networks'}
                {$network_and_mask_as_found}{'count'} = 1;

            #Matches to the mask (as a range or individual hosts)
            $found_networks_and_hosts_ref->{'networks'}
                {$network_and_mask_as_found}{'list_of_hosts'} = "@one";
        }
        else {
            #Increment the count of times we've seen this object
            $found_networks_and_hosts_ref->{'networks'}
                {$network_and_mask_as_found}{'count'}++;
        }

    }
}

sub parallel_process_hosts {

    #Ping and DNS lookup all found hosts in parallel fashion
    #Then add this info back into source config text

    my ( $found_networks_and_hosts_ref, $scalar_of_lines_ref )
        = validate_pos( @_, { type => HASHREF }, { type => SCALARREF }, );

    #Now prepare to get DNS names and responsiveness for each host/network
    #in a parallel fashion so it doesn't take forever

    # A new empty queue
    my $q = Thread::Queue->new();

    # Queue up all of the hosts for the threads
    # Make an array of existing keys to avoid warnings about hash iterator
    my @host_keys = keys %{ $found_networks_and_hosts_ref->{'hosts'} };
    for my $host_ip (@host_keys) {

        # foreach  my $host_ip ( keys %{ $found_networks_and_hosts_ref->{'hosts'} } ){
        #Don't work on this host again if we already have
        next
            unless $found_networks_and_hosts_ref->{'hosts'}{$host_ip}
            {'status'} eq 'untested';
        $q->enqueue($host_ip);
    }

    #Nothing else to queue
    $q->end();

    #How many hosts we queued
    say $q->pending() . " hosts queued" if $q->pending();

    #Create $max_threads worker threads calling "process_hosts_thread"
    my @thr = map {
        threads->create(
            sub {
                while ( defined( my $host_ip = $q->dequeue_nb() ) ) {
                    process_hosts_thread( $host_ip,
                        $found_networks_and_hosts_ref, );
                }
            }
        );
    } 1 .. $max_threads;

    # Wait for all of the threads in @thr to terminate
    $_->join() for @thr;

    #Smart comment for debug
    ## found_networks_and_hosts: %found_networks_and_hosts;

    #Substitute info we found back into the lines of the config
    #Use the previously created array of keys

    for my $host_key (@host_keys) {

        # foreach  my $host_key ( keys %{ $found_networks_and_hosts_ref->{'hosts'} } )    {

        #Get the info we found for this host
        my $host_name
            = $found_networks_and_hosts_ref->{'hosts'}{$host_key}{'dns_name'};
        my $host_status
            = $found_networks_and_hosts_ref->{'hosts'}{$host_key}{'status'};

        #What color to use depends on status of host
        my $text_color = $host_status eq 'UP' ? 'lime' : 'red';

        #What to add
        #If there's no DNS entry for this host don't add anything
        my $text_to_insert = $host_name eq $host_key ? '' : " [$host_name]";

        #Substitute it back into the config
        ${$scalar_of_lines_ref}
            =~ s/([^\d] \s+ )$host_key (\s* [^\dm])/$1<font color = "blue"><font color = "$text_color">$host_key<\/font>$text_to_insert<\/font>$2/ixg;
    }
}

sub parallel_process_networks {

    #Now prepare to process info network
    #in a parallel fashion so it doesn't take forever
    #Add found information back into original configuration text
    my ( $found_networks_and_hosts_ref, $scalar_of_lines_ref )
        = validate_pos( @_, { type => HASHREF }, { type => SCALARREF }, );

    # A new empty queue
    my $q = Thread::Queue->new();

    # # Queue up all of the networks for the threads
    # $q->enqueue($_) for keys %{ $found_networks_and_hosts_ref->{'networks'} };

    # Queue up all of the networks for the threads
    # Make an array of existing keys to avoid warnings about hash iterator
    my @network_keys = keys %{ $found_networks_and_hosts_ref->{'networks'} };
    for my $network_key (@network_keys) {

        # foreach  my $network_key ( keys %{ $found_networks_and_hosts_ref->{'networks'} } ){
        #Don't work on this network again if we already have
        next
            if
            exists $found_networks_and_hosts_ref->{'networks'}{$network_key}
            {'tested'};
        $q->enqueue($network_key);
    }

    #No more data to queue
    $q->end();

    #How many networks did we queue
    say $q->pending() . " networks queued" if $q->pending();

    #Create $max_threads worker threads calling "process_networks_thread"
    my @thr = map {
        threads->create(
            sub {
                while ( defined( my $network_and_mask = $q->dequeue_nb() ) ) {
                    process_networks_thread( $network_and_mask,
                        $found_networks_and_hosts_ref, );
                }
            }
        );
    } 1 .. $max_threads;

    # Wait for all of the threads in @thr to terminate
    $_->join() for @thr;

    #Smart comment for debugging
    ## found_networks_and_hosts: %found_networks_and_hosts;

    #Substitute info we found back into the lines of the ACL
    #Use the previously created array of keys

    for my $network_key (@network_keys) {

        # foreach my $network_key (
        # keys %{ $found_networks_and_hosts_ref->{'networks'} } )    {

        #Get the info we found for this network
        my $number_of_hosts
            = $found_networks_and_hosts_ref->{'networks'}{$network_key}
            {'number_of_hosts'};

        my $status
            = $found_networks_and_hosts_ref->{'networks'}{$network_key}
            {'status'};

        my $network_as_found
            = $found_networks_and_hosts_ref->{'networks'}{$network_key}
            {'as_found'};

        my $network_normalized
            = $found_networks_and_hosts_ref->{'networks'}{$network_key}
            {'normalized'};

        my $list_of_hosts
            = $found_networks_and_hosts_ref->{'networks'}{$network_key}
            {'list_of_hosts'};

        #Color of the text depends on whether we found a specific route for this network (green)
        # or just a default (red)
        my $text_color = $status =~ /default/ix ? 'red' : 'lime';

        #Substitute it back into the original configuration text
        ${$scalar_of_lines_ref}
            =~ s/$network_as_found/<font color = "blue"><font color = "$text_color">$network_as_found<\/font> [ $number_of_hosts hosts <font color = "$text_color">$status<\/font>, matches $list_of_hosts ]<\/font>/g;
    }

}

sub process_hosts_thread {

    #This is the body of the threads that run in parallel
    my ( $host_ip, $found_networks_and_hosts_ref )
        = validate_pos( @_, { type => SCALAR }, { type => HASHREF }, );

    # Get the thread id. Allows each thread to be identified.
    my $id = threads->tid();

    #     say "Thread $id: $host_ip";

    #Do a DNS lookup for the host
    my $name = pretty_addr($host_ip);

    # say "Thread $id: $host_ip -> $name";

    # I'm not sure if we should lock or not...
    # lock($found_networks_and_hosts_ref)->{'hosts'};
    $found_networks_and_hosts_ref->{'hosts'}{$host_ip}{'dns_name'}
        = "$name";

    #How long to wait for a response
    my $timeout = 3;

    #This needs to be 'tcp' or 'udp' on unix systems (or run script as root)
    my $p = Net::Ping->new( $ping_method, $timeout )
        or die "Thread $id: Unable to create Net::Ping object ";

    #Default status is not responding
    my $status = 'NOT RESPONDING';

    if ( $p->ping($host_ip) ) {

        #If the host responded, change its status
        $status = 'UP';
    }

    # say "Thread $id: $host_ip -> $status";
    #Update the hash for this host
    $found_networks_and_hosts_ref->{'hosts'}{$host_ip}{'status'}
        = "$status";
    $p->close;

}

sub process_networks_thread {

    #This is the body of the threads that run in parallel
    #Test if a route for this network even exists in %known_networks hash
    #Other tests could be added here (eg Who owns this block?)
    my ( $network_key, $found_networks_and_hosts_ref )
        = validate_pos( @_, { type => SCALAR }, { type => HASHREF }, );

    # Get the thread id. Allows each thread to be identified.
    my $id = threads->tid();

    #say "Thread $id: $network_key";

    #Get address and mask components
    my $network = $found_networks_and_hosts_ref->{'networks'}{$network_key}
        {'address'};

    my $network_mask
        = $found_networks_and_hosts_ref->{'networks'}{$network_key}{'mask'};

    my $acl_subnet;

    #Does the mask appear to be a subnet mask?
    if ( is_subnet_mask($network_mask) ) {

        #Create a NetAddr object
        $acl_subnet = NetAddr::IP->new("$network/$network_mask");
    }
    else {
        #Assume it's a wildcard_mask
        #This little bit of magic inverts the wildcard mask to a netmask.  Copied from somewhere on the net
        #Note that it doesn't work with non contiguous masks
        my $mask_wild_dotted = $network_mask;
        my $mask_wild_packed = pack 'C4', split /\./, $mask_wild_dotted;

        my $mask_norm_packed = ~$mask_wild_packed;
        my $mask_norm_dotted = join '.', unpack 'C4', $mask_norm_packed;

        #Get the prefix length of this wildcard mask.
        # Works with non-contiguous masks
        my ( $prefix_length, $prefix_length_long )
            = find_longest_subnet_mask_in_wildcard_mask($network_mask);

        #Create a new subnet from captured info
        #         $acl_subnet = NetAddr::IP->new("$network/$mask_norm_dotted");
        $acl_subnet = NetAddr::IP->new("$network/$prefix_length");
    }

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
        #TODO Maybe we should sort by prefix length to get most specific match
        foreach my $known_network ( keys %{$known_networks_ref} ) {
            ## $known_network
            # say "known_network: $known_network";

            #Everything will match default route, let's skip it
            next if ( $known_network eq '0.0.0.0/0' );

            #Create a subnet for the known network
            my $known_subnet = NetAddr::IP->new($known_network);

            #If that worked...
            #(which it won't with some wildcard masks)
            if ($known_subnet) {

                #Is the ACL subnet within the known network?
                if ( $acl_subnet->within($known_subnet) ) {

                    #Update the status of this network
                    $found_networks_and_hosts_ref->{'networks'}
                        {$network_key}{'status'} = "via $known_subnet";
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
            "Network w/ wildcard mask: Couldn't create subnet for $network mask $network_mask";
        $found_networks_and_hosts_ref->{'networks'}{$network_key}{'status'}
            = "BAD_MASK";
    }

    #We've done all our work for this network, let's mark it so it won't get processed again
    $found_networks_and_hosts_ref->{'networks'}{$network_key}{'tested'} = 1;

    #Test how many of this network's hosts respond
    #......
}

sub usage {
    say "";
    say " Usage : ";
    say " $0 <options> <ACL_file1 > <ACL_file 2> <*.acl> etc ";
    say "";
    say "       -p tcp/udp/icmp  Method to use for testing host reachability";
    say "       -t <number>      Maximum number of threads to use";
    say "       -d               Print items mentioned more than once";
    say "";
    exit 1;
}

sub pretty_addr {

    #Return DNS entry for an IP or just the IP if no DNS
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

sub list_of_matches_wildcard {

    #Generate a list of all hosts that would match this network/wildcard_mask pair
    #
    #This routine is completely unoptimized at this point

    #Pass in the variables of ACL network and wildcard mask
    #eg 10.200.128.0 0.0.0.255

    my ( $acl_address, $acl_mask )
        = validate_pos( @_, { type => SCALAR }, { type => SCALAR }, );

    #The array of possible matches
    my ( @all_matches, @ranged_matches );

    #Abort if this looks to be a subnet mask
    if ( is_subnet_mask($acl_mask) ) {
        say "$acl_mask doesn't appear to be a wildcard mask";
        return \@all_matches;
    }

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

    #This generates ranges rather than ALL individual matches
    my $ranged_octet1 = scalar list2ranges(@one);
    my $ranged_octet2 = scalar list2ranges(@two);
    my $ranged_octet3 = scalar list2ranges(@three);
    my $ranged_octet4 = scalar list2ranges(@four);

    push( @ranged_matches,
        "$ranged_octet1.$ranged_octet2.$ranged_octet3.$ranged_octet4" );

    #Assemble the list of ALL possible IP addresses that match
    #Iterating over all options for each octet
    foreach my $octet1 (@one) {
        foreach my $octet2 (@two) {
            foreach my $octet3 (@three) {
                foreach my $octet4 (@four) {

                    #Save this potential match to the array of matches
                    #say "$octet1.$octet2.$octet3.$octet4"
                    push( @all_matches, "$octet1.$octet2.$octet3.$octet4" );
                }
            }
        }
    }
    return \@all_matches, \@ranged_matches;
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

    #Return array of which values from 0..255 matched
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

sub is_subnet_mask {

    #Test if supplied quad is likely a subnet mask or wildcard mask
    my ($mask_to_test) = validate_pos( @_, { type => SCALAR }, );

    #For now I'm just going to check whether the first bit is set and consider
    #that to indicate a subnet mask
    #Perhaps there are better heuristics to consider

    #Split the incoming parameter into 4 octets
    my @mask_octets = split /\./, $mask_to_test;

    #Get the first octet
    my $value     = $mask_octets[0];
    my $test_mask = 0b10000000;        #128

    #Return value is whether they match exactly
    return ( ( $value & $test_mask ) == $test_mask );
}

sub dump_to_file {

    #Simplify dumping a hash to a file
    my ( $file, $aoh_ref ) = @_;

    open my $fh, '>', $file
        or die "Can't write '$file': $!";

    local $Data::Dumper::Terse = 1;    # no '$VAR1 = '
    local $Data::Dumper::Useqq = 1;    # double quoted strings

    print $fh Dumper $aoh_ref;
    close $fh or die "Can't close '$file': $!";
}

sub show_duplicates {

    #Print any host/network that we saw more than once
    my ($found_networks_and_hosts_ref)
        = validate_pos( @_, { type => HASHREF }, );

    say "Duplicates:";
    for my $key ( sort keys %{ $found_networks_and_hosts_ref->{'hosts'} } ) {
        if ( $found_networks_and_hosts_ref->{'hosts'}{$key}{'count'} > 1 ) {
            say $key;
        }
    }
    for my $key ( sort keys %{ $found_networks_and_hosts_ref->{'networks'} } )
    {
        if ( $found_networks_and_hosts_ref->{'networks'}{$key}{'count'} > 1 )
        {
            say $found_networks_and_hosts_ref->{'networks'}{$key}
                {'normalized'};
        }
    }
    return 1;
}

sub list2ranges {

    #From: http://www.perlmonks.org/?node_id=175558
    #Condense a list of numbers down to ranges
    my @list    = sort { $a <=> $b } @_;
    my $current = $list[0];
    my @ranges  = ($current);
    for ( my $i = 1; $i <= @list; $i++ ) {
        if (   $list[$i] && $list[$i] - $current == 1
            || $list[$i]
            && $list[$i] - $current < 1
            && substr( $list[$i], 0, -1 ) eq substr( $current, 0, -1 ) )
        {
            $current = $list[$i];
        }
        else {
            $ranges[-1] .= " - $current" if $ranges[-1] != $current;
            $list[$i] && push @ranges, $current = "$list[$i]";
        }
    }

    return wantarray ? @ranges : join( ", ", @ranges );
}

sub format_number_list {

    #From http://perl.plover.com/qotw/r/solution/006
    my @output;
    while (@_) {
        my $range_start = shift;
        my $range_end   = $range_start;

        # check if the numbers go in sequence from here
        $range_end = shift while ( @_ && $_[0] == $range_end + 1 );

        # ...and add to output accordingly
        if ( $range_start == $range_end ) { push @output, $range_start; }
        else { push @output, "$range_start-$range_end"; }
    }
    join ", ", @output;
}

sub find_longest_subnet_mask_in_wildcard_mask {

    #This is dumb, I know, but I was having trouble with a smarter solution
    #Find first unset bit after finding one set bit

    my $mask = shift;

    my $binary_rep;
    my @octets = split /\./, $mask;
    foreach my $octet (@octets) {

        #Just make one long binary string out of the octets
        $binary_rep .= sprintf( "%08b", $octet );
    }

    #Number of zeros at the beginning of string
    my ($zeroes) = $binary_rep =~ /^([0]+)/;
    my $prefix_length = length($zeroes);

    #Bit position of first 0 after a 1
    my ($zeroes_ones) = $binary_rep =~ /^([0]+[1]+)/;
    my $prefix_length_long = length($zeroes_ones);

    return ( $prefix_length, $prefix_length_long );
}
