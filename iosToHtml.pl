#!/usr/bin/perl
# Copyright (C) 2015  Jesse McGraw (jlmcgraw@gmail.com)
#
# Convert a Cisco confuration file (IOS, NXOS, PIX/ASA, ACE) to an HTML
# representation that creates links between commands that use lists and those
# lists, hopefully making it easier to follow their logic (eg QoS, routing
# policies, voice setups etc etc)
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
# External pointer lists
#   eg
#        set ip next-hop 10.1.192.1 10.1.192.9
#
#   How to handle cases where pointer doesn't match pointee?
#       Add per-match callbacks to edit pointer/pointee?
#       eg: channel-group 20 -> Etherchannel20
#
#   Highlight missing pointees in red?
#
#   Yes, I'm reading through the file twice.  I haven't reached the point
#       of really trying to optimize anything
#
#   Add a unit to numbers we make human readable?
#
#   Are we recompiling regexes needlessly?
#
#   Collapse lists of things
#       1) items that all begin with same thing (eg "ip access-list xx"
#       2) Items that have same indent level (eg interfaces)
#       3) Groups of #1 or #2

#BUGS
#   wrong link location (finds first match) when pointed_to occurs twice in string
#       eg: standby 1 track 1 decrement 10
#       Would be fixed by having identifiers with spaces in them
#       eg "track 1" instead of "1"

#DONE
#   Maybe should regenerate overall host info hash each run?
#   Make this work as CGI
#   Match a list of referenced items which correct link for each
#        match ip address prefix-list LIST1 LIST3 LIST3
#   Make pointed_at/points_to with a space in them work right
#       eg
#         "track 1"
#         "ospf 10"
#         "sip-profiles 1"
#
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
use Data::Dumper;
use Carp;
use Fcntl qw/ :flock /;

#Look into using this so users don't need to install modules
use lib "$FindBin::Bin/local/lib/perl5";

#Non-core additional modules
use Modern::Perl '2014';
use Regexp::Common;
use NetAddr::IP;
use Number::Bytes::Human qw(format_bytes);
use Number::Format qw(:subs :vars);
use Params::Validate qw(:all);
use Smart::Comments -ENV;
use Sys::CpuAffinity;

# use Memoize;
use Regexp::Assemble;
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
# no if $] >= 5.018, warnings => "experimental";

#Define the valid command line options
my $opt_string = 'ehfnsru';
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
my ($should_link_externally,     $should_reformat_numbers,
    $should_do_extra_formatting, $dont_use_threads,
    $should_scrub,               $should_remove_redundancy,
    $should_write_unused_report
) = ( $opt{e}, $opt{h}, $opt{f}, $opt{n}, $opt{s}, $opt{r}, $opt{u} );

#Hold a copy of the original ARGV so we can pass it instead of globbed version
#to create_host_info_hashes
my @ARGV_unmodified;

#Expand wildcards on command line since windows doesn't do it for us
if ( $Config{archname} =~ m/win/ix ) {
    use File::Glob ':bsd_glob';

    #Expand wildcards on command line
    say "Expanding wildcards for Windows";
    @ARGV_unmodified = @ARGV;
    @ARGV = map { bsd_glob $_ } @ARGV;
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

    my $hex_digits = qr/[A-F0-9]{8}/ix;
    our $cert_line = qr/(?: $hex_digits (?: \s+ | $ ) ){8}/ix;

    #An octet
    my $octetRegex = qr/(?: 25[0-5] | 2[0-4]\d | [01]?\d\d? )/mx;

    #An IP address is made of octets
    our $ipv4AddressRegex = qr/$octetRegex\.
                                $octetRegex\.
                                $octetRegex\.
                                $octetRegex/mx;

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

    #load regexes for redundancies we want to remove
    my %redundancies = do $Bin . 'redundancies.pl';

    #     #Testing pre-compiling of regexes
    #     my %compiled_pointees;
    #     foreach my $pointee_type (sort keys %pointees) {
    #         my @array;
    #         foreach my $rule_number (sort keys %{ $pointees{$pointee_type} }){
    #             push @array, qr/$pointees{$pointee_type}{$rule_number}/;
    #             }
    #         $compiled_pointees{$pointee_type} = \@array;
    #         }
    #
    #     print Dumper \%compiled_pointees;
    #     exit;

    #load regexes for the items that may point to other files at ("external-pointers")
    my %external_pointers = do $Bin . 'external_pointers.pl';

    #A hash reference for information about all hosts in this run
    my $host_info_ref = {};

    #Try to retrieve host_info_hash if user wants to try linking between files
    if ($should_link_externally) {
        $host_info_ref = create_external_host_info_hash();
    }

    #Create the header of the unused pointee report
    if ($should_write_unused_report) {
        open my $filehandleHtml, '>', 'unused.html' or die $!;

        #Print a simple html beginning to output
        print $filehandleHtml <<"END";
<!DOCTYPE html>
<html>

    <head>
        <meta charset="UTF-8">
        <title>     
            Unused pointees report
        </title>
    </head>
END
    }
    my $unused_report_filehandle;

    #     if ($should_write_unused_report) {
    #         my $unused_report_filename = "./unused.html";
    #         say "Creating unused pointee html report";
    #         open $main::unused_report_filehandle, ">", $unused_report_filename or die("Could not open file. $!");
    #         }

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

    my $number_of_files_queued = $q->pending();
    say "$number_of_files_queued files queued";

    # Maximum number of worker threads
    # BUG TODO Adjust this dynamically based on number of CPUs
    # my $thread_limit = 3;

    if ($dont_use_threads) {
        say "Not using threads";

        while ( defined( my $filename = $q->dequeue_nb() ) ) {
            config_to_html( $filename, \%pointees, \%humanReadable,
                $host_info_ref, \%external_pointers );
        }
    }
    else {
        #Get the current number of CPUs
        my $num_cpus = Sys::CpuAffinity::getNumCpus();

        #say "$num_cpus processors available";

        #Create $main::num_cpus worker threads calling "config_to_html"
        say "Using $num_cpus threads";
        my @thr = map {
            threads->create(
                sub {
                    while ( defined( my $filename = $q->dequeue_nb() ) ) {
                        config_to_html( $filename, \%pointees,
                            \%humanReadable,
                            $host_info_ref, \%external_pointers,
                            \%redundancies );
                    }
                }
            );
        } 1 .. $num_cpus;

        # terminate all of the threads in @thr
        $_->join() for @thr;
    }

    #Close the unused report if we opened it
    if ($unused_report_filehandle) {
        close $unused_report_filehandle;
    }

    # end timer
    my $end = new Benchmark;

    # calculate difference
    my $diff            = timediff( $end, $start );
    my $duration_of_run = $diff->cpu_a;
    my $time_per_file   = $duration_of_run / $number_of_files_queued;

    # report
    say "Time taken was ", timestr( $diff, 'all' ), " seconds";
    say "$time_per_file CPU seconds per file";
    return (0);

}

