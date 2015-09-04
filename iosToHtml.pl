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
#   How to handle cases where pointer doesn't match pointee?
#       eg: channel-group 20 -> Etherchannel20

#   Hightlight missing pointees in red?
#   Yes, I'm reading through the file twice.  I haven't reached the point
#       of really trying to optimize anything
#   Add a unit to numbers we make human readable?
#   Make pointed_at/points_to with a space in them work right
#       eg "track 1" or "ospf 10"
#BUGS
#   wrong link location (first match) when pointed_to occurs twice in string
#       eg: standby 1 track 1 decrement 10

#DONE
#   Maybe should regenerate overall host info hash each run?
#   Make this work as CGI
#   Match a list of referenced items which correct link for each
#        match ip address prefix-list LIST1 LIST3 LIST3

#Standard modules
use strict;
use warnings;
use autodie;
use Storable;
use File::Basename;
use threads;
use Thread::Queue;
use Benchmark qw(:hireswallclock);
use Getopt::Std;
use FindBin '$Bin';
use vars qw/ %opt /;
use Config;

# use Data::Dumper;
# # #Look into using this so users don't need to install modules
use lib "$FindBin::Bin/local/lib/perl5";

#Additional modules
use Modern::Perl '2014';
use Regexp::Common;
use NetAddr::IP;
use Number::Bytes::Human qw(format_bytes);
use Number::Format qw(:subs :vars);
use Params::Validate qw(:all);

#Smart_Comments=0 perl my_script.pl
# to run without smart comments, and
#Smart_Comments=1 perl my_script.pl
use Smart::Comments -ENV;

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

#Use this to not print warnings
# no if $] >= 5.018, warnings => "experimental";

#Define the valid command line options
my $opt_string = 'eh';
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

#Set variables from command line options
my ( $should_link_externally, $should_reformat_numbers )
    = ( $opt{e}, $opt{h} );

#Hold a copy of the original ARGV so we can pass it instead of globbed version to create_host_info_hashes
my @ARGV_unmodified;

#Expand wildcards on command line since windows doesn't do it for us
if ( $Config{archname} =~ m/win/ix ) {

    #Expand wildcards on command line
    say "Expanding wildcards for Windows";
    @ARGV_unmodified = @ARGV;
    @ARGV = map {glob} @ARGV;
}

#Call main routine
exit main(@ARGV);

sub main {

    # start timer
    my $start = new Benchmark;

    #What constitutes a valid name in IOS
    #OUR because of using it in external regex files
    #Could fine tune if I ever look up the list of valid characters
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

    #load regexes for numbers we want to reformat
    my %humanReadable = do $Bin . 'human_readable.pl';

    #load regexes for the items that are pointed at ("pointees")
    my %pointees = do $Bin . 'pointees.pl';

    my $host_info_ref = {};

    #Try to retrieve host_info_hash if user wants to try linking between files
    if ($should_link_externally) {

        #Let's recreate this every time
        #         #This hash must be pre-created by create_host_info_hashes.pl
        #         if ( !-e $Bin . 'host_info_hash.stored' ) {
        say "Creating host_info_hash";

        #Pass the unglobbed command line under Windows so command line isn't too long
        my $status;
        if ( $Config{archname} =~ m/win/ix ) {
            $status = system( $Bin
                    . "create_host_info_hashes.pl @ARGV_unmodified" );
        }
        else {
            $status = system( $Bin . 'create_host_info_hashes.pl',
                map {"$_"} @ARGV );
        }
        if ( ( $status >>= 8 ) != 0 ) {
            die "Failed to run " . $Bin . "create_host_info_hashes.pl $!";
        }

        #         }
        say "Loading host_info_hash";
        $host_info_ref = retrieve( "$Bin" . 'host_info_hash.stored' )
            or die "Unable to open host_info_hash";
    }

    # A new empty queue
    my $q = Thread::Queue->new();

    ## @ARGV
    # Queue up all of the files for the threads
    #     $q->enqueue($_) for @ARGV;
    foreach my $file (@ARGV) {
        if ( -e $file ) {
            $q->enqueue($file);
        }
        else {
            say "$file does not exist";
        }
    }
    $q->end();

    #Return if there's no files to process
    return 0 unless $q->pending();

    say $q->pending() . " files queued";

    # Maximum number of worker threads
    # BUG TODO Adjust this dynamically based on number of CPUs
    my $thread_limit = 3;

    #Create $thread_limit worker threads calling "config_to_html"
    my @thr = map {
        threads->create(
            sub {
                while ( defined( my $filename = $q->dequeue_nb() ) ) {
                    config_to_html(
                        $filename,       \%pointees,
                        \%humanReadable, $host_info_ref
                    );
                }
            }
        );
    } 1 .. $thread_limit;

    # terminate all of the threads in @thr
    $_->join() for @thr;

    # end timer
    my $end = new Benchmark;

    # calculate difference
    my $diff = timediff( $end, $start );

    # report
    say "Time taken was ", timestr( $diff, 'all' ), " seconds";

    return (0);

}

