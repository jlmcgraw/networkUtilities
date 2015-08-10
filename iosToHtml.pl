#!/usr/bin/perl
# Copyright (C) 2015  Jesse McGraw (jlmcgraw@gmail.com)
#
# Convert a Cisco IOS file to a very basic HTML representation that creates
# links between commands that use lists and those lists, hopefully making it easier
# to follow deeply nested QoS or routing policies

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
#   Yes, I'm reading through the file twice.  I haven't reached the point
#       of really trying to optimize anything
#   Add a unit to numbers we make human readable?
#   Make pointed_at/points_to with a space in them work right
#       eg "track 1" or "ospf 10"
#BUGS
#   wrong link location (first match) when pointed_to occurs twice in string
#       eg: standby 1 track 1 decrement 10

#DONE
#   Match a list of referenced items which correct link for each
#        match ip address prefix-list LIST1 LIST3 LIST3

use Modern::Perl '2014';
use autodie;
use Regexp::Common;

# Uncomment to see debugging comments
# use Smart::Comments;
use NetAddr::IP;
use Number::Bytes::Human qw(format_bytes);
use Number::Format qw(:subs :vars);
use Storable;
use File::Basename;

# use Data::Dumper;
#
# # The sort routine for Data::Dumper
# $Data::Dumper::Sortkeys = sub {
#
#     #Get all the keys for this hash
#     my $keys = join '', keys %{ $_[0] };
#
#     #Are they only numbers?
#     if ( $keys =~ /^ [[:alnum:]]+ $/x ) {
#
#         #Sort keys numerically
#         return [ sort { $a <=> $b or $a cmp $b } keys %{ $_[0] } ];
#     }
#     else {
#         #Keys are not all numeric so sort by alphabetically
#         return [ sort { lc $a cmp lc $b } keys %{ $_[0] } ];
#     }
# };

use Params::Validate qw(:all);
use Getopt::Std;
use FindBin '$Bin';
use vars qw/ %opt /;

#Use this to not print warnings
no if $] >= 5.018, warnings => "experimental";

#Define the valid command line options
my $opt_string = 'ehv';
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