sub usage {
    say "";
    say "Usage:";
    say "   $0 -h <config file1> <config file2> <*.cfg> etc";
    say "";
    say "       -h Make some numbers human readable";
    say "";
    say
        "       -e Try to make links to other configs from this same set (bgp neighbors, route next hops etc)";
    say "";
    say
        "       -f Do some extra formatting (italic comments, permits/green denies/red)";
    say "";
    say "       -n Don't use threads (for debugging/profiling)";
    say "";
    say "       -s Do a simple scrub of sensitive info";
    say "";
    say "       -r Remove some redundancy between lines";
    say "";
    say "       -u Create an HTML list of unused pointees";
    say "";
    say "To run with smart comments enabled:";
    say "	Smart_Comments=1 perl $0";
    exit 1;
}

sub construct_lists_of_pointees {

    #Make a hash of lists, for each type of pointee, of what we've seen defined
    #in this file so we can use them as part of the respective pointer regexes

    my ($pointees_seen_ref)
        = validate_pos( @_, { type => HASHREF }, );

    my %pointees_list = ();

    #Go through each type and save all of the pointees of that type that
    # we've seen defined in this file
    foreach my $pointeeType ( sort keys %{$pointees_seen_ref} ) {

        #         my $ra = Regexp::Assemble->new( flags => '-x' );
        my @list_of_pointees;

        #         my @raw_list_of_pointees;

        foreach my $rule_number (
            sort keys %{ $pointees_seen_ref->{"$pointeeType"} } )
        {

            #             #Add this label to our list for Regexp::Assemble
            #             push( @raw_list_of_pointees,
            #                 $pointees_seen_ref->{"$pointeeType"}{"$rule_number"} );

            #             #Add this label to our list
            #             #This version doesn't handle whitespace in pointees
            #             push( @list_of_pointees,
            #                       '(?: '
            #                     . $pointees_seen_ref->{"$pointeeType"}{"$rule_number"}
            #                     . ')' );

            #             %HoF = (    # Compose a hash of functions
            #                 exit => sub {exit},
            #                 help => \&show_help,
            #                 watch => sub { $watch = 1 },
            #                 mail => sub { mail_msg($msg) },
            #                 edit => sub { $edited++; editmsg($msg); },
            #                 delete => \&confirm_kill,
            #             );
            #
            #             if ( $HoF{ lc $cmd } )
            #                 { $HoF{ lc $cmd }->(); }    # Call function
            #             else
            #                 { warn "Unknown command: `$cmd'; Try `help' next time\n" }

            #Testing pointees with spaces in them
            #BUG TODO REMOVE If issues with finding pointees and uncomment above method
            #Please notice the use of ?-x to disable ignoring whitespace
            #Add this label to our list
            push( @list_of_pointees,
                      '(?-x:'
                    . $pointees_seen_ref->{"$pointeeType"}{"$rule_number"}
                    . ')' );

        }

        #Sort them by length, longest first
        #This is done so stuff like COS2V will match COS2V instead of just COS2
        # TODO Perhaps regex could also be changed to use \b
        @list_of_pointees
            = sort { length $b <=> length $a } @list_of_pointees;

        #Make a list of those names joined by |
        #This list is what will be used in the pointer regex (see pointers.pl)
        $pointees_list{$pointeeType} = join( ' | ', @list_of_pointees );

        #         @raw_list_of_pointees
        #         = sort { length $b <=> length $a } @raw_list_of_pointees;
        #
        #         #Create a minimal regex from the whole list of pointees
        #         map { $ra->add( "$_" ) } @raw_list_of_pointees;
        #         $pointees_list{$pointeeType} = $ra->re;

        #         say $ra->re;
    }

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
    my ( $filename, $pointees_ref, $human_readable_ref, $host_info_ref,
        $external_pointers_ref, $redundancies_ref )
        = validate_pos(
        @_,
        { type => SCALAR },
        { type => HASHREF },
        { type => HASHREF },
        { type => HASHREF },
        { type => HASHREF },
        { type => HASHREF },
        );

    my $subnet_regex_ref
        = qr/(?: ^ \s+ ip \s+ address \s+ (?<ip_and_mask> $RE{net}{IPv4} \s+ $RE{net}{IPv4}) ) |
                          (?: ^ \s+ ip \s+ address \s+ (?<ip_and_mask> $RE{net}{IPv4} \s* \/ \d+) )
                        /ixsm;

    my $network_regex = qr/(?: ^ \s+ 
                network \s+ 
                (?<network> 
                    $RE{net}{IPv4} ) \s+
                mask \s+
                (?<mask> 
                    $RE{net}{IPv4} )
            ) 
            /ixsm;

    #reset these for each file
    my %foundPointers = ();

    #     my %foundPointees        = ();
    my %pointee_seen_in_file = ();
    my @html_formatted_text;

    #Open the input and output files
    open my $filehandle, '<', $filename or die $!;

    #Read in the whole file
    my @array_of_lines = <$filehandle>
        or die $!;    # Reads all lines into array
    close $filehandle;

    #chomp the whole array in one fell swoop
    chomp @array_of_lines;

    #Find all pointees (things that are pointed TO) in this particular file
    my $found_pointees_ref = find_pointees( \@array_of_lines, $pointees_ref );
    ### <file>[<line>]
    ### found_pointees_ref

    #Construct "OR" lists (eg a|b|c|d) of the found pointees of each type for
    # using in the POINTER regexes to make them more explicit for this
    # particular file
    our $list_of_pointees_ref
        = construct_lists_of_pointees($found_pointees_ref);
    ### <file>[<line>]
    ### $list_of_pointees_ref

    #Load regexes for commands that refer to other lists of some sort
    #NOTE THAT THESE ARE DYNAMICALLY CONSTRUCTED FOR EACH FILE BASED ON THE
    #POINTEES WE FOUND IN IT ABOVE in "construct_lists_of_pointees"
    my %pointers = do $Bin . 'pointers.pl';

    #Delete pointers that have no possible pointees, hopefully speeding things
    #up
    delete_pointers_with_no_pointees( \%pointers, $list_of_pointees_ref );
    ### <file>[<line>]
    ### %pointers

    # Get the thread id. Allows each thread to be identified.
    my $id = threads->tid();
    say "Thread $id: $filename";

    #Search the whole file to find the hostname
    my ($hostname)
        = map { /^ \s* hostname \s+ (\S+) \b/ix ? $1 : () } @array_of_lines;

    #If we didn't find a name set a default
    $hostname //= 'no name';

    #     memoize('reformat_numbers');
    #     memoize('add_pointer_links_to_line');
    #     memoize('add_pointee_links_to_line');
    #     memoize('process_external_pointers');
    #     memoize('find_subnet_peers');
    #     memoize('extra_formatting');

    #Process each line, one at a time, of this file
    foreach my $line (@array_of_lines) {

        #Remove linefeeds
        $line =~ s/\R//gx;

        #Remove trailing whitespace
        $line =~ s/\s+$//gx;

        #Scrub passwords etc. if user requested
        $line = scrub($line) if $should_scrub;

        #Did user request to reformat some numbers?
        $line = reformat_numbers( $line, $human_readable_ref )
            if $should_reformat_numbers;

        #Add pointer links
        $line
            = add_pointer_links_to_line( $line, \%pointers, \%foundPointers );

        #Remove some redundancy if user requested
        $line = remove_redundancy( $line, $redundancies_ref )
            if $should_remove_redundancy;

        #Add pointee links
        $line = add_pointee_links_to_line( $line, $pointees_ref,
            $found_pointees_ref, \%pointee_seen_in_file, \%foundPointers );

        #Did user request to try to link to external files?
        if ($should_link_externally) {

            #Simple external links to one IP address
            $line = process_external_pointers( $line,
                $external_pointers_ref, $host_info_ref );

            #Find the devices from this run with interfaces on the same subnet and list them
            #as peers
            $line
                = find_subnet_peers( $line, $filename,
                $external_pointers_ref, $host_info_ref, $subnet_regex_ref );
        }

        #Find the interfaces on this device that are relevant to a routing
        # process
        $line
            = find_routing_interfaces( $line, $filename,
            $external_pointers_ref, $host_info_ref, $network_regex );

        #Some experimental formatting (colored permits/denies, comments are italic etc)
        $line = extra_formatting($line) if $should_do_extra_formatting;

        #Save the (possibly) modified line for later printing
        push @html_formatted_text, $line;
    }

    #Find any pointee that doesn't seem to have something pointing to it
    #and change its CSS class
    my $config_as_html_ref = find_pointees_with_nothing_pointing_to_them(
        \@html_formatted_text );

    #Construct the floating menu unique to this file
    my $floating_menu_text
        = construct_floating_menu( $filename, \@html_formatted_text,
        $hostname, \%pointee_seen_in_file, $config_as_html_ref );

    #Output as a web page
    output_as_html( $filename, \@html_formatted_text,
        $hostname, $floating_menu_text, $config_as_html_ref );

    #Do we want to add to the global report of unused pointees?
    if ($should_write_unused_report) {
        write_unused_pointee_report( $filename, $hostname,
            $config_as_html_ref );
    }
    ### <file>[<line>]
    ### %foundPointers
    ### %pointee_seen_in_file
    return;
}