sub usage {
    say "";
    say "Usage:";
    say "   $0 -h <config file1> <config file2> <*.cfg> etc";
    say "";
    say "       -h Make some numbers human readable";
    say "";
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

        foreach my $rule_number (
            sort keys %{ $pointees_seen_ref->{"$pointeeType"} } )
        {
            #Add this label to our list
            push( @list_of_pointees,
                $pointees_seen_ref->{"$pointeeType"}{"$rule_number"} );

        }

        #Sort them by length, longest first
        #This is done so stuff like COS2V will match COS2V instead of just COS2
        # TODO Perhaps regex could also be changed to use \b
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

        #Remove linefeeds
        $line =~ s/\R//gx;

        #Match it against our hash of pointees regexes
        foreach my $pointeeType ( sort keys %{$pointee_regex_ref} ) {
            foreach my $rule_number (
                sort keys %{ $pointee_regex_ref->{"$pointeeType"} } )
            {
                if ( $line
                    =~ $pointee_regex_ref->{"$pointeeType"}{"$rule_number"} )
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
    return \%foundPointees;
}

sub config_to_html {
    my ( $filename, $pointees_ref, $human_readable_ref, $host_info_ref )
        = validate_pos(
        @_,
        { type => SCALAR },
        { type => HASHREF },
        { type => HASHREF },
        { type => HASHREF },
        );

    #reset these for each file
    my %foundPointers        = ();
    my %foundPointees        = ();
    my %pointee_seen_in_file = ();

    #Open the input and output files
    open my $filehandle, '<', $filename or die $!;

    #Read in the whole file
    my @array_of_lines = <$filehandle>
        or die $!;    # Reads all lines into array

    #chomp the whole array in one fell swoop
    chomp @array_of_lines;

    my @html_formatted_text;

    #Find all pointees (things that are pointed TO) in the file
    my $found_pointees_ref = find_pointees( \@array_of_lines, $pointees_ref );

    #Construct lists of these pointees of each type for using in the POINTER regexes
    #to make them more explicit for this particular file
    our $list_of_pointees_ref
        = construct_lists_of_pointees($found_pointees_ref);

    #load regexes for commands that refer to other lists of some sort
    #NOTE THAT THESE ARE DYNAMICALLY CONSTRUCTED FOR EACH FILE BASED ON THE
    #POINTEES WE FOUND IN IT ABOVE in "construct_lists_of_pointees"
    my %pointers = do $Bin . 'pointers.pl';

    ### %pointers

    # Get the thread id. Allows each thread to be identified.
    my $id = threads->tid();
    say "Thread $id: $filename";

    #Find the hostname
    my ($hostname)
        = map { /^ \s* hostname \s+ (\S+) \b/ix ? $1 : () } @array_of_lines;

    #If we didn't find a name set a default
    $hostname //= 'no name';

    #Read each line, one at a time, of this file
    foreach my $line (@array_of_lines) {

        #Remove linefeeds
        $line =~ s/\R//gx;

        #Remove trailing whitespace
        $line =~ s/\s+$//gx;

        #Save the current amount of indentation of this line
        #to make stuff we might insert line up right (eg PEERS)
        my ($current_indent_level) = $line =~ m/^(\s*)/ixsm;

        #Match $line against our hash of POINTERS regexes
        #add HTML link to matching lines
        foreach my $pointerType ( sort keys %pointers ) {
            foreach
                my $rule_number ( sort keys %{ $pointers{"$pointerType"} } )
            {

                #The while allows multiple pointers in one line
                while (
                    $line =~ m/$pointers{"$pointerType"}{"$rule_number"}/g )
                {
                    #Save what we captured
                    #                     my $unique_id = $+{unique_id};
                    my $points_to = $+{points_to};

                    #abort if $points_to isn't defined
                    unless ($points_to) {

                        #say "Null points_to:";
                        #say $pointers{"$pointerType"}{"$rule_number"};
                        #say "\t$line";
                        #say "\tpointer_type: $pointerType | rule: $rule_number";
                        next;
                    }

                    #Save what we found for debugging
                    $foundPointers{"$line"}
                        = "Points_to: $points_to | pointerType: $pointerType | RuleNumber: $rule_number";

                    #Points_to can be a list!
                    #See pointers->prefix_list->2 for an example
                    #Split it up and create a link for each element

                    #                     #Trying a hack here to work with identifiers that have spaces in them
                    #                     #Remove ?-x from pointers->interface->#11
                    #                     #Set pointees->interface->#2 back to $valid_cisco_name
                    #                     my @fields;
                    #
                    #                     if ($pointerType =~ /interface/ix) {
                    #                         push @fields, $points_to;
                    #                     }
                    #                     else {
                    #                         @fields = split( '\s+', $points_to );
                    #                     }

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

                        #                         #Notice the (?-x:$label)
                        #                         #That's disabling ignoring spaces just for the $label part
                        #                         #Handles identifiers with spaces in them
                        #                         $line =~ s/(\s+) (?-x:$label) (\s+|$)/$1$linkText$2/gx;
                    }

                }
            }
        }

        #Match $line against our hash of POINTEES regexes
        #add HTML anchor to matching lines
        foreach my $pointeeType ( sort keys %{$pointees_ref} ) {
            foreach my $rule_number (
                sort keys %{ $pointees_ref->{"$pointeeType"} } )
            {
                if ( $line
                    =~ m/$pointees_ref->{"$pointeeType"}{"$rule_number"}/ )
                {
                    my $unique_id  = $+{unique_id};
                    my $pointed_at = $+{pointed_at};

                    #Save what we found for debugging
                    $foundPointees{$unique_id} = $pointed_at;

                    #Have we seen this pointee already?
                    #We only want to make a section marker for the first occurrence
                    if ( !$pointee_seen_in_file{$pointeeType}{$unique_id} ) {
                        $pointee_seen_in_file{$pointeeType}{$unique_id}
                            = "$pointed_at";

                        #                         my $anchor_text = '<a name="'
                        #                             . $pointeeType . '_'
                        #                             . $pointed_at . '">'
                        #                             . $pointed_at
                        #                             . '</a>';

                        #                         #Add the section anchor
                        #                         $line
                        #                             =~ s/ (\s+) $pointed_at ( \s+ | $ ) /$1$anchor_text$2/ixg;

                        #Add a span for what's actually pointed at
                        #See "output_as_html" to adjust styling via cs
                        $line
                            =~ s/ (\s+) $pointed_at ( \s+ | $ ) /$1<span class="pointed_at">$pointed_at<\/span>$2/ixg;

                        #Add a span for links to refer to
                        #See "output_as_html" to adjust styling via css
                        $line
                            = '<br>'
                            . '<span id="'
                            . $pointeeType . '_'
                            . $pointed_at . '" '
                            . 'class="pointee"' . '>'
                            . $line
                            . '</span>';

                    }
                }
            }
        }

        #Did user request to reformat some numbers?
        if ($should_reformat_numbers) {

            #Match it against our hash of number regexes
            foreach
                my $human_readable_key ( sort keys %{$human_readable_ref} )
            {

                #Did we find any matches? (number of captured items varies between the regexes)
                if ( my @matches
                    = ( $line
                            =~ $human_readable_ref->{"$human_readable_key"} )
                    )
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
        if ($should_link_externally) {
            given ($line) {

                #Link to BGP neighbors if we have a config for them
                when (
                    m/^ \s+ neighbor \s+ (?<neighbor_ip> $RE{net}{IPv4})/ixms
                    )
                {

                    my $neighbor_ip = $+{neighbor_ip};

                    #say $neighbor_ip;

                    if ( exists $host_info_ref->{'ip_address'}{$neighbor_ip} )
                    {
                        my ( $file, $interface )
                            = split( ',',
                            $host_info_ref->{'ip_address'}{$neighbor_ip} );

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
                        if ( exists $host_info_ref->{'subnet'}{$network} ) {

                            my @peer_array;

                            while ( my ( $peer_file, $peer_interface )
                                = each
                                %{ $host_info_ref->{'subnet'}{$network} } )
                            {

                                #Don't list ourself as a peer
                                if ( $filename =~ quotemeta $peer_file ) {
                                    next;
                                }

                                #Pull out the various filename components of the file
                                my ( $filename, $dir, $ext )
                                    = fileparse( $peer_file, qr/\.[^.]*/x );

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

                #Hosts in ACLs
                when (
                    m/^ \s+ (?: permit | deny ) \s+ .*? host \s+ (?<host_ip> $RE{net}{IPv4})/ixms
                    )
                {

                    my $host_ip = $+{host_ip};

                    #                      say $host_ip;

                    #Is this particular IP referenced in our pre-collected host_info_hash
                    if ( exists $host_info_ref->{'ip_address'}{$host_ip} ) {

                        #Get the file and interface the IP was referenced in
                        my ( $file, $interface )
                            = split( ',',
                            $host_info_ref->{'ip_address'}{$host_ip} );

                        #Pull out the various filename components of the input file from the command line
                        my ( $filename, $dir, $ext )
                            = fileparse( $file, qr/\.[^.]*/x );

                        #Construct the text of the link
                        my $linkText
                            = '<a href="'
                            . $filename
                            . $ext . '.html' . '#'
                            . "interface_$interface"
                            . "\">$host_ip</a>";

                        #Insert the link back into the line
                        #Link point needs to be surrounded by whitespace or end of line
                        $line =~ s/(\s+) $host_ip (\s+|$)/$1$linkText$2/gx;
                    }
                }

                #IP SLA
                when (
                    m/\w+ \s +source-ip \s+ (?<host_ip> $RE{net}{IPv4})/ixms)
                {

                    my $host_ip = $+{host_ip};

                    #                      say $host_ip;

                    #Is this particular IP referenced in our pre-collected host_info_hash
                    if ( exists $host_info_ref->{'ip_address'}{$host_ip} ) {

                        #Get the file and interface the IP was referenced in
                        my ( $file, $interface )
                            = split( ',',
                            $host_info_ref->{'ip_address'}{$host_ip} );

                        #Pull out the various filename components of the input file from the command line
                        my ( $filename, $dir, $ext )
                            = fileparse( $file, qr/\.[^.]*/x );

                        #Construct the text of the link
                        my $linkText
                            = '<a href="'
                            . $filename
                            . $ext . '.html' . '#'
                            . "interface_$interface"
                            . "\">$host_ip</a>";

                        #Insert the link back into the line
                        #Link point needs to be surrounded by whitespace or end of line
                        $line =~ s/(\s+) $host_ip (\s+|$)/$1$linkText$2/gx;
                    }
                }
            }
        }

        #Save the (possibly) modified line for later printing
        push @html_formatted_text, $line

    }

    #Construct the floating menu
    my $floating_menu_text = construct_floating_menu(
        $filename, \@html_formatted_text,
        $hostname, \%pointee_seen_in_file
    );

    #Output as a web page
    output_as_html( $filename, \@html_formatted_text, $hostname,
        $floating_menu_text );

    close $filehandle;

    ### %foundPointers
    ### %foundPointees
    ### %pointee_seen_in_file
}

sub construct_floating_menu {

    #Construct a menu from the pointees we've seen in this file

    my ( $filename, $html_formatted_text_ref, $hostname, $pointees_ref )
        = validate_pos(
        @_,
        { type => SCALAR },
        { type => ARRAYREF },
        { type => SCALAR },
        { type => HASHREF },
        );

    #Construct a menu from the pointees we've seen in this file
    my $file_basename = basename($filename);

    #First occurrence of each type of pointee
    my @first_occurence_of_pointees;

    #Copy the array of html-ized test to a scalar
    my $config_as_html = join "", @$html_formatted_text_ref;

    #for each pointee we found in this config
    foreach my $pointee_type ( sort keys %{$pointees_ref} ) {

        #find only the first occurrence
        my $regex = qr/<span \s+ id="(?<type> $pointee_type .*? )"/x;
        $config_as_html =~ /$regex/ix;

        #Save it
        push @first_occurence_of_pointees, "$pointee_type|$+{type}";
    }

    #First portion of the HTML
    my $menu_text = << "END_MENU";
<div class="floating-menu">
    <h3>$hostname ($file_basename)</h3>
    <a href="#">Top</a>
    <h4>Beginning of Sections</h4>
END_MENU

    #Create a link for each type of pointee
    map {
        #Split up what we pushed earlier
        my ( $type, $specific ) = split( '\|', $_ );

        #Fix case on $type
        $type = ucfirst $type;

        #Construct the link
        #         $menu_text .= "<div><a href=\"#$specific\" style=\"text-align: right\">$type</a>" . "</div>\n";
        $menu_text .= "<a href=\"#$specific\">$type</a>" . "\n";
    } @first_occurence_of_pointees;

    #Close of the DIV in the html
    $menu_text .= '</div>';

    #Return the constructed text
    return $menu_text;
}

sub output_as_html {
    my ($filename, $html_formatted_text_ref,
        $hostname, $floating_menu_text
        )
        = validate_pos(
        @_,
        { type => SCALAR },
        { type => ARRAYREF },
        { type => SCALAR },
        { type => SCALAR },
        );

    open my $filehandleHtml, '>', $filename . '.html' or die $!;

    #Print a simple html beginning to output
    print $filehandleHtml <<"END";
<!DOCTYPE html>
<html>

    <head>
        <meta charset="UTF-8">
        <title>     
            $filename
        </title>
        <style>
            :target{
                background-color: #ffa;
                }
            .pointee {
                font-weight: bold;
                }
            .pointed_at {
                font-style: italic;
                }
            .to_top_label{
                position: fixed; 
                top:10px;
                right:10px;
                color: white;
                background-color: Blue;
                text-decoration:none
                }
            div.floating-menu {
                position:fixed;
                top:10px;
                right:10px;
                background:#fff4c8;
                padding:5px;
                z-index:100;
                }
            div.floating-menu a, div.floating-menu h3, div.floating-menu h4 {
                text-align: right;
                text-decoration:none;
                display:block;
                margin:0 0.5em;
                }
            div.floating-menu a:hover {
                color: grey;
                }
                
        </style>
    </head>
    <body>
        <pre>
END
    say {$filehandleHtml} join( "\n", @$html_formatted_text_ref );

    #say {$filehandleHtml} $line;
    #Close out the file with very basic html ending
    print $filehandleHtml <<"END";
        </pre>
        $floating_menu_text
    </body>
</html>
END

    close $filehandleHtml;
}