sub main {

    #What constitutes a valid name in IOS
    #OUR because of using it in external files
    our $valid_cisco_name = qr/ [\S]+ /isxm;

    #our $validPointeeNameRegex = qr/ [\S]+ /isxm;

    #The hashes of regexes have been moved to an external file to reduce clutter here
    #Note that the keys/categories in pointers and pointees match (acl, route_map etc)
    #This is so we can match them together properly
    #You must keep pointers/pointees categories in sync if you add new ones
    #
    #Note that we're using the path of the script to load the files ($Bin), in case
    #you run it from some other directory
    #Add a trailing /
    $Bin .= '/';

    #load regexes for numbers we want to reformat
    my %humanReadable = do $Bin . 'human_readable.pl';

    #load regexes for the lists that are referred to ("pointees")
    my %pointees = do $Bin . 'pointees.pl';

    my $host_info_ref;

    #Try to retrieve host_info_hash if user wants to try linking between files
    if ( $opt{e} ) {

        #This is pre-created by find_address_in_configs.pl
        $host_info_ref = retrieve( $Bin . 'host_info_hash.stored' )
            or die "Unable to open host_info_hash";
    }

    #Loop through every file provided on command line
    foreach my $filename (@ARGV) {

        #reset these for each file
        my %foundPointers = ();
        my %foundPointees = ();
        my %pointeeSeen   = ();

        #Open the input and output files
        open my $filehandle,     '<', $filename           or die $!;
        open my $filehandleHtml, '>', $filename . '.html' or die $!;

        #Read in the whole file
        my @array_of_lines = <$filehandle>
            or die $!;    # Reads all lines into array

        #Find all pointees in the file
        my $found_pointees_ref
            = find_pointees( \@array_of_lines, \%pointees );

        #Construct lists of pointees of each type for using in the regexes
        #to make them more explicit for this particular file
        our $list_of_pointees_ref
            = construct_lists_of_pointees($found_pointees_ref);

        #load regexes for commands that refer to other lists of some sort
        #NOTE THAT THESE ARE DYNAMICALLY CONSTRUCTED FOR EACH FILE BASED ON THE
        #POINTEES WE FOUND IN IT ABOVE
        my %pointers = do $Bin . 'pointers.pl';

        ### %pointers

        #Print a simple html beginning to output
        print $filehandleHtml <<"END";
<html>
  <head>
    <title> 
      $filename
    </title>
  </head>

    <body>
        <pre>
END

        #Say the current filename just as a progress indicator
        say $filename;

        #Read each line, one at a time, of this file
        foreach my $line (@array_of_lines) {
            chomp $line;

            #Remove linefeeds
            $line =~ s/\R//gx;

            #Save the current amount of indentation of this line
            my ($current_indent_level) = $line =~ m/^(\s*)/ixsm;

            #Match it against our hash of POINTERS regexes
            foreach my $pointerType ( sort keys %pointers ) {
                foreach
                    my $pointerKey2 ( sort keys $pointers{"$pointerType"} )
                {

                    #The while allows multiple pointers in one line
                    while ( $line
                        =~ m/$pointers{"$pointerType"}{"$pointerKey2"}/g )
                    {
                        #Save what we captured
                        my $unique_id = $+{unique_id};
                        my $points_to = $+{points_to};

                        #Save what we found for debugging
                        $foundPointers{"$line"} .= $points_to;

                        #Points_to can be a list!
                        #See pointers->prefix_list->2 for an example
                        #Split it up and create a link for each element
                        my @fields = split( '\s+', $points_to );

                        foreach my $label (@fields) {

                            #Construct the text of the link
                            my $linkText
                                = '<a href="#'
                                . $pointerType . '_'
                                . $label
                                . "\">$label</a>";

                            #Insert the link back into the line
                            #Link point needs to be surrounded by whitespace or end of line
                            $line =~ s/(\s+) $label (\s+|$)/$1$linkText$2/gx;
                        }

                    }
                }
            }

            #Match it against our hash of POINTEES regexes
            foreach my $pointeeType ( sort keys %pointees ) {
                foreach
                    my $pointeeKey2 ( sort keys $pointees{"$pointeeType"} )
                {
                    if ( $line
                        =~ m/$pointees{"$pointeeType"}{"$pointeeKey2"}/ )
                    {
                        my $unique_id  = $+{unique_id};
                        my $pointed_at = $+{pointed_at};

                        #Save what we found for debugging
                        $foundPointees{$unique_id} = $pointed_at;

                        #Have we seen this pointee already?
                        #We only want to make a link pointer for the first occurrence
                        if ( !$pointeeSeen{$pointeeType}{$unique_id} ) {
                            $pointeeSeen{$pointeeType}{$unique_id}
                                = "$pointed_at";

                            #Add a break <br> to make this stand out from text above it
                            #Add underline/italic to destination line
                            #along with the anchor for links to refer to
                            $line
                                = '<br>' . '<b>'
                                . '<a name="'
                                . $pointeeType . '_'
                                . $pointed_at . '">'
                                . $line . '</a>' . '</b>';

                        }
                    }
                }
            }

            #Did user request to reformat some numbers?
            if ( $opt{h} ) {

                #Match it against our hash of number regexes
                foreach my $human_readable_key ( sort keys %humanReadable ) {

                    #Did we find any matches? (number varies between the regexes)
                    if ( my @matches
                        = ( $line =~ $humanReadable{"$human_readable_key"} ) )
                    {
                        #For each match, reformat the number
                        foreach my $number (@matches) {

                            #Different ways to format the number
                            #my $number_formatted = format_number($number);
                            my $number_formatted = format_bytes($number);

                            #Replace the non-formatted number with the formmated one
                            $line =~ s/$number/$number_formatted/x;
                        }

                    }
                }
            }

            #Did user request to try to link to external files?
            #BUG TODO HACK This section is very experimental currently
            if ( $opt{e} ) {
                given ($line) {

                    #Link to BGP neighbors if we have a config for them
                    when (
                        m/^ \s+ neighbor \s+ (?<neighbor_ip> $RE{net}{IPv4})/ixms
                        )
                    {

                        my $neighbor_ip = $+{neighbor_ip};

                        #                      say $neighbor_ip;

                        if (exists $host_info_ref->{'ip_address'}
                            {$neighbor_ip} )
                        {
                            my ( $file, $interface ) = split( ',',
                                $host_info_ref->{'ip_address'}{$neighbor_ip}
                            );

                            #Pull out the various filename components of the input file from the command line
                            my ( $filename, $dir, $ext )
                                = fileparse( $file, qr/\.[^.]*/x );

                            #Construct the text of the link
                            my $linkText
                                = '<a href="'
                                . $filename
                                . $ext . '.html' . '#'
                                . "interface_$interface"
                                . "\">$neighbor_ip</a>";

                            #Insert the link back into the line
                            #Link point needs to be surrounded by whitespace or end of line
                            $line
                                =~ s/(\s+) $neighbor_ip (\s+|$)/$1$linkText$2/gx;
                        }
                    }

                    #List devices on the same subnet when we know of them
                    when (
                        m/(?: ^ \s+ ip \s+ address \s+ (?<ip_and_mask> $RE{net}{IPv4} \s+ $RE{net}{IPv4}) |
                              ^ \s+ ip \s+ address \s+ (?<ip_and_mask> $RE{net}{IPv4} \s* \/ \d+)
                              )
                        /ixms
                        )

                        #ip address 10.102.54.2 255.255.255.0
                    {

                        my $ip_and_netmask = $+{ip_and_mask};

                        #                      say $ip_and_mask;

                        #HACK In RIOS, there's a space between IP address and CIDR
                        #Remove that without hopefully causing other issues
                        $ip_and_netmask =~ s|\s/|/|;

                        #Try to create a new NetAddr::IP object from this key
                        my $subnet = NetAddr::IP->new($ip_and_netmask);

                        #If it worked...
                        if ($subnet) {

                            #                             my $ip_addr        = $subnet->addr;
                            my $network = $subnet->network;

                            #                             my $mask           = $subnet->mask;
                            #                             my $masklen        = $subnet->masklen;
                            #                             my $ip_addr_bigint = $subnet->bigint();
                            #                             my $isRfc1918      = $subnet->is_rfc1918();
                            #                             my $range          = $subnet->range();

                            #Do we know about this subnet via create_host_info_hashes
                            if ( exists $host_info_ref->{'subnet'}{$network} )
                            {

                                my @peer_array;

                                while ( my ( $peer_file, $peer_interface )
                                    = each $host_info_ref->{'subnet'}
                                    {$network} )
                                {

                                    #Don't list ourself as a peer
                                    if ( $filename =~ $peer_file ) {
                                        next;
                                    }

                                    #Pull out the various filename components of the file
                                    my ( $filename, $dir, $ext )
                                        = fileparse( $peer_file,
                                        qr/\.[^.]*/x );

                                    #Construct the text of the link
                                    my $linkText
                                        = '<a href="'
                                        . $filename
                                        . $ext . '.html' . '#'
                                        . "interface_$peer_interface"
                                        . "\">$filename</a>";

                                    #And save that link
                                    push @peer_array, $linkText;
                                }

                                #Join them all together
                                my $peer_list = join( ' ', @peer_array );

                                #And add them below the IP address line if there
                                #are any peers
                                if ($peer_list) {
                                    $line
                                        .= "\n"
                                        . "$current_indent_level! PEERS: $peer_list";
                                }
                            }
                        }
                    }
                }
            }

            #Print the (possibly) modified line to html file
            say {$filehandleHtml} $line;
        }

        #Close out the file with very basic html ending
        print $filehandleHtml <<"END";
        </pre>
    </body>
</html>
END
        close $filehandle;
        close $filehandleHtml;

        ### %foundPointers
        ### %foundPointees
        ### %pointeeSeen

    }

    return (0);

}