sub delete_pointers_with_no_pointees {

    #Clean out pointers with no possible pointees

    my ( $pointers_ref, $list_of_pointees_ref )
        = validate_pos( @_, { type => HASHREF }, { type => HASHREF }, );

    while ( my ( $rule_type, $rule_number ) = each %{$pointers_ref} ) {
        if ( !( exists $list_of_pointees_ref->{"$rule_type"} ) ) {

            #say "$rule_type has no list";
            delete $pointers_ref->{$rule_type};
        }
    }
}

sub find_pointees_with_nothing_pointing_to_them {
    my ( $html_formatted_text_ref, )
        = validate_pos( @_, { type => ARRAYREF }, );

    #Copy the array of html-ized test to a scalar
    my $config_as_html = join "\n", @$html_formatted_text_ref;

    #Find the names of all the pointers and create a hash from it
    my @array_of_pointers = $config_as_html =~ /<a href="#(.*?)">/g;
    my %pointers = map { $_, 1 } @array_of_pointers;

    #Find the names of all the pointees and create a hash from it
    my @array_of_pointees = $config_as_html =~ /id="(.*?)" class="pointee">/g;
    my %pointees = map { $_, 1 } @array_of_pointees;

    #Delete every POINTEE that has a POINTER
    foreach my $pointer ( keys %pointers ) {
        if ( exists $pointees{$pointer} ) {
            delete $pointees{$pointer};
        }
    }

    #At this point, pointees contains only things that haven't been pointed at
    #So change their CSS class
    foreach my $unused_pointee ( keys %pointees ) {
        my $class = 'unused_pointee';

        #Ignore interfaces and routing processes since they don't get referred to quite often
        if ( $unused_pointee =~ /interface_|routing_/ix ) {
            $class = '';
        }

        #Update this unused pointee's CSS class
        $config_as_html
            =~ s/id="$unused_pointee" class="pointee">/id="$unused_pointee" class="$class">/g;
    }

    return \$config_as_html;
}

