#!/usr/bin/perl
# Copyright (C) 2015  Jesse McGraw (jlmcgraw@gmail.com)
#
#Parse the output of "show mls qos interface statistics" from a Cisco Catalyst
# 3560/3750 switch
#Combine the counts of all of the interfaces to get an idea of the overall
# mix of incoming/outgoing COS/DSCP values and which queues are queuing and dropping
# the most packets

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
# Give some thought to how to ignore certain interfaces (eg uplinks to other
# switches)
# Print numbers human-style
# More gracefully handle the variable counts of data in COS/DSCP listings

#DONE
# Allow user to select the sorting

use Modern::Perl '2014';
use autodie;
use Number::Bytes::Human qw(format_bytes);
use Data::Dumper;
use Getopt::Std;
use vars qw/ %opt /;

#Use this to not print warnings
no if $] >= 5.018, warnings => "experimental";

#Define the valid command line options
my $opt_string = 's';
my $arg_num    = scalar @ARGV;

#This will fail if we receive an invalid option
unless ( getopts( "$opt_string", \%opt ) ) {
    usage();
    exit(1);
}

#Call main routine
exit main(@ARGV);

sub main {

    my %data;

    #A count of how many interfaces we've processed
    my $interfaceCount;

    #Determine how user wants to sort the display
    determineDesiredSorting();

    #Read each line, one at a time, of all files specified on command line or stdin
    while (<>) {
        my $line = $_;

        #Don't reinitialize these variables each time through the loop
        state(
            $currentInterface, $markingType, $markingDirection,
            $queueType,        $queueAction
        );

        #         say $line;
        given ($line) {
            when (/(dscp|cos) \s* : \s* (incoming|outgoing)/ix) {

                #Save the type of mark and its direction
                $markingType      = $1;
                $markingDirection = $2;

                #                 say "\tFound: $markingType $markingDirection";
            }

            when (/(output \s+ queues) \s* (enqueued|dropped)/ix) {

                #Save whether we're queuing or dropping
                $queueType   = $1;
                $queueAction = $2;

                #                 say "\tFound: $queueType with action $queueAction";
            }

            #The DSCP/COS lines with 5 entries
            when (
                /^ \s+
                     (?<lower>\d+) \s+
                     \-
                     \s+
                     (?<upper>\d+) \s+ 
                     \: 
                     \s+ (?<first>\d+)
                     \s+ (?<second>\d+) 
                     \s+ (?<third>\d+) 
                     \s+ (?<fourth>\d+) 
                     \s+ (?<fifth>\d+)
                     \s*
                     $/ix
              )
            {
                #                 say "\t$markingType with 5 entries!";
                #                 say "\t\t"
                #                   . $+{lower} . "/"
                #                   . $+{upper} . ":"
                #                   . $+{first} . ":"
                #                   . $+{second} . ":"
                #                   . $+{third} . ":"
                #                   . $+{fourth} . ":"
                #                   . $+{fifth};
                #Get the lower and upper bounds of the COS/DSCP for this line
                my $lower = $+{lower};
                my $upper = $+{upper};

                #Calculate the COS/DSCP represented by the columns of data
                my $first  = $+{lower};
                my $second = $+{lower} + 1;
                my $third  = $+{lower} + 2;
                my $fourth = $+{lower} + 3;
                my $fifth  = $+{lower} + 4;

                #Save it into the hash
                $data{ $markingType . ":" . $markingDirection }{$first} +=
                  $+{first};
                $data{ $markingType . ":" . $markingDirection }{$second} +=
                  $+{second};
                $data{ $markingType . ":" . $markingDirection }{$third} +=
                  $+{third};
                $data{ $markingType . ":" . $markingDirection }{$fourth} +=
                  $+{fourth};
                $data{ $markingType . ":" . $markingDirection }{$fifth} +=
                  $+{fifth};
            }

            #The DSCP/COS lines with 4 entries
            when (
                /^ \s+
                     (?<lower>\d+) \s+
                     \-
                     \s+
                     (?<upper>\d+) \s+ 
                     \: 
                     \s+ (?<first>\d+)
                     \s+ (?<second>\d+) 
                     \s+ (?<third>\d+) 
                     \s+ (?<fourth>\d+) 
                     \s*
                     $/ix
              )
            {
                #                 say "\t$markingType with 3 entries!";
                #                 say "\t\t"
                #                   . $+{lower} . "/"
                #                   . $+{upper} . ":"
                #                   . $+{first} . ":"
                #                   . $+{second} . ":"
                #                   . $+{third};
                #Get the lower and upper bounds of the COS/DSCP for this line
                my $lower = $+{lower};
                my $upper = $+{upper};

                #Calculate the COS/DSCP represented by the columns of data
                my $first  = $+{lower};
                my $second = $+{lower} + 1;
                my $third  = $+{lower} + 2;
                my $fourth = $+{lower} + 3;

                #Save it into the hash
                $data{ $markingType . ":" . $markingDirection }{$first} +=
                  $+{first};
                $data{ $markingType . ":" . $markingDirection }{$second} +=
                  $+{second};
                $data{ $markingType . ":" . $markingDirection }{$third} +=
                  $+{third};
                $data{ $markingType . ":" . $markingDirection }{$fourth} +=
                  $+{fourth};

            }

            #The DSCP/COS lines with 3 entries
            when (
                /^ \s+
                     (?<lower>\d+) \s+
                     \-
                     \s+
                     (?<upper>\d+) \s+ 
                     \: 
                     \s+ (?<first>\d+)
                     \s+ (?<second>\d+) 
                     \s+ (?<third>\d+) 
                     \s*
                     $/ix
              )
            {
                #                 say "\t$markingType with 3 entries!";
                #                 say "\t\t"
                #                   . $+{lower} . "/"
                #                   . $+{upper} . ":"
                #                   . $+{first} . ":"
                #                   . $+{second} . ":"
                #                   . $+{third};
                #Get the lower and upper bounds of the COS/DSCP for this line
                my $lower = $+{lower};
                my $upper = $+{upper};

                #Calculate the COS/DSCP represented by the columns of data
                my $first  = $+{lower};
                my $second = $+{lower} + 1;
                my $third  = $+{lower} + 2;

                #Save into the hash
                $data{ $markingType . ":" . $markingDirection }{$first} +=
                  $+{first};
                $data{ $markingType . ":" . $markingDirection }{$second} +=
                  $+{second};
                $data{ $markingType . ":" . $markingDirection }{$third} +=
                  $+{third};

            }

            #Queue entries
            when (
                /^ \s+
                    queue
                    \s+
                     (?<queueNumber>\d+)
                     : 
                     \s+ (?<threshold1>\d+)
                     \s+ (?<threshold2>\d+) 
                     \s+ (?<threshold3>\d+) 
                     \s*
                     $/ix
              )
            {
                #                 say "\t$queueType with action $queueAction with 3 entries!";
                #                 say "\t\t"
                #                   . $+{queueNumber} . ":"
                #                   . $+{threshold1} . ":"
                #                   . $+{threshold2} . ":"
                #                   . $+{threshold3};
                #The queue number
                #For whatever dumb reason, this output starts queue numbering at 0
                #where the config starts at 1.  So +1 here to make them consistent
                my $queueNumber = $+{queueNumber} + 1;

                #The thresholds for that queue
                my $threshold1 = $+{threshold1};
                my $threshold2 = $+{threshold2};
                my $threshold3 = $+{threshold3};

                $data{ $queueType . ":" . $queueAction }{$queueNumber}
                  {"threshold1"} += $threshold1;
                $data{ $queueType . ":" . $queueAction }{$queueNumber}
                  {"threshold2"} += $threshold2;
                $data{ $queueType . ":" . $queueAction }{$queueNumber}
                  {"threshold3"} += $threshold3;

            }
            when (/FastEthernet|GigabitEthernet/ix) {
                $interfaceCount++;

                #Add in other types of interfaces here
                #eg 10Mb, 10Gig, etc etc etc
                #Clear information for every new interface
                #                 say "Clearing data!";
                $currentInterface = $markingType = $markingDirection =
                  $queueType      = $queueAction = undef;
            }

            default {
                #Save the Unrecognized line in the hash for user review
                $data{"Unrecognized Lines"}{$line} = 1;
            }
        }

    }

    #Dump the hash
    print Dumper \%data;

    say "Processed $interfaceCount interfaces";
    return (0);

}

sub usage {
    say "";
    say "Usage:";
    say "   $0 [-s] <log file1> <log file2> etc";
    say "       -s     Sort by count values instead of keys";
    say "";
    exit 1;
}

sub determineDesiredSorting {

    #How does the user want to sort the display?
    if ( $opt{s} ) {

        #Provide a routine for Data::dumper to sort by hash values
        $Data::Dumper::Sortkeys = sub {
            my $data = join '', values %{ $_[0] };

            #Sort numerically
            return [ sort { $_[0]->{$b} <=> $_[0]->{$a} } keys %{ $_[0] } ];

        };
    }
    else {
        #Provide a routine for Data::dumper to sort by hash keys
        $Data::Dumper::Sortkeys = sub {
            my $data = join '', keys %{ $_[0] };

            if ( $data =~ /[A-Za-z]/ ) {    # for example
                    #Input is not numeric so sort Asciibetically
                return [ sort keys %{ $_[0] } ];
            }
            else {
                #Sort numerically
                return [ sort { $a <=> $b } keys %{ $_[0] } ];
            }
        };
    }
}