sub usage {
    say "";
    say "Usage:";
    say "   $0 -h <config file1> <config file2> <*.cfg> etc";
    say "       -h Make some numbers human readable";
    say "       -e Try to make links to other files (bgp neighbors, etc)";
    say "";
    exit 1;
}

sub construct_lists_of_pointees {

    #Make a hash of lists, for each type of pointee, of what we've seen defined to use
    #as part of the respective pointer regexes

    my ($pointees_seen_ref)
        = validate_pos( @_, { type => HASHREF }, );

    my %pointees_list = ();

    #Go through each type and save all of the pointees we've seen defined in this file
    foreach my $pointeeType ( sort keys %{$pointees_seen_ref} ) {
        my @list_of_pointees;
        foreach
            my $pointeeKey2 ( sort keys $pointees_seen_ref->{"$pointeeType"} )
        {
            #Add this label to our list
            push( @list_of_pointees,
                $pointees_seen_ref->{"$pointeeType"}{"$pointeeKey2"} );

        }

        #Sort them by length, longest first
        #This is done so stuff like COS2V will match COS2V instead of just COS2
        #Perhaps regex could also be changed to use \b
        @list_of_pointees
            = sort { length $b <=> length $a } @list_of_pointees;

        #Make a list of those names joined by |
        #This list is what will be used in the pointer regex (see pointers.pl)
        $pointees_list{$pointeeType} = join( ' | ', @list_of_pointees );
    }
    ### %pointees_list
    return \%pointees_list;
}

sub find_pointees {

    #Construct a hash of the types of pointees we've seen in this file
    my ( $array_of_lines_ref, $pointee_regex_ref )
        = validate_pos( @_, { type => ARRAYREF }, { type => HASHREF } );

    my %foundPointees = ();

    foreach my $line (@$array_of_lines_ref) {
        chomp $line;

        #Remove linefeeds
        $line =~ s/\R//gx;

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

                    #Have we seen this pointee already?
                    #We only want to make a link pointer for the first occurrence
                    if ( !$foundPointees{$pointeeType}{$unique_id} ) {
                        $foundPointees{$pointeeType}{$unique_id}
                            = "$pointed_at";

                    }
                }
            }
        }
    }
    ### %foundPointees
    return \%foundPointees;
}