sub construct_floating_menu {

    #Construct a menu from the pointees we've seen in this file

    my ( $filename, $html_formatted_text_ref, $hostname, $pointees_ref,
        $config_as_html_ref )
        = validate_pos(
        @_,
        { type => SCALAR },
        { type => ARRAYREF },
        { type => SCALAR },
        { type => HASHREF },
        { type => SCALARREF },
        );

    #Construct a menu from the pointees we've seen in this file
    my $file_basename = basename($filename);

    #First occurrence of each type of pointee
    my @first_occurence_of_pointees;

    #Copy the array of html-ized text to a scalar
    my $config_as_html = join "", @$html_formatted_text_ref;

    #for each pointee we found in this config
    foreach my $pointee_type ( sort keys %{$pointees_ref} ) {

        #find only the first occurrence
        my $regex = qr/<span \s+ id="(?<type> $pointee_type .*? )"/x;
        $config_as_html =~ /$regex/ix;

        #Save it
        push @first_occurence_of_pointees, "$pointee_type|$+{type}";
    }

    #First portion of the menu's HTML
    my $menu_text = << "END_MENU";
<div class="floating-menu">
    <h3>$hostname ($file_basename)</h3>
    <a href="#">Top</a>
    <br>
    <h4><u>Beginnings of Sections</u></h4>
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

    $menu_text .= '<br>' . "\n";
    $menu_text .= '<h4><u>Key</u></h4>' . "\n";
    $menu_text .= '<span class="unused_pointee">Unused Pointee</span>' . "\n";
    $menu_text .= '<span class="pointee">Used Pointee</span>' . "\n";
    $menu_text .= '<span class="deny">Deny/No</span>' . "\n";
    $menu_text .= '<span class="permit">Permit/Included</span>' . "\n";
    $menu_text .= '<span class="remark">Remark/Description</span>' . "\n";

    #Regex for unused pointees
    my $unused_pointee_regex = qr/
                                <span 
                                \s+ 
                                id="(?<id> .*? )"
                                \s+
                                class="unused_pointee"
                                /ix;

    #Construct a list of unused pointees
    my (@list_of_unused_pointees)
        = $$config_as_html_ref =~ /$unused_pointee_regex/igx;

    #If there actually are any unused pointees then add links to the floating menu
    if (@list_of_unused_pointees) {

        #Sort the list alphabetically
        @list_of_unused_pointees = sort @list_of_unused_pointees;

        $menu_text .= '<br>';
        $menu_text .= '<h4><u>Unused Pointees</u></h4>' . "\n";

        #Add links to each unused pointee to the floating menu
        map {
            my $pointee_id = $_;

            #Append this link to the floating menu
            $menu_text .= "<a href=\"#$pointee_id\">$pointee_id</a>" . "\n";
        } @list_of_unused_pointees;
    }

    #Close of the DIV in the html
    $menu_text .= '</div>';

    #Return the constructed text
    return $menu_text;
}

sub write_unused_pointee_report {

    #Create an HTML list of unused pointees in this file

    my ( $filename, $hostname, $config_as_html_ref ) = validate_pos(
        @_,
        { type => SCALAR },
        { type => SCALAR },
        { type => SCALARREF },
    );

    my $file_basename = basename($filename);

    #Regex for unused pointees
    my $unused_pointee_regex = qr/
                                <span 
                                \s+ 
                                id="(?<id> .*? )"
                                \s+
                                class="unused_pointee"
                                /ix;

    #Construct a list of unused pointees
    my (@list_of_unused_pointees)
        = $$config_as_html_ref =~ /$unused_pointee_regex/igx;

    #If there actually are any unused pointees then add links to the report
    if (@list_of_unused_pointees) {

        #Add links to each unused pointee to the report
        map {
            my $pointee_id = $_;

            #Construct the HTML
            my $external_link_text
                = "<a href=\"$filename.html#$pointee_id\">$hostname : $file_basename : $pointee_id</a><br>"
                . "\n";

            #Write to the report file, thread safe
            append_message_to_file($external_link_text, 'unused.html');

        } sort @list_of_unused_pointees;
    }
    return 0;
}

