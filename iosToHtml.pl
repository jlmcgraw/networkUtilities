#!/usr/bin/perl
# Copyright (C) 2015  Jesse McGraw (jlmcgraw@gmail.com)
#
#Parse Riverbed Interceptor configuration

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

#DONE

use Modern::Perl '2014';
use autodie;
use Regexp::Common;
use Smart::Comments;

#use Number::Bytes::Human qw(format_bytes);
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

use Params::Validate qw(:all);
use Getopt::Std;
use vars qw/ %opt /;
use Spreadsheet::WriteExcel;

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
    my $valid_cisco_name      = qr/ [\S]+ /isxm;
    my $validPointeeNameRegex = qr/ [\S]+ /isxm;
    my %data;
    my %pointers = (

        #named capture "points_to" is the pointer to the pointee
        'uses_acl' => {
            1 =>
                qr /^ \s* match \s+ access-group \s+ name \s+ (?<points_to> $validPointeeNameRegex)/ixsm,
            2 =>
                qr /^ \s* snmp-server \s+ community \s+ (?: $valid_cisco_name) \s+ view \s+ (?: $valid_cisco_name) \s+ (?: RO|RW) \s+ (?<points_to> $validPointeeNameRegex)ixsm/,
            3 =>
                qr /^ \s* snmp-server \s+ community \s+ (?: $valid_cisco_name) \s+ (?: RO|RW) \s+ (?<points_to> $validPointeeNameRegex)/ixsm,
            4 =>
                qr /^ \s* snmp-server \s+ file-transfer \s+ access-group \s+ (?<points_to> $validPointeeNameRegex) \s+ protocol/ixsm,
            5 =>
                qr /^ \s* access-class \s+ (?<points_to> $validPointeeNameRegex) \s+ (?: in|out)/ixsm,
        },
        'uses_service_policy' => {
            \1 =>
                qr/^ \s* service-policy \s+ (?: input|output) \s+ (?<points_to> $validPointeeNameRegex)/ixsm,
        },
        'uses_route_map' => {
            1 =>
                qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ route-map \s+ (?<points_to> $valid_cisco_name)/ixsm,
        },

    );

    my %pointees = (
        'is_an_acl' => {

            #Named capture "unique_id" is the beginning of the pointed to thingy
            #Named capture "pointed_at" is what to match with %pointers hash
            1 => qr/(?<unique_id> 
                                ^ \s* 
                                ip \s+ 
                                access-list \s+ 
                                extended \s+ 
                                (?<pointed_at> 
                                    (?: $valid_cisco_name)
                                ) 
                    )
                    /ixsm,
            2 =>
                qr/(?<unique_id> ^ \s* access-list \s+ (?<pointed_at> (?: $valid_cisco_name) ) )/ixsm,
        },
        'is_an_service_policy' => {
            1 =>
                qr/ (?<unique_id> ^ \s* policy-map \s+ (?<pointed_at> (?: $valid_cisco_name) ) )/ixsm
        },
        'is_a_route_map' => {
            1 =>
                qr/ (?<unique_id> ^ \s* route-map \s+ (?<pointed_at> (?: $valid_cisco_name) ) )/ixsm
        },

    );

    my %foundPointers = ();
    my %foundPointees = ();

    foreach my $filename (@ARGV) {
        open my $filehandle,     '<', $filename           or die $!;
        open my $filehandleHtml, '>', $filename . '.html' or die $!;

        print $filehandleHtml <<"END";
<html>
  <head>
    <title> 
      $filename
   </title>
  </head>

  <body>
END
        say $filename;

        #Read each line, one at a time, of all files specified on command line or stdin
        while ( my $line = <$filehandle> ) {

            chomp $line;

            #Remove linefeeds
            $line =~ s/\R//g;

            #Match it against our hash of pointers regexes
            foreach my $pointerKey1 ( keys %pointers ) {
                foreach my $pointerKey2 ( keys $pointers{"$pointerKey1"} ) {
                    if ( $line =~ $pointers{"$pointerKey1"}{"$pointerKey2"} )
                    {
                        $foundPointers{"$line"} = $+{points_to};

                        #<a name="top"></a>
                        say {$filehandleHtml} $line;

                    }
                }
            }

            #Match it against our hash of pointees regexes
            foreach my $pointeeKey1 ( keys %pointees ) {
                foreach my $pointeeKey2 ( keys $pointees{"$pointeeKey1"} ) {
                    if ( $line =~ $pointees{"$pointeeKey1"}{"$pointeeKey2"} )
                    {
                        $foundPointees{"$+{unique_id}"} = $+{pointed_at};

                        # <a href="#top">link to top</a>
                        say {$filehandleHtml} $line;

                    }
                }
            }
        }
        print $filehandleHtml <<"END";
  </body>
</html>
END
        close $filehandle;
        close $filehandleHtml;

        ### %foundPointers
        ### %foundPointees

    }

    return (0);

}

sub usage {
    say "";
    say "Usage:";
    say "   $0 <config file1> <config file2> or redirect from stdin";
    say "";
    exit 1;
}

