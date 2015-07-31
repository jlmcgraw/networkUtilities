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
#  instead of multiple "when"s
# output to CSV or spreadsheet

#DONE
# Allow user to select the sorting

use Modern::Perl '2014';
use autodie;

#use Number::Bytes::Human qw(format_bytes);
use Data::Dumper;
use Params::Validate qw(:all);
use Getopt::Std;
use vars qw/ %opt /;

#Use this to not print warnings
no if $] >= 5.018, warnings => "experimental";

#Define the valid command line options
my $opt_string = 'szu';
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

        given ($line) {
            when (/(dscp|cos) \s* : \s* (incoming|outgoing)/ix) {

                #Save the type of mark and its direction
                $markingType      = $1;
                $markingDirection = $2;
            }

            when (/(output \s+ queues) \s* (enqueued|dropped)/ix) {

                #Save whether we're queuing or dropping
                $queueType   = $1;
                $queueAction = $2;
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
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$first} += $+{first};
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$second} += $+{second};
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$third} += $+{third};
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$fourth} += $+{fourth};
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$fifth} += $+{fifth};
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
                #Get the lower and upper bounds of the COS/DSCP for this line
                my $lower = $+{lower};
                my $upper = $+{upper};

                #Calculate the COS/DSCP represented by the columns of data
                my $first  = $+{lower};
                my $second = $+{lower} + 1;
                my $third  = $+{lower} + 2;
                my $fourth = $+{lower} + 3;

                #Save it into the hash
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$first} += $+{first};
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$second} += $+{second};
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$third} += $+{third};
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$fourth} += $+{fourth};

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
                #Get the lower and upper bounds of the COS/DSCP for this line
                my $lower = $+{lower};
                my $upper = $+{upper};

                #Calculate the COS/DSCP represented by the columns of data
                my $first  = $+{lower};
                my $second = $+{lower} + 1;
                my $third  = $+{lower} + 2;

                #Save into the hash
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$first} += $+{first};
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$second} += $+{second};
                $data{  $markingType . ":"
                      . $markingDirection
                      . " ( Tag -> Packets )" }{$third} += $+{third};

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
                #The queue number
                #For whatever dumb reason, this output starts queue numbering at 0
                #where the configuration commands starts it at 1.  So +1 here to
                #make them consistent
                my $queueNumber = $+{queueNumber} + 1;

                #The thresholds for that queue
                my $threshold1 = $+{threshold1};
                my $threshold2 = $+{threshold2};
                my $threshold3 = $+{threshold3};

                #An alternative way to format this output
                #                 $data{ $queueType . ":" . $queueAction . " (queue - threshold)" }{$queueNumber}
                #                   {"threshold1"} += $threshold1;
                #                 $data{ $queueType . ":" . $queueAction . " (queue - threshold)" }{$queueNumber}
                #                   {"threshold2"} += $threshold2;
                #                 $data{ $queueType . ":" . $queueAction . " (queue - threshold)" }{$queueNumber}
                #                   {"threshold3"} += $threshold3;

                $data{  $queueType . ":"
                      . $queueAction
                      . " (queue - threshold)" }{ $queueNumber . "-1" } +=
                  $threshold1;
                $data{  $queueType . ":"
                      . $queueAction
                      . " (queue - threshold)" }{ $queueNumber . "-2" } +=
                  $threshold2;
                $data{  $queueType . ":"
                      . $queueAction
                      . " (queue - threshold)" }{ $queueNumber . "-3" } +=
                  $threshold3;

            }
            when (/FastEthernet|GigabitEthernet|Ethernet/ix) {

                #We've begun processing output for another interface
                $interfaceCount++;

                #TODO: Add in other types of interfaces here
                #eg 10Mb, 10Gig, etc etc etc

                #Clear information for every new interface
                $currentInterface = $markingType = $markingDirection =
                  $queueType      = $queueAction = undef;
            }

            default {
                #If requested, save the unrecognized line in the hash for user review
                if ( $opt{u} ) { $data{"Unrecognized Lines"}{$line} = 1; }
            }
        }

    }

    #Delete keys with value 0 if user requested
    if ( $opt{z} ) { deleteKeysWithValueZero( \%data ); }

    #Dump the hash
    print Dumper \%data;

    say "Processed $interfaceCount interfaces";
    return (0);

}

sub deleteKeysWithValueZero {

    #Recursively search through a hash and delete keys with value 0

    my ($collection) = validate_pos( @_, { type => HASHREF | ARRAYREF }, );

    #Is collection referencing an array?
    if ( ref $collection eq "ARRAY" ) {

        #For each item in the array, Recursively search if the item is
        #a HASHREF or an ARRAYREF
        for my $arrayValue ( @{$collection} ) {
            if ( ref($arrayValue) eq 'HASH' || ref($arrayValue) eq 'ARRAY' ) {
                deleteKeysWithValueZero($arrayValue);
            }
        }
    }

    #Is collection referencing a hash?
    elsif ( ref $collection eq "HASH" ) {

        for my $key ( keys %{$collection} ) {
            my $hashValue = $collection->{$key};

            #Recursively search if the item is a reference to hash or array
            if ( ref($hashValue) eq 'HASH' || ref($hashValue) eq 'ARRAY' ) {
                deleteKeysWithValueZero($hashValue);
            }
            else {
                #Unless the value is defined (not zero) delete it
                unless ($hashValue) {
                    delete $collection->{$key};
                }
            }
        }
    }
}

sub usage {
    say "";
    say "Usage:";
    say "   $0 [-s] <log file1> <log file2> etc";
    say "       -s     Sort by count values instead of keys";
    say "       -z     Delete keys with value of 0 to unclutter display";
    say "       -u     Save unrecognized lines for diagnosing parsing issues";
    say "";
    exit 1;
}

sub determineDesiredSorting {

    #How does the user want to sort the display?
    my $shouldSortByvalue = $opt{s};

    if ($shouldSortByvalue) {

        #Provide a routine for Data::dumper to sort by hash VALUES
        $Data::Dumper::Sortkeys = sub {

            #Get all the values for this hash
            my $values = join '', values %{ $_[0] };

            #Are they only numbers?
            if ( $values =~ /^[[:alnum:]]+$/ ) {

                #Sort by values numerically
                return [ sort { $_[0]->{$b} <=> $_[0]->{$a} } keys %{ $_[0] } ];
            }
            else {
                #Values is not all numeric so sort by keys alphabetically
                #BUG TODO Should be values?
                return [ sort { lc $a cmp lc $b } keys %{ $_[0] } ];
            }
        };
    }
    else {
        #Provide a routine for Data::dumper to sort by hash KEYS
        $Data::Dumper::Sortkeys = sub {

            #Get all the values for this hash
            my $values = join '', values %{ $_[0] };

            #Are they only numbers?
            if ( $values =~ /^[[:alnum:]]+$/ ) {

                #Sort keys numerically
                return [ sort { $a <=> $b or $a cmp $b } keys %{ $_[0] } ];
            }
            else {
                #Values is not all numeric so sort by keys alphabetically
                return [ sort { lc $a cmp lc $b } keys %{ $_[0] } ];
            }
        };
    }
}