sub output_as_html {
    my ( $filename, $html_formatted_text_ref,
        $hostname, $floating_menu_text, $config_as_html_ref )
        = validate_pos(
        @_,
        { type => SCALAR },
        { type => ARRAYREF },
        { type => SCALAR },
        { type => SCALAR },
        { type => SCALARREF },
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
            a {
            text-decoration:none;
            }
            a:link, a:visited {
                color:blue;
                }
            a:hover, a:visited:hover {
                color: white;
                background-color: blue;
                }
            :target {
                background-color: #ffa;
                }
            .pointee {
                font-weight: bold;
                }
            .unused_pointee {
                color: white;
                background-color:orange
                }
            .pointed_at {
                font-style: italic;
                }
            .deny {
                color: red;
                }
            .permit {
                color: green;
                }
            .remark {
                font-style: italic;
                }
            .remark_subtle {
                font-style: italic;
                opacity: .40;
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
                opacity: .90;
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
                color: white;
                }
            div.floating-menu .unused_pointee, div.floating-menu .pointee,  
            div.floating-menu .remark,  div.floating-menu .deny,  
            div.floating-menu .permit {
                text-align: right;
                display:block;
                }
        </style>
    </head>
    <body>
        <pre>
END

    #     say {$filehandleHtml} join( "\n", @$html_formatted_text_ref );
    say {$filehandleHtml} $$config_as_html_ref;

    #say {$filehandleHtml} $line;
    #Close out the file with very basic html ending
    print $filehandleHtml <<"END";
        </pre>
        $floating_menu_text
    </body>
</html>
END

    close $filehandleHtml;
    return;
}

sub process_external_pointers {

    #Construct a menu from the pointees we've seen in this file

    my ( $line, $external_pointers_ref, $host_info_ref ) = validate_pos(
        @_,
        { type => SCALAR },
        { type => HASHREF },
        { type => HASHREF },
    );

    #Match $line against our hash of EXTERNAL_POINTERS regexes
    #add HTML link to matching lines
    foreach my $pointerType ( sort keys %{$external_pointers_ref} ) {
        foreach my $rule_number (
            sort keys %{ $external_pointers_ref->{"$pointerType"} } )
        {

            #The while allows multiple pointers in one line
            while ( $line
                =~ m/$external_pointers_ref->{"$pointerType"}{"$rule_number"}/xg
                )
            {
                my $neighbor_ip = $+{external_ipv4};

                #say $neighbor_ip;

                if ( exists $host_info_ref->{'ip_address'}{$neighbor_ip} ) {
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
                        . "\" title=\"$filename\">$neighbor_ip</a>";

                    #Insert the link back into the line
                    #Link point needs to be surrounded by whitespace or end of line
                    $line =~ s/(\s+) $neighbor_ip (\s+|$)/$1$linkText$2/gx;
                }

            }
        }
    }
    return $line;
}

sub reformat_numbers {

    #Make some numbers easier to read (add thousands separator etc)
    my ( $line, $human_readable_ref )
        = validate_pos( @_, { type => SCALAR }, { type => HASHREF }, );

    #Match it against our hash of number regexes
    foreach my $human_readable_key ( sort keys %{$human_readable_ref} ) {

        #Did we find any matches? (number of captured items varies between the regexes)
        if ( my @matches
            = ( $line =~ $human_readable_ref->{"$human_readable_key"} ) )
        {
            #For each match, reformat the number
            foreach my $number (@matches) {

                #Different ways to format the number, choose what you like
                my $number_formatted = format_number($number);

                #my $number_formatted = format_bytes($number);

                #Replace the non-formatted number with the formmated one
                $line =~ s/$number/$number_formatted/x;
            }

        }
    }
    return $line;
}

sub find_subnet_peers {

    my ( $line, $our_filename, $external_pointers_ref, $host_info_ref,
        $subnet_regex_ref )
        = validate_pos(
        @_,
        { type => SCALAR },
        { type => SCALAR },
        { type => HASHREF },
        { type => HASHREF },
        { type => SCALARREF },
        );

    #List devices on the same subnet when we know of them
    if ( $line =~ m/$subnet_regex_ref/ixms ) {

        my $ip_and_netmask = $+{ip_and_mask};

        #Save the current amount of indentation of this line
        #to make stuff we might insert line up right (eg PEERS)
        my ($current_indent_level) = $line =~ m/^(\s*)/ixsm;

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
            my $masklen = $subnet->masklen;

            #                             my $ip_addr_bigint = $subnet->bigint();
            #                             my $isRfc1918      = $subnet->is_rfc1918();
            #                             my $range          = $subnet->range();

            #Do we know about this subnet via create_host_info_hashes?
            if ( exists $host_info_ref->{'subnet'}{$network} ) {

                my @peer_array;

                #TODO BUG Make this sort
                #                             while ( my ( $peer_file, $peer_interface )
                #                                 = each
                #                                 %{ $host_info_ref->{'subnet'}{$network} } )
                foreach my $peer_file (
                    sort
                    keys %{ $host_info_ref->{'subnet'}{$network} }
                    )
                {

                    my $peer_interface
                        = $host_info_ref->{'subnet'}{$network}{$peer_file};

                    #Don't list ourself as a peer
                    if ( $our_filename =~ quotemeta $peer_file ) {
                        next;
                    }

                    #Pull out the various filename components of the file
                    my ( $peer_filename, $dir, $ext )
                        = fileparse( $peer_file, qr/\.[^.]*/x );

                    #Construct the text of the link
                    my $linkText
                        = '<a href="'
                        . $peer_filename
                        . $ext . '.html' . '#'
                        . "interface_$peer_interface"
                        . "\">$peer_filename</a>";

                    #And save that link
                    push @peer_array, $linkText;
                }

                #Join them all together
                my $peer_list  = join( ' | ', @peer_array );
                my $peer_count = @peer_array;
                my $peer_form  = $peer_count > 1 ? "PEERS" : "PEER";

                #And add them below the IP address line if there
                #are any peers
                if ($peer_list) {
                    $line
                        .= "\n"
                        . '<span class="remark_subtle">'
                        . "$current_indent_level! $peer_count $peer_form on $network: $peer_list"
                        . '</span>';
                }
            }
        }

    }

    return $line;
}

