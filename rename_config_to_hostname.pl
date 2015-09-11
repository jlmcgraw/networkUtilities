#!/usr/bin/perl
# Copyright (C) 2015  Jesse McGraw (jlmcgraw@gmail.com)
#
# Rename files based on hostname
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

#Standard modules
use strict;
use warnings;
use autodie;

# use Socket;
# use Config;
# use Data::Dumper;
# use Storable;
# use threads;
# use Thread::Queue;
# use threads::shared;
# use Getopt::Std;
use FindBin '$Bin';
use vars qw/ %opt /;
use File::Copy;

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

#Use a local lib directory so users don't need to install modules
use lib "$FindBin::Bin/local/lib/perl5";

#Additional modules
use Modern::Perl '2014';
use Params::Validate qw(:all);
use Regexp::Common;

# use NetAddr::IP;
# use Net::Ping;
# use Hash::Merge qw(merge);

#Smart_Comments=1 perl my_script.pl to show smart comments
use Smart::Comments -ENV;

#Everything in this directory
# my @files = <@ARGV>;
if (!@ARGV) {
    say "$0 <files to rename>";
    }

    #Expand wildcards on command line since windows doesn't do it for us
if ( $Config{archname} =~ m/win/ix ) {

    #Expand wildcards on command line
    say "Expanding wildcards for Windows";
    @ARGV_unmodified = @ARGV;
    @ARGV = map {glob} @ARGV;
}

my $hostname_regex = qr/^
                        \s* 
                        (?: hostname | switchname ) 
                        \s+
                        "?
                        ( $RE{net}{domain} )
                        "?
                        \R
                        /ismx;

foreach my $file (@ARGV) {

    my $file_text;

    {
        local $/;
        open my $fh, '<', $file or die "can't open $file: $!";
        $file_text = <$fh>;

    }

    #     my ($name) = $file_text =~ /^ \s*
    #                             (?:hostname|switchname) \s+
    #                             ["]?
    #                             (\S+)
    #                             ["]?
    #                             /ix;
    #Try to find a hostname
    my ($name) = $file_text =~ m/$hostname_regex/ixsm;

    if ($name) {
        $name = lc $name;
    }

    #What did it match
    #     say "Matched: $name";
    #Make a sanitized version of the current file's name
    my $sanitized_name = $file;
    $sanitized_name =~ s/[ \W ]/_/ixg;

    #If we didn't match anything use the sanitized version
    $name //= lc $sanitized_name;
    $name .= '.cfg';

    #What are we doing
    say "$file -> $name";
    #Do it
    move( $file, $name ) or die(qq{failed to move $file -> $name});
}
