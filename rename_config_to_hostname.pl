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
use Config;
use File::Basename;

#Use a local lib directory so users don't need to install modules
use lib "$FindBin::Bin/local/lib/perl5";

#Additional modules
use Modern::Perl '2014';
use Params::Validate qw(:all);
use Regexp::Common;

#Smart_Comments=1 perl my_script.pl to show smart comments
use Smart::Comments -ENV;

#Everything in this directory
# my @files = <@ARGV>;
if ( !@ARGV ) {
    say "$0 <files to rename>";
}

#Save original ARGV
my @ARGV_unmodified;

#Expand wildcards on command line since windows doesn't do it for us
if ( $Config{archname} =~ m/win/ix ) {
    use File::Glob ':bsd_glob';

    #Expand wildcards on command line
    say "Expanding wildcards for Windows";
    @ARGV_unmodified = @ARGV;
    @ARGV            = map { bsd_glob $_ } @ARGV;
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

    #Pull out the various filename components of the input file from the command line
    my ( $filename, $dir, $ext ) = fileparse( $file, qr/\.[^.]*/x );

    #Read in the whole file
    {
        local $/;
        open my $fh, '<', $file or die "can't open $file: $!";
        $file_text = <$fh>;
        close $fh;
    }

    #Try to find a hostname
    my ($hostname_in_file) = $file_text =~ m/$hostname_regex/ixsm;

    #Did we find a hostname?
    if ($hostname_in_file) {

        #Lowercase it
        $hostname_in_file = lc $hostname_in_file;

        #Sanitize it
        $hostname_in_file =~ s/[ \W ]/_/ixg;

        #Add on cfg extension
        $hostname_in_file .= '.cfg';

    }
    else {
        #Make a sanitized version of the current file's name
        #Replace non-word characters with underscore
        $filename =~ s/[ \W ]/_/ixg;

        #         $ext =~ s/[ \W ]/_/ixg;

        my $sanitized_name = $filename . $ext;

        #Set new name to sanitized version of existing file name

        $hostname_in_file //= lc $sanitized_name;
    }

    my $name = $hostname_in_file;

    #What did it match
    #say "Matched: $hostname_in_file";

    #What are we doing
    say "$file -> $dir$name";

    #Do it
    move( $file, $dir . $name ) or die(qq{failed to move $file -> $dir$name});
}