sub find_routing_interfaces {

    my ( $line, $our_filename, $external_pointers_ref, $host_info_ref,
        $network_regex )
        = validate_pos(
        @_,
        { type => SCALAR },
        { type => SCALAR },
        { type => HASHREF },
        { type => HASHREF },
        { type => SCALARREF },
        );

    #List devices on the same subnet when we know of them
    if ( $line =~ m/$network_regex/ixms ) {

        my $network = $+{network};
        my $mask    = $+{mask};

        #Save the current amount of indentation of this line
        #to make stuff we might insert line up right (eg PEERS)
        my ($current_indent_level) = $line =~ m/^(\s*)/ixsm;

        #HACK In RIOS, there's a space between IP address and CIDR
        #Remove that without hopefully causing other issues
        #         $ip_and_netmask =~ s|\s/|/|;

        #Try to create a new NetAddr::IP object from this key
        my $subnet = NetAddr::IP->new("$network $mask");

        #If it worked...
        if ($subnet) {

            #                             my $ip_addr        = $subnet->addr;
            my $network = $subnet->network;

            #                             my $mask           = $subnet->mask;
            my $masklen = $subnet->masklen;

            #                             my $ip_addr_bigint = $subnet->bigint();
            #                             my $isRfc1918      = $subnet->is_rfc1918();
            #                             my $range          = $subnet->range();

            #Do we know about this subnet via create_host_info_hashes?
            if ( exists $host_info_ref->{'subnet'}{$network} ) {

                my @peer_array;

                #TODO BUG Make this sort
                #                             while ( my ( $peer_file, $peer_interface )
                #                                 = each
                #                                 %{ $host_info_ref->{'subnet'}{$network} } )
                foreach my $peer_file (
                    sort
                    keys %{ $host_info_ref->{'subnet'}{$network} }
                    )
                {

                    my $peer_interface
                        = $host_info_ref->{'subnet'}{$network}{$peer_file};

                    #                     #Don't list ourself as a peer
                    #                     if ( $our_filename =~ quotemeta $peer_file ) {
                    #                         next;
                    #                     }

                    #Pull out the various filename components of the file
                    my ( $peer_filename, $dir, $ext )
                        = fileparse( $peer_file, qr/\.[^.]*/x );

                    #Construct the text of the link
                    my $linkText
                        = '<a href="'
                        . $peer_filename
                        . $ext . '.html' . '#'
                        . "interface_$peer_interface"
                        . "\">$peer_filename-$peer_interface</a>";

                    #And save that link
                    push @peer_array, $linkText;
                }

                #Join them all together
                my $peer_list  = join( ' | ', @peer_array );
                my $peer_count = @peer_array;
                my $peer_form  = $peer_count > 1 ? "interfaces" : "interface";

                #And add them below the IP address line if there
                #are any peers
                if ($peer_list) {
                    $line
                        .= "\n"
                        . '<span class="remark_subtle">'
                        . "$current_indent_level! $peer_count $peer_form on $network: $peer_list"
                        . "\n"
                        . '</span>';
                }
            }
        }

    }

    return $line;
}

sub extra_formatting {
    my ($line) = validate_pos( @_, { type => SCALAR }, );

    #Style PERMIT lines
    $line
        =~ s/ (\s+) (permit|included) (  .*? $  ) /$1<span class="permit">$2$3<\/span>/ixg;

    #Style DENY lines
    $line
        =~ s/ (\s+) (deny|excluded) (  .*?  $ ) /$1<span class="deny">$2$3<\/span>/ixg;

    #Style NO lines
    $line
        =~ s/^( \s* ) (no) (  .*?  $ ) /$1<span class="deny">$2$3<\/span>/ixg;

    #Style REMARK lines
    $line
        =~ s/ (\s+) (remark|description) ( .*? $ ) /$1<span class="remark">$2$3<\/span>/ixg;

    #Style CONFORM-ACTION lines
    $line
        =~ s/ (\s+) (conform-action) ( .*? $ ) /$1<span class="permit">$2$3<\/span>/ixg;

    #Style EXCEED-ACTION lines
    $line
        =~ s/ (\s+) (exceed-action) ( .*? $ ) /$1<span class="deny">$2$3<\/span>/ixg;

    return $line;
}

