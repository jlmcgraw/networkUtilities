#!/usr/bin/perl
# Copyright (C) 2015  Jesse McGraw (jlmcgraw@gmail.com)
#
# Collect information (IP addresses, hostnames, subnets etc) from a set
# of IOS configuration files to aid in inter-device linking with iosToHtml
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
# Expand this to create regexes for each file too, so iosToHtml doesn't have to ecah time
#BUGS

#DONE

use Modern::Perl '2014';
use autodie;
use Regexp::Common;

# Uncomment to see debugging comments
# use Smart::Comments;

use Data::Dumper;
use Params::Validate qw(:all);
use Getopt::Std;
use FindBin '$Bin';
use NetAddr::IP;
use vars qw/ %opt /;
use Storable;
use Hash::Merge qw(merge);

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

#Use this to not print warnings
no if $] >= 5.018, warnings => "experimental";

#Define the valid command line options
my $opt_string = 'hv';
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

#Call main routine
exit main(@ARGV);

#-------------------------------------------------------------------------------

sub main {

    #What constitutes a valid name in IOS
    #OUR because of using it in external files
    our $valid_cisco_name = qr/ [\S]+ /isxm;

    #The hashes of regexes have been moved to an external file to reduce clutter here
    #Note that the keys/categories in pointers and pointees match (acl, route_map etc)
    #This is so we can match them together properly
    #You must keep pointers/pointees categories in sync if you add new ones
    #
    #Note that we're using the path of the script to load the files ($Bin), in case
    #you run it from some other directory
    #Add a trailing /
    $Bin .= '/';

    #load regexes for the lists that are referred to ("pointees")
    my %pointees = do $Bin . 'external_pointees.pl';

    #For collecting overall info
    my $overall_hash_ref;

    #Where will we store the host_info_hash
    my $host_info_storefile = 'host_info_hash.stored';

    #Loop through every file provided on command line
    foreach my $filename (@ARGV) {

        #reset these for each file
        my %foundPointees = ();
        my %pointeeSeen   = ();

        #Open the input and output files
        open my $filehandle, '<', $filename or die $!;

        #Read in the whole file
        my @array_of_lines = <$filehandle>
            or die $!;    # Reads all lines into array

        #Progress indicator
        say $filename;

        #Find all pointees in this file
        my $found_pointees_ref
            = find_pointees( \@array_of_lines, \%pointees, $filename );

        #Calculate subnets etc for this host's IP addresses
        calculate_subnets( $found_pointees_ref, $filename );

        #Add the new hash of hashes to our overall hash
        $overall_hash_ref = merge( $found_pointees_ref, $overall_hash_ref );

        close $filehandle;

    }

    #Save the hash back to disk
    store( $overall_hash_ref, $host_info_storefile )
        || die "can't store to $host_info_storefile\n";

    #To read it in
    #$host_info_hash_ref = retrieve($host_info_storefile);
    # %overall_hash

    #Dump the hash to a human-readable file
    dump_to_file( 'host_info_hash.txt', $overall_hash_ref );

    return (0);

}

sub usage {
    say "Create an overall hash of info from each configuration file to be used with iosToHtml";
    say ""
    say "Usage:";
    say "   $0 <config file1> <config file2> <*.cfg> etc";
    say "";
    exit 1;
}

sub find_pointees {

    #Construct a hash of the types of pointees we've seen in this file
    my ( $array_of_lines_ref, $pointee_regex_ref, $filename ) = validate_pos(
        @_,
        { type => ARRAYREF },
        { type => HASHREF },
        { type => SCALAR },
    );

    my %foundPointees = ();

    #Keep track of the last interface name we saw
    my $current_interface;

    foreach my $line (@$array_of_lines_ref) {
        chomp $line;

        #Remove linefeeds
        $line =~ s/\R//gx;

        #Update the last seen interface name if we see a new one
        $line
            =~ /^ \s* interface \s+ (?<current_interface> .*?) (?: \s | $) /ixsm;
        $current_interface = $+{current_interface} if $+{current_interface};

        #Match it against our hash of pointees regexes
        foreach my $pointeeType ( sort keys %{$pointee_regex_ref} ) {
            foreach
                my $pointeeKey2 ( keys $pointee_regex_ref->{"$pointeeType"} )
            {
                if ( $line
                    =~ $pointee_regex_ref->{"$pointeeType"}{"$pointeeKey2"} )
                {
                    my $unique_id  = $+{unique_id};
                    my $pointed_at = $+{pointed_at};

                    #Add the current interface name for ip_addresses
                    if ( $pointeeType eq 'ip_address' ) {
                        $foundPointees{$filename}{$pointeeType}{$unique_id}
                            = "$pointed_at,$current_interface";
                    }
                    else {
                        $foundPointees{$filename}{$pointeeType}{$unique_id}
                            = "$pointed_at";
                    }

                }
            }
        }
    }
    return \%foundPointees;
}

sub calculate_subnets {

    #Do subnet calculations on each IP address we found
    #Add these as new hashes to use in external lookups in iosToHtml

    my ( $pointees_seen_ref, $filename )
        = validate_pos( @_, { type => HASHREF }, { type => SCALAR }, );

    #For every IP address we found
    foreach my $ip_address_key (
        sort keys $pointees_seen_ref->{$filename}{'ip_address'} )
    {

        #Split out IP address and interface components
        my ( $ip_and_netmask, $interface )
            = split( ',',
            $pointees_seen_ref->{$filename}{'ip_address'}{$ip_address_key} );

        #Try to create a new NetAddr::IP object from this key
        my $subnet = NetAddr::IP->new($ip_and_netmask);

        #If it worked...
        if ($subnet) {

            my $ip_addr        = $subnet->addr;
            my $network        = $subnet->network;
            my $mask           = $subnet->mask;
            my $masklen        = $subnet->masklen;
            my $ip_addr_bigint = $subnet->bigint();
            my $isRfc1918      = $subnet->is_rfc1918();
            my $range          = $subnet->range();

            #All info by filename
            $pointees_seen_ref->{$filename}{"subnet"}{$network} = 1;

            #All info by IP address pointing to file name
            $pointees_seen_ref->{'ip_address'}{$ip_addr}
                = "$filename,$interface";

            #All info by subnet pointing to file name
            $pointees_seen_ref->{'subnet'}{$network}{$filename} = $interface;

            #Smart comment
            # ### $pointees_seen_ref

        }
    }

    return 1;
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
