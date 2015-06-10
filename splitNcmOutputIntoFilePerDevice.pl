#!/usr/bin/perl

#Split output from NCM into one file for each device
#Valid input is only text from Solarwinds Network Configuration Manager job output

use Modern::Perl '2014';
use autodie;

# use NetAddr::IP;
# use File::Slurp;
# use Getopt::Std;
# use vars qw/ %opt /;
# use Params::Validate qw(:all);
# use Data::Dumper;
# $Data::Dumper::Indent   = 2;
# $Data::Dumper::Sortkeys = 1;
# $Data::Dumper::Purity   = 1;

# #don't buffer stdout
# $| = 1;

exit main(@ARGV);

sub main {

    #Check that we're redirecting stdin from a file
    if (-t) {
        say "You must redirect input from a valid NCM output file";
        say "Usage: $0 < fileWithOutputFromNcm";
        exit 1;
    }
    
    #Check that the first line looks like it's from NCM
    my $firstLine = <>;
    die "Not a valid Solarwinds NCM output file"
      unless ( $firstLine =~ /SolarWinds Network Configuration Manager/ );
      
    my $hostName;
    my $ipAddress;
    my $fileName;
    my $fileHandle;

    my $ipOctetRegex = qr/(?:25[0-5]|2[0-4]\d|[01]?\d\d?)/x;

    my $ipv4AddressRegex = qr/$ipOctetRegex\.
			      $ipOctetRegex\.
			      $ipOctetRegex\.
			      $ipOctetRegex/mx;

    #read from STDIN
    while (<>) {

        #Find the current hostname
        if (
            $_ =~ /
            ^ 
            \s+
            (?<hostName>.*?)
            \s+
            \(
            (?<ipAddress>$ipv4AddressRegex)
            \)\:
            \s*
            $
            /ix
          )
        {
            $hostName  = $+{hostName};
            $ipAddress = $+{ipAddress};
            $fileName  = "$hostName - $ipAddress.txt";

            #             say $fileName;
            open $fileHandle, '>', $fileName or croak $!;
        }

        #Clear variables between devices
        elsif ( $_ =~ /(______________)/ix ) {

            #Close the current file
            if ($fileHandle) { close($fileHandle); }

            #             say "Clearing!";
            $hostName = $ipAddress = $fileName = $fileHandle = undef;

        }
        else {
            #Any lines that don't match fall through to here
            #If we have an open fileHandle print the line to it

            if ($fileHandle) {

                #              say $_;
                $_ =~ s/\R//x;
                say $fileHandle $_;
            }
            else { say $_; }
        }

    }
    return 0;
}
