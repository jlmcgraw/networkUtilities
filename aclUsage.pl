#!/usr/bin/perl

#Which lines from an ACL are being hit
#Valid input is only text from Solarwinds Network Configuration Manager job output of "show IP access-lists" on Cisco IOS/Nexus devices

use Modern::Perl '2014';
use autodie;

# use NetAddr::IP;
# use File::Slurp;
# use Getopt::Std;
# use vars qw/ %opt /;
# use Params::Validate qw(:all);
use Data::Dumper;
$Data::Dumper::Indent   = 2;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Purity   = 1;

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
      
    my %acls;
    my $aclName;
    my $aclLine;
    my $aclEntry;
    my $aclEntryHitCount;

    #read from STDIN
    while (<>) {

        #Find the current ACL name/number
        if (
            $_ =~ /
            ^
                \s*
                    (?:Extended | Standard )?       #
                \s*
                    IP
                \s+
                    access
                \s+
                    list 
                \s+
                    (?<aclName>[\w\-_]+)
                \s*
            $
            /ix
          )
        {
            $aclName = $+{aclName};
        }

        #Find the current ACL name/number from Nexus
        elsif (
            $_ =~ /
            \s* 
            IPV4
            \s+ 
            ACL
            \s+ 
            (?<aclName>[\w\-_]+)
            /ix
          )
        {
            $aclName = $+{aclName};
        }

        #Sample lines from "show ip access-lists
        #       10 deny ip any host 10.71.235.80
        #       50 permit udp any host 10.255.228.1 eq 1967 dscp ef (651970 matches)
        #
        #Find ACL lines
        elsif (
            $_ =~ /
            ^                                                   #beginning of line
            \s+                                                 #some whitespace
                (?<aclLine> \d+)                                #ACL entry number
                \s+                                             #followed by whitespace
                (?<aclEntry> (?:permit | deny) .*? )            #The ACL up to the possible  "matches" portion
                (?:
                    \s+
                    \(                                          # (
                        \s*                                     # zero or more whitespace
                        (?<aclEntryHitCount> \d+ )              # the count of hits
                        \s*                                     # zero or more whitespace
                        (?:match|matches)                       # "match" or "matches"
                    \)                                          # )
                )?
                \s*                                         # zero or more whitespace
            $
            /ix
          )
        {
            $aclEntry = $+{aclEntry};
            $aclEntry =~ s/\R//;
            $aclLine          = $+{aclLine};
            $aclEntryHitCount = $+{aclEntryHitCount};

            #             say $aclEntry;
            #             say $aclEntryHitCount;

            #Add aclEntryHitCount to a hash of ACLs where "aclEntry" is a key

            #If there is a aclEntryHitCount, add it to the running total
            #otherwise just add 0
            if ($aclEntryHitCount) {
                $acls{$aclName}{$aclEntry} += $aclEntryHitCount;
            }
            else {
                $acls{$aclName}{$aclEntry} += 0;
            }

            #Uncomment if you want to see line numbers and hits per line #
            #$acls{$aclName}{$aclEntry}{"totalHits"} += $aclEntryHitCount;
            #$acls{$aclName}{$aclEntry}{"Lines"}{$aclLine} += $aclEntryHitCount;

        }

        #Clear variables between devices or commands
        elsif ( $_ =~ /(--------------|______________)/ix ) {
            $aclName = $aclLine = $aclEntry = $aclEntryHitCount = "";

        }
        else {
            #Any lines that don't match fall through to here, just so we can check that we're covering all desirable inputs
            #say $_;
        }

    }
    say Dumper \%acls;
}