sub scrub {
    my ($line) = validate_pos( @_, { type => SCALAR }, );

    #BUG TODO A quick hack to see if replacing "host x.x.x.x" with
    # x.x.x.x 0.0.0.0 looks any better
    #     $line =~ s/host ($main::ipv4AddressRegex)/$1 0.0.0.0/gi;

    $line =~ s/password .*/password SCRUBBED/gi;
    $line =~ s/secret .*/secret SCRUBBED/gi;
    $line =~ s/snmp-server community [^ ]+/snmp-server community SCRUBBED/gi;
    $line =~ s/(key-string \s+ \d+) \s+ \S+/$1 SCRUBBED/gix;
    $line =~ s/(tacacs-server \s+ key \s+ \d+) \s+ \S+/$1 SCRUBBED/gix;
    $line =~ s/(tacacs-server \s+ 
                host \s+ 
                $main::ipv4AddressRegex \s+ 
                key \s+ 
                \d+) \s+ \S+/$1 SCRUBBED/gix;
    $line
        =~ s/(snmp-server \s+ host \s+  $main::ipv4AddressRegex ) \s+ \S+/$1 SCRUBBED/gix;
    $line =~ s/(flash.?:) \S+/$1 SCRUBBED/gix;
    $line =~ s/$main::cert_line/SCRUBBED/gix;
    $line =~ s/\s+sn\s+\S+/ sn SCRUBBED/gix;
    $line =~ s/(crypto \s+ isakmp \s+ key) \s+ \S+/$1 SCRUBBED/gix;

    return $line;
}

sub remove_redundancy {
    my ( $line, $redundancies_ref )
        = validate_pos( @_, { type => SCALAR }, { type => HASHREF }, );

    state $last_line;
    state $match;

    #For each of the things we consider potentially redundant/noisy
    foreach my $key ( sort keys %{$redundancies_ref} ) {
        my $redundancy_regex = $redundancies_ref->{$key};

        #Does this line match?
        if ( $line =~ /$redundancy_regex/ ) {

            #Collect what matched
            $match = $+{match};

            #Does the last line also fully match (note the \b)?
            if ( $last_line =~ /^\s*$match\b/ ) {

                #Save our unmodified line
                $last_line = $line;

                #Create a replacement string of the correct length
                #  my $replacement_text = ' ' x length $match;

                #Create a replacement string of the correct length
                ( my $replacement_text = $match ) =~ s/\S/-/g;

                #and substitute it back into the line
                ( my $modified_line = $line ) =~ s/$match/$replacement_text/;

                #Return the modified line
                return $modified_line;
            }
        }
    }

    #Save the current line for the next iteration
    $last_line = $line;

    return $line;
}

sub add_pointer_links_to_line {
    my ( $line, $pointers_ref, $found_pointers_ref ) = validate_pos(
        @_,
        { type => SCALAR },
        { type => HASHREF },
        { type => HASHREF },
    );

    #Match $line against our hash of POINTERS regexes
    #add HTML link to matching lines
    foreach my $pointerType ( sort keys %{$pointers_ref} ) {
        foreach
            my $rule_number ( sort keys %{ $pointers_ref->{"$pointerType"} } )
        {

            #The while allows multiple pointers in one line
            while ( $line
                =~ m/$pointers_ref->{"$pointerType"}{"$rule_number"}/xg )
            {
                #Save what we captured
                #my $unique_id = $+{unique_id};
                my $points_to = $+{points_to};

                #abort if $points_to isn't defined
                unless ($points_to) {

                    #say "Null points_to:";
                    #say $pointers_ref{"$pointerType"}{"$rule_number"};
                    #say "\t$line";
                    #say "\tpointer_type: $pointerType | rule: $rule_number";
                    next;
                }

                #Save what we found for debugging
                $found_pointers_ref->{
                    "$line|$pointerType|$rule_number|$points_to"}
                    = "Points_to: $points_to | pointerType: $pointerType | RuleNumber: $rule_number";

                #Save this for helping us determine which pointees have pointers referring to them
                $found_pointers_ref->{ "$pointerType" . '_' . "$points_to" }
                    = "$line";

                my @fields;

                #Does this specific rule support space separated lists?
                if ( $rule_number =~ /_list/ix ) {

                    #Split it up by whitespace
                    @fields = split( '\s+', $points_to );

                }
                else {
                    #Else treat the whole thing as one pointer
                    push @fields, $points_to;

                }

                #Now for each pointer we found...
                foreach my $label (@fields) {

                    #Construct the text of a link
                    my $linkText
                        = '<a href="#'
                        . $pointerType . '_'
                        . $label
                        . "\">$label</a>";

                    #Insert the link back into the line
                    #Link point needs to be surrounded by whitespace or end of line
                    #                     $line =~ s/(\s+) $label (\s+|$)/$1$linkText$2/gx;

                    #Notice the (?-x:$label)
                    #That's disabling ignoring spaces just for the $label part
                    #Handles identifiers with spaces in them
                    $line =~ s/(\s+) (?-x:$label) (\s+|$)/$1$linkText$2/gx;
                }

            }
        }
    }
    return $line;
}

sub add_pointee_links_to_line {
    my ( $line, $pointees_ref, $found_pointees_ref,
        $pointee_seen_in_file_ref, $found_pointers_ref )
        = validate_pos(
        @_,
        { type => SCALAR },
        { type => HASHREF },
        { type => HASHREF },
        { type => HASHREF },
        { type => HASHREF },
        );

    #Match $line against our hash of POINTEES regexes
    #add HTML anchor to matching lines
    foreach my $pointeeType ( sort keys %{$pointees_ref} ) {
        foreach
            my $rule_number ( sort keys %{ $pointees_ref->{"$pointeeType"} } )
        {
            if ($line =~ m/$pointees_ref->{"$pointeeType"}{"$rule_number"}/x )
            {
                my $unique_id  = $+{unique_id};
                my $pointed_at = $+{pointed_at};

                #Save what we found for debugging
                $found_pointees_ref->{$unique_id} = $pointed_at;

                #Have we seen this pointee already?
                #We only want to make a section marker for the first occurrence
                if ( !$pointee_seen_in_file_ref->{$pointeeType}{$unique_id} )
                {
                    $pointee_seen_in_file_ref->{$pointeeType}{$unique_id}
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
                    #See "output_as_html" to adjust styling via CSS
                    $line
                        =~ s/ (\s+) $pointed_at ( \s+ | $ ) /$1<span class="pointed_at">$pointed_at<\/span>$2/ixg;

                    my $class   = "pointee";
                    my $span_id = $pointeeType . '_' . $pointed_at;

                    #Add a span for links to refer to
                    #See "output_as_html" to adjust styling via css
                    $line
                        = '<br>'
                        . '<span id="'
                        . $span_id . '" '
                        . 'class="'
                        . $class . '">'
                        . $line
                        . '</span>';

                    #Don't loop anymore since each line can only be one pointee
                    return $line;
                }
            }
        }
    }
    return $line;
}

