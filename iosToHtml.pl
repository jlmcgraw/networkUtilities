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
#   Add a unit to numbers we make human readable?
#BUG wrong link location when pointed_to occurs twice in string
#   eg: standby 1 track 1 decrement 10

#DONE

use Modern::Perl '2014';
use autodie;
use Regexp::Common;

# Uncomment to see debugging comments
# use Smart::Comments;

use Number::Bytes::Human qw(format_bytes);
use Number::Format qw(:subs :vars);

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

sub main {

    #What constitutes a valid name in IOS
    #OUR because of using in external files
    our $valid_cisco_name      = qr/ [\S]+ /isxm;
    our $validPointeeNameRegex = qr/ [\S]+ /isxm;

    #These hashes of regexes have been moved to an external file to reduce clutter here
    #Note that the keys/categories in pointers and pointees match (acl, route_map etc)
    #This is so we can linkify properly
    #You must keep pointers/pointees categories in sync
    #
    #Note that we're using the path of the script to load the files ($Bin), in case
    #you run it from some other directory
    #Add a trailing /
    $Bin .= '/';
    
    #regexes for numbers we want to reformat
    my %humanReadable = do $Bin . 'human_readable.pl';

    #regexes for commands that refer to other lists of some sort
    my %pointers = do $Bin . 'pointers.pl';

    #regexes for the lists that are referred to
    my %pointees = do $Bin . 'pointees.pl';

    #Loop through every file provided on command line
    foreach my $filename (@ARGV) {

        #reset these for each file
        my %foundPointers = ();
        my %foundPointees = ();
        my %pointeeSeen   = ();

        #Open the input and output files
        open my $filehandle,     '<', $filename           or die $!;
        open my $filehandleHtml, '>', $filename . '.html' or die $!;

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

        #Say the current filename just for a progress indicator
        say $filename;

        #Read each line, one at a time, of all files specified on command line or stdin
        while ( my $line = <$filehandle> ) {

            chomp $line;

            #Remove linefeeds
            $line =~ s/\R//g;

            #Match it against our hash of pointers regexes
            foreach my $pointerType ( sort keys %pointers ) {
                foreach my $pointerKey2 ( keys $pointers{"$pointerType"} ) {
                    if ( $line =~ $pointers{"$pointerType"}{"$pointerKey2"} )
                    {
                        #Save what we captures
                        my $unique_id = $+{unique_id};
                        my $points_to = $+{points_to};

                        #Save what we found for debugging
                        $foundPointers{"$line"} = $points_to;

                        #Construct the text of the link
                        my $linkText
                            = '<a href="#'
                            . $pointerType . '_'
                            . $points_to
                            . "\">$points_to</a>";

                        #Insert the link back into the line
                        #Link point needs to be surrounded by whitespace or end of line
                        $line =~ s/(\s+) $points_to (\s+|$)/$1$linkText$2/x;

                    }
                }
            }

            #Match it against our hash of pointees regexes
            foreach my $pointeeType ( sort keys %pointees ) {
                foreach my $pointeeKey2 ( keys $pointees{"$pointeeType"} ) {
                    if ( $line =~ $pointees{"$pointeeType"}{"$pointeeKey2"} )
                    {
                        my $unique_id  = $+{unique_id};
                        my $pointed_at = $+{pointed_at};

                        #Save what we found for debugging
                        $foundPointees{$unique_id} = $pointed_at;

                        #Have we seen this pointee already?
                        #We only want to make a link pointer for the first occurrence
                        if ( !$pointeeSeen{$pointeeType}{$unique_id} ) {
                            $pointeeSeen{$pointeeType}{$unique_id} = 1;

                            #Add a break <br> to make this stand out from text above it
                            #Add underline/italic to hold destination line
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
                            $line =~ s/$number/$number_formatted/;
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
    say "";
    exit 1;
}

