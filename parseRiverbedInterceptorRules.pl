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

    my %data;
    my %inpath_rule;
    my %load_balance_rule;
    my %inpath_hardware_assist_rule;

    #An octet
    my $octetRegex = qr/(?:25[0-5]|2[0-4]\d|[01]?\d\d?)/mx;

    #An IP address is made of octets
    my $ipv4AddressRegex = qr/$octetRegex\.
			      $octetRegex\.
			      $octetRegex\.
			      $octetRegex/mx;

    my $ipv4AddressWithCidrRegex = qr/
                            $octetRegex\.
			    $octetRegex\.
			    $octetRegex\.
			    $octetRegex
			    \/\d+
			    /mx;

    my $ipAddressListRegex = qr/ (?: (?:$ipv4AddressRegex [,]?)+ | any )  /mx;

    #     say
    #       "Rule Type \t Local Steelhead inpath IP \t Remote Steelhead inpath IP(s) \t Source subnet \t Destination subnet \t Dest. port \t Description \t vlan \t fair-peering \t fillup \t Rule number";

    #Read each line, one at a time, of all files specified on command line or stdin
    while (<>) {
        my $line = $_;
        chomp $line;

        my @ruleElements;
        my @hardwareAssistRuleElements;
        my @inpathRuleElements;

        state $section;
        
        given ($line) {
            when (/^
                    \#\# \s+ (?<section>[\w \s]+)
                    /ismx) {
                $section = $+{section};
                ### section: $section
            }
            when (
                /^ \s*
                    load \s+ balance \s+ rule \s+ redirect \s+
                    addrs \s+ " (?<local_steelhead_inpath_ip>  $ipAddressListRegex ) " \s+
                    peer  \s+ " (?<remote_steelhead_inpath_ip> $ipAddressListRegex ) " \s+
                    src \s+ (?<source_subnet>       (?:all | $ipv4AddressWithCidrRegex) ) \s+
                    dest \s+ (?<destination_subnet> (?:all | $ipv4AddressWithCidrRegex) ) \s+
                    dest-port \s+ " (?<destination_port> (?: all | [\w \d \- ]+ ) ) " \s+
                    description \s+ " (?<description> .*? ) " \s+
                    vlan \s+ (?<vlan> -1 ) \s+
                    fair-peering \s+ (?<fair_peering> no ) \s+
                    enforce-fillup \s+ (?<enforce_fillup> no ) \s+
                    rulenum \s+ (?<rulenum> (?:start | \d+ ) )
                    /ismx
              )
            {
                ### Matched: $line
                ### Found redirection rule
                my $action                     = 'redirect';
                my $local_steelhead_inpath_ip  = $+{local_steelhead_inpath_ip};
                my $remote_steelhead_inpath_ip = $+{remote_steelhead_inpath_ip};
                my $source_subnet              = $+{source_subnet};
                my $destination_subnet         = $+{destination_subnet};
                my $destination_port           = $+{destination_port};
                my $description                = $+{description};
                my $vlan                       = $+{vlan};
                my $fair_peering               = $+{fair_peering};
                my $enforce_fillup             = $+{enforce_fillup};
                my $rulenum                    = $+{rulenum};

                ### $action:                      $action
                ### $local_steelhead_inpath_ip:   $local_steelhead_inpath_ip
                ### $remote_steelhead_inpath_ip:  $remote_steelhead_inpath_ip
                ### $source_subnet:               $source_subnet
                ### $destination_subnet:          $destination_subnet
                ### $destination_port:            $destination_port
                ### $description:                 $description
                ### $vlan:                        $vlan
                ### $fair_peering:                $fair_peering
                ### $enforce_fillup:              $enforce_fillup
                ### $rulenum:                     $rulenum

                $load_balance_rule{$rulenum}{action} = $action;
                $load_balance_rule{$rulenum}{local_steelhead_inpath_ip} =
                  $+{local_steelhead_inpath_ip};
                $load_balance_rule{$rulenum}{remote_steelhead_inpath_ip} =
                  $+{remote_steelhead_inpath_ip};
                $load_balance_rule{$rulenum}{source_subnet} = $+{source_subnet};
                $load_balance_rule{$rulenum}{destination_subnet} =
                  $+{destination_subnet};
                $load_balance_rule{$rulenum}{destination_port} =
                  $+{destination_port};
                $load_balance_rule{$rulenum}{description}  = $+{description};
                $load_balance_rule{$rulenum}{vlan}         = $+{vlan};
                $load_balance_rule{$rulenum}{fair_peering} = $+{fair_peering};
                $load_balance_rule{$rulenum}{enforce_fillup} =
                  $+{enforce_fillup};
                $load_balance_rule{$rulenum}{rulenum} = $+{rulenum};

            }
            when (
                /^ \s*
                    load \s+ balance \s+ rule \s+ pass \s+
                    peer  \s+ " (?<remote_steelhead_inpath_ip> $ipAddressListRegex ) " \s+
                    src \s+ (?<source_subnet>       (?:all | $ipv4AddressWithCidrRegex) ) \s+
                    dest \s+ (?<destination_subnet> (?:all | $ipv4AddressWithCidrRegex) ) \s+
                    dest-port \s+ " (?<destination_port> (?: all | \d+ ) ) " \s+
                    description \s+ " (?<description> .*? ) " \s+
                    vlan \s+ (?<vlan> -1 ) \s+
                    rulenum \s+ (?<rulenum> (?:start | \d+ ) )
                    /ismx
              )
            {

                ### Matched: $line
                ### Found passthrough rule
                my $action                     = 'pass';
                my $local_steelhead_inpath_ip  = $+{local_steelhead_inpath_ip};
                my $remote_steelhead_inpath_ip = $+{remote_steelhead_inpath_ip};
                my $source_subnet              = $+{source_subnet};
                my $destination_subnet         = $+{destination_subnet};
                my $destination_port           = $+{destination_port};
                my $description                = $+{description};
                my $vlan                       = $+{vlan};
                my $fair_peering               = $+{fair_peering};
                my $enforce_fillup             = $+{enforce_fillup};
                my $rulenum                    = $+{rulenum};

                ### $action:                      $action
                ### $local_steelhead_inpath_ip:   $local_steelhead_inpath_ip
                ### $remote_steelhead_inpath_ip:  $remote_steelhead_inpath_ip
                ### $source_subnet:               $source_subnet
                ### $destination_subnet:          $destination_subnet
                ### $destination_port:            $destination_port
                ### $description:                 $description
                ### $vlan:                        $vlan
                ### $fair_peering:                $fair_peering
                ### $enforce_fillup:              $enforce_fillup
                ### $rulenum:                     $rulenum

                $load_balance_rule{$rulenum}{action} = $action;
                $load_balance_rule{$rulenum}{local_steelhead_inpath_ip} =
                  $+{local_steelhead_inpath_ip};
                $load_balance_rule{$rulenum}{remote_steelhead_inpath_ip} =
                  $+{remote_steelhead_inpath_ip};
                $load_balance_rule{$rulenum}{source_subnet} = $+{source_subnet};
                $load_balance_rule{$rulenum}{destination_subnet} =
                  $+{destination_subnet};
                $load_balance_rule{$rulenum}{destination_port} =
                  $+{destination_port};
                $load_balance_rule{$rulenum}{description}  = $+{description};
                $load_balance_rule{$rulenum}{vlan}         = $+{vlan};
                $load_balance_rule{$rulenum}{fair_peering} = $+{fair_peering};
                $load_balance_rule{$rulenum}{enforce_fillup} =
                  $+{enforce_fillup};
                $load_balance_rule{$rulenum}{rulenum} = $+{rulenum};

            }
            when (
                /^ \s*
                    in-path \s+ rule \s+
                    " (?<action> pass-through|redirect|discard|deny) " \s+
                    src \s+ (?<source_subnet>       (?:all | $ipv4AddressWithCidrRegex) ) \s+
                    dest \s+ (?<destination_subnet> (?:all | $ipv4AddressWithCidrRegex) ) \s+
                    dest-port \s+ " (?<destination_port> (?: all | [\w \d \- ]+ ) ) " \s+
                    vlan \s+ (?<vlan> -1 ) \s+
                    description \s+ " (?<description> .*? ) " \s+
                    rulenum \s+ (?<rulenum> (?:start | \d+ ) )
                    /ismx
              )
            {
                ### Found inpath rule
                ### Matched: $line
                my $action                     = $+{action};
                my $local_steelhead_inpath_ip  = $+{local_steelhead_inpath_ip};
                my $remote_steelhead_inpath_ip = $+{remote_steelhead_inpath_ip};
                my $source_subnet              = $+{source_subnet};
                my $destination_subnet         = $+{destination_subnet};
                my $destination_port           = $+{destination_port};
                my $description                = $+{description};
                my $vlan                       = $+{vlan};
                my $fair_peering               = $+{fair_peering};
                my $enforce_fillup             = $+{enforce_fillup};
                my $rulenum                    = $+{rulenum};

                ### $action:                      $action
                ### $local_steelhead_inpath_ip:   $local_steelhead_inpath_ip
                ### $remote_steelhead_inpath_ip:  $remote_steelhead_inpath_ip
                ### $source_subnet:               $source_subnet
                ### $destination_subnet:          $destination_subnet
                ### $destination_port:            $destination_port
                ### $description:                 $description
                ### $vlan:                        $vlan
                ### $fair_peering:                $fair_peering
                ### $enforce_fillup:              $enforce_fillup
                ### $rulenum:                     $rulenum

                $inpath_rule{$rulenum}{action} = $action;
                $inpath_rule{$rulenum}{local_steelhead_inpath_ip} =
                  $+{local_steelhead_inpath_ip};
                $inpath_rule{$rulenum}{remote_steelhead_inpath_ip} =
                  $+{remote_steelhead_inpath_ip};
                $inpath_rule{$rulenum}{source_subnet} = $+{source_subnet};
                $inpath_rule{$rulenum}{destination_subnet} =
                  $+{destination_subnet};
                $inpath_rule{$rulenum}{destination_port} = $+{destination_port};
                $inpath_rule{$rulenum}{description}      = $+{description};
                $inpath_rule{$rulenum}{vlan}             = $+{vlan};
                $inpath_rule{$rulenum}{rulenum}          = $+{rulenum};

            }
            when (
                /^ \s*
                    in-path \s+ hw-assist \s+ rule \s+
                    " (?<action> pass-through|accept) " \s+
                    subnet-a \s+ (?<subnet_a>       (?:all | $ipv4AddressWithCidrRegex) ) \s+
                    subnet-b \s+ (?<subnet_b>       (?:all | $ipv4AddressWithCidrRegex) ) \s+
                    description \s+ " (?<description> .*? ) " \s+
                    vlan \s+ (?<vlan> (?:all) ) \s+
                    rulenum \s+ (?<rulenum> (?:start | \d+ ) )
                    /ismx
              )
            {
                my $action      = $+{action};
                my $subnet_a    = $+{subnet_a};
                my $subnet_b    = $+{subnet_b};
                my $description = $+{description};
                my $vlan        = $+{vlan};
                my $rulenum     = $+{rulenum};

                ### $action:                      $action
                ### $subnet_a:                    $subnet_a
                ### $subnet_b:                    $subnet_b
                ### $description:                 $description
                ### $vlan:                        $vlan
                ### $rulenum:                     $rulenum

                $inpath_hardware_assist_rule{$rulenum}{action}   = $action;
                $inpath_hardware_assist_rule{$rulenum}{subnet_a} = $+{subnet_a};
                $inpath_hardware_assist_rule{$rulenum}{subnet_b} = $+{subnet_b};
                $inpath_hardware_assist_rule{$rulenum}{description} =
                  $+{description};
                $inpath_hardware_assist_rule{$rulenum}{vlan}    = $+{vlan};
                $inpath_hardware_assist_rule{$rulenum}{rulenum} = $+{rulenum};

            }

            default {
                say "Didn't match: $line"
                  if $line =~
                  /^ \s* (?:in-path \s+ rule | load \s+ balance | in-path \s+ hw-assist) \s+ /x;
            }

        }

    }

    # Create a new Excel workbook
    my $workbook =
      Spreadsheet::WriteExcel->new('Riverbed_interceptor_rules.xls');

    # Add worksheets
    my $worksheet_load_balance_rule =
      $workbook->add_worksheet('load_balance_rule');
    my $worksheet_inpath_rule = $workbook->add_worksheet('inpath_rule');
    my $worksheet_inpath_hardware_assist_rule =
      $workbook->add_worksheet('inpath_hardware_assist_rule');

    foreach my $key ( sort keys %load_balance_rule ) {
        my $row;
        if   ( $key =~ m/start/i ) { $row = 1 }
        else                       { $row = $key }

        $worksheet_load_balance_rule->write( $row, 0,
            $load_balance_rule{$key}{action} );
        $worksheet_load_balance_rule->write( $row, 1,
            $load_balance_rule{$key}{local_steelhead_inpath_ip} );
        $worksheet_load_balance_rule->write( $row, 2,
            $load_balance_rule{$key}{remote_steelhead_inpath_ip} );
        $worksheet_load_balance_rule->write( $row, 3,
            $load_balance_rule{$key}{source_subnet} );
        $worksheet_load_balance_rule->write( $row, 4,
            $load_balance_rule{$key}{destination_subnet} );
        $worksheet_load_balance_rule->write( $row, 5,
            $load_balance_rule{$key}{destination_port} );
        $worksheet_load_balance_rule->write( $row, 6,
            $load_balance_rule{$key}{description} );
        $worksheet_load_balance_rule->write( $row, 7,
            $load_balance_rule{$key}{vlan} );
        $worksheet_load_balance_rule->write( $row, 8,
            $load_balance_rule{$key}{fair_peering} );
        $worksheet_load_balance_rule->write( $row, 9,
            $load_balance_rule{$key}{enforce_fillup} );
        $worksheet_load_balance_rule->write( $row, 10,
            $load_balance_rule{$key}{action} );
        $worksheet_load_balance_rule->write( $row, 11,
            $load_balance_rule{$key}{rulenum} );
        $row++;
    }

    foreach my $key ( keys %inpath_rule ) {
        my $row;
        if   ( $key =~ m/start/i ) { $row = 1 }
        else                       { $row = $key }

        $worksheet_inpath_rule->write( $row, 0, $inpath_rule{$key}{action} );
        $worksheet_inpath_rule->write( $row, 1,
            $inpath_rule{$key}{local_steelhead_inpath_ip} );
        $worksheet_inpath_rule->write( $row, 2,
            $inpath_rule{$key}{remote_steelhead_inpath_ip} );
        $worksheet_inpath_rule->write( $row, 3,
            $inpath_rule{$key}{source_subnet} );
        $worksheet_inpath_rule->write( $row, 4,
            $inpath_rule{$key}{destination_subnet} );
        $worksheet_inpath_rule->write( $row, 5,
            $inpath_rule{$key}{destination_port} );
        $worksheet_inpath_rule->write( $row, 6,
            $inpath_rule{$key}{description} );
        $worksheet_inpath_rule->write( $row, 7, $inpath_rule{$key}{vlan} );
        $worksheet_inpath_rule->write( $row, 8, $inpath_rule{$key}{rulenum} );

    }
    foreach my $key ( keys %inpath_hardware_assist_rule ) {
        my $row;
        if   ( $key =~ m/start/i ) { $row = 1 }
        else                       { $row = $key }
        $worksheet_inpath_hardware_assist_rule->write( $row, 0,
            $inpath_hardware_assist_rule{$key}{action} );
        $worksheet_inpath_hardware_assist_rule->write( $row, 1,
            $inpath_hardware_assist_rule{$key}{subnet_a} );
        $worksheet_inpath_hardware_assist_rule->write( $row, 2,
            $inpath_hardware_assist_rule{$key}{subnet_b} );
        $worksheet_inpath_hardware_assist_rule->write( $row, 3,
            $inpath_hardware_assist_rule{$key}{description} );
        $worksheet_inpath_hardware_assist_rule->write( $row, 4,
            $inpath_hardware_assist_rule{$key}{vlan} );
        $worksheet_inpath_hardware_assist_rule->write( $row, 5,
            $inpath_hardware_assist_rule{$key}{rulenum} );

    }

    # #     #Dump the hash
    #     print Dumper \%load_balance_rule;
    #     print Dumper \%inpath_rule;
    #     print Dumper \%inpath_hardware_assist_rule;

    return (0);

}

sub usage {
    say "";
    say "Usage:";
    say "   $0 <config file1> <config file2> or redirect from stdin";
    say "";
    exit 1;
}