sub external_linking_find_pointees {

    #Construct a hash of the types of pointees we've seen in this file
    my ( $array_of_lines_ref, $pointee_regex_ref, $filename ) = validate_pos(
        @_,
        { type => ARRAYREF },
        { type => HASHREF },
        { type => SCALAR },
    );

    my %foundPointees = ();

    #Keep track of the last interface name we saw
    my $current_interface = "unknown";

    foreach my $line (@$array_of_lines_ref) {
        chomp $line;

        #Remove linefeeds
        $line =~ s/\R//gx;

        #Update the last seen interface name if we see a new one
        $line
            =~ /^ \s* interface \s+ (?<current_interface> .*?) (?: \s | $) /ixsm;
        $current_interface = $+{current_interface} if $+{current_interface};

        #         $current_interface //= "unknown";

        #Match it against our hash of pointees regexes
        foreach my $pointeeType ( sort keys %{$pointee_regex_ref} ) {
            foreach my $pointeeKey2 (
                keys %{ $pointee_regex_ref->{"$pointeeType"} } )
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
        sort keys %{ $pointees_seen_ref->{$filename}{'ip_address'} } )
    {

        #Split out IP address and interface components
        my ( $ip_and_netmask, $interface )
            = split( ',',
            $pointees_seen_ref->{$filename}{'ip_address'}{$ip_address_key} );

        #HACK In RIOS, there's a space between IP address and CIDR
        #Remove that without hopefully causing other issues
        $ip_and_netmask =~ s|\s/|/|;

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
            # ### <file>[<line>]
            # ### $pointees_seen_ref

        }
        else {
            say "Couldn't create subnet for $ip_and_netmask";
        }
    }

    return 1;
}

sub create_external_host_info_hash {

    #Let's recreate this every time
    #         #This hash must be pre-created by create_host_info_hashes.pl
    #         if ( !-e $Bin . 'host_info_hash.stored' ) {
    say "Gather info for external linking";

    #         #Pass the unglobbed command line under Windows so command line isn't too long
    #         my $status;
    #
    #         if ( $Config{archname} =~ m/win/ix ) {
    #             $status = system( $Bin
    #                     . "create_host_info_hashes.pl @ARGV_unmodified" );
    #         }
    #         else {
    #             $status = system( $Bin . 'create_host_info_hashes.pl',
    #                 map {"$_"} @ARGV );
    #         }
    #
    #         if ( ( $status >>= 8 ) != 0 ) {
    #             die "Failed to run " . $Bin . "create_host_info_hashes.pl $!";
    #         }
    #
    #         #         }
    #         say "Loading host_info_hash";
    #         $host_info_ref = retrieve( "$Bin" . 'host_info_hash.stored' )
    #             or die "Unable to open host_info_hash";
    #load regexes for the lists that are referred to ("pointees")
    my %pointees = do $Bin . 'external_pointees.pl';

    #For collecting overall info
    my $overall_hash_ref;

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

        close $filehandle;

        #Progress indicator
        say $filename;

        #Find all pointees in this file
        my $found_pointees_ref
            = external_linking_find_pointees( \@array_of_lines, \%pointees,
            $filename );

        #Calculate subnets etc for this host's IP addresses
        calculate_subnets( $found_pointees_ref, $filename );

        #Merge this new hash of hashes into our overall hash
        $overall_hash_ref = merge( $found_pointees_ref, $overall_hash_ref );

    }

    #             #Where will we store the host_info_hash
    #             my $host_info_storefile = "$Bin" . 'host_info_hash.stored';

    #             #Save the hash back to disk
    #             store( $overall_hash_ref, $host_info_storefile )
    #                 || die "can't store to $host_info_storefile\n";

    #To read it in:
    #$host_info_hash_ref = retrieve($host_info_storefile);
    # %overall_hash

    #             #Dump the hash to a human-readable file
    #             dump_to_file( "$Bin" . 'host_info_hash.txt', $overall_hash_ref );

    #A reference to the hash of host information
    #         $host_info_ref = $overall_hash_ref;
    return $overall_hash_ref;

    #             print Dumper $host_info_ref;
    #             exit;
    #             return (0);

}

sub append_message_to_file {

    #Append to a file, locking it to ensure thread safety
    my ( $msg, $filename )
        = validate_pos( @_, { type => SCALAR }, { type => SCALAR }, );

    open my $fh, ">>", $filename or die "$0 [$$]: open: $!";
    flock $fh, LOCK_EX or die "$0 [$$]: flock: $!";
    print $fh "$msg\n" or die "$0 [$$]: write: $!";
    close $fh or warn "$0 [$$]: close: $!";
}
