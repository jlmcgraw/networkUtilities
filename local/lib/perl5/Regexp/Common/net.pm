package Regexp::Common::net;

use Regexp::Common qw /pattern clean no_defaults/;

use strict;
use warnings;

use vars qw /$VERSION/;
$VERSION = '2013031301';


my %IPunit = (
    dec => q{(?k:25[0-5]|2[0-4][0-9]|[0-1]?[0-9]{1,2})},
    oct => q{(?k:[0-3]?[0-7]{1,2})},
    hex => q{(?k:[0-9a-fA-F]{1,2})},
    bin => q{(?k:[0-1]{1,8})},
);
my %MACunit = (
    %IPunit,
    hex => q{(?k:[0-9a-fA-F]{1,2})},
);

my %IPv6unit = (
    hex => q {(?k:[0-9a-f]{1,4})},
    HEX => q {(?k:[0-9A-F]{1,4})},
    HeX => q {(?k:[0-9a-fA-F]{1,4})},
);

sub dec {$_};
sub bin {oct "0b$_"}

my $IPdefsep   = '[.]';
my $MACdefsep  =  ':';
my $IPv6defsep =  ':';

pattern name   => [qw (net IPv4)],
        create => "(?k:$IPunit{dec}$IPdefsep$IPunit{dec}$IPdefsep" .
                      "$IPunit{dec}$IPdefsep$IPunit{dec})",
        ;

pattern name   => [qw (net MAC)],
        create => "(?k:" . join ($MACdefsep => ($MACunit{hex}) x 6) . ")",
        subs   => sub {
            $_ [1] = join ":" => map {sprintf "%02x" => hex}
                                 split /$MACdefsep/ => $_ [1]
                     if $_ [1] =~ /$_[0]/
        },
        ;

foreach my $type (qw /dec oct hex bin/) {
    pattern name   => [qw (net IPv4), $type, "-sep=$IPdefsep"],
            create => sub {my $sep = $_ [1] -> {-sep};
                           "(?k:$IPunit{$type}$sep$IPunit{$type}$sep" .
                               "$IPunit{$type}$sep$IPunit{$type})"
                      },
            ;

    pattern name   => [qw (net MAC), $type, "-sep=$MACdefsep"],
            create => sub {my $sep = $_ [1] -> {-sep};
                           "(?k:" . join ($sep => ($MACunit{$type}) x 6) . ")",
                      },
            subs   => sub {
                return if $] < 5.006 and $type eq 'bin';
                $_ [1] = join ":" => map {sprintf "%02x" => eval $type}
                                     $2, $3, $4, $5, $6, $7
                         if $_ [1] =~ $RE {net} {MAC} {$type}
                                          {-sep => $_ [0] -> {flags} {-sep}}
                                          {-keep};
            },
            ;

}


my %cache6;
pattern name   => [qw (net IPv6), "-sep=$IPv6defsep", "-style=HeX"],
        create => sub {
            my $style = $_ [1] {-style};
            my $sep   = $_ [1] {-sep};

            return $cache6 {$style, $sep} if $cache6 {$style, $sep};

            my @re;

            die "Impossible style '$style'\n" unless exists $IPv6unit {$style};

            #
            # Nothing missing
            #
            push @re => join $sep => ($IPv6unit {$style}) x 8;

            #
            # For "double colon" representations, at least 2 units must
            # be omitted, leaving us with at most 6 units. 0 units is also
            # possible. Note we can have at most one double colon.
            #
            for (my $l = 0; $l <= 6; $l ++) {
                #
                # We prefer to do longest match, so larger $r gets priority
                #
                for (my $r = 6 - $l; $r >= 0; $r --) {
                    #
                    # $l is the number of blocks left of the double colon,
                    # $r is the number of blocks left of the double colon,
                    # $m is the number of omitted blocks
                    #
                    my $m    = 8 - $l - $r;
                    my $patl = $l ? ($IPv6unit {$style} . $sep) x $l : $sep;
                    my $patr = $r ? ($sep . $IPv6unit {$style}) x $r : $sep;
                    my $patm = "(?k:)" x $m;
                    my $pat  = $patl . $patm . $patr;
                    push @re => "(?:$pat)";
                }
            }
            local $" = "|";
            $cache6 {$style, $sep} = qq /(?k:(?|@re))/;
        },
        version => 5.010
;


my $letter      =  "[A-Za-z]";
my $let_dig     =  "[A-Za-z0-9]";
my $let_dig_hyp = "[-A-Za-z0-9]";

# Domain names, from RFC 1035.
pattern name   => [qw (net domain -nospace= -rfc1101=)],
        create => sub {
            my $rfc1101 = exists $_ [1] {-rfc1101} &&
                        !defined $_ [1] {-rfc1101};

            my $lead = $rfc1101 ? "(?!$RE{net}{IPv4}(?:[.]|\$))$let_dig"
                                : $letter;

            if (exists $_ [1] {-nospace} && !defined $_ [1] {-nospace}) {
                return "(?k:$lead(?:(?:$let_dig_hyp){0,61}$let_dig)?" .
                       "(?:\\.$lead(?:(?:$let_dig_hyp){0,61}$let_dig)?)*)"
            }
            else {
                return "(?k: |(?:$lead(?:(?:$let_dig_hyp){0,61}$let_dig)?" .
                       "(?:\\.$lead(?:(?:$let_dig_hyp){0,61}$let_dig)?)*))"
            }
        },
        ;



1;

__END__

=head1 NAME

Regexp::Common::net -- provide regexes for IPv4 addresses.

=head1 SYNOPSIS

    use Regexp::Common qw /net/;

    while (<>) {
        /$RE{net}{IPv4}/       and print "Dotted decimal IP address";
        /$RE{net}{IPv4}{hex}/  and print "Dotted hexadecimal IP address";
        /$RE{net}{IPv4}{oct}{-sep => ':'}/ and
                               print "Colon separated octal IP address";
        /$RE{net}{IPv4}{bin}/  and print "Dotted binary IP address";
        /$RE{net}{MAC}/        and print "MAC address";
        /$RE{net}{MAC}{oct}{-sep => " "}/ and
                               print "Space separated octal MAC address";
    }

=head1 DESCRIPTION

Please consult the manual of L<Regexp::Common> for a general description
of the works of this interface.

Do not use this module directly, but load it via I<Regexp::Common>.

This modules gives you regular expressions for various style IPv4 
and MAC (or ethernet) addresses.

=head2 C<$RE{net}{IPv4}>

Returns a pattern that matches a valid IP address in "dotted decimal".
Note that while C<318.99.183.11> is not a valid IP address, it does
match C</$RE{net}{IPv4}/>, but this is because C<318.99.183.11> contains
a valid IP address, namely C<18.99.183.11>. To prevent the unwanted
matching, one needs to anchor the regexp: C</^$RE{net}{IPv4}$/>.

For this pattern and the next four, under C<-keep> (See L<Regexp::Common>):

=over 4

=item $1

captures the entire match

=item $2

captures the first component of the address

=item $3

captures the second component of the address

=item $4

captures the third component of the address

=item $5

captures the final component of the address

=back

=head2 C<$RE{net}{IPv4}{dec}{-sep}>

Returns a pattern that matches a valid IP address in "dotted decimal"

If C<< -sep=I<P> >> is specified the pattern I<P> is used as the separator.
By default I<P> is C<qr/[.]/>. 

=head2 C<$RE{net}{IPv4}{hex}{-sep}>

Returns a pattern that matches a valid IP address in "dotted hexadecimal",
with the letters C<A> to C<F> capitalized.

If C<< -sep=I<P> >> is specified the pattern I<P> is used as the separator.
By default I<P> is C<qr/[.]/>. C<< -sep="" >> and
C<< -sep=" " >> are useful alternatives.

=head2 C<$RE{net}{IPv4}{oct}{-sep}>

Returns a pattern that matches a valid IP address in "dotted octal"

If C<< -sep=I<P> >> is specified the pattern I<P> is used as the separator.
By default I<P> is C<qr/[.]/>.

=head2 C<$RE{net}{IPv4}{bin}{-sep}>

Returns a pattern that matches a valid IP address in "dotted binary"

If C<< -sep=I<P> >> is specified the pattern I<P> is used as the separator.
By default I<P> is C<qr/[.]/>.

=head2 C<$RE{net}{MAC}>

Returns a pattern that matches a valid MAC or ethernet address as
colon separated hexadecimals.

For this pattern, and the next four, under C<-keep> (See L<Regexp::Common>):

=over 4

=item $1

captures the entire match

=item $2

captures the first component of the address

=item $3

captures the second component of the address

=item $4

captures the third component of the address

=item $5

captures the fourth component of the address

=item $6

captures the fifth component of the address

=item $7

captures the sixth and final component of the address

=back

This pattern, and the next four, have a C<subs> method as well, which
will transform a matching MAC address into so called canonical format.
Canonical format means that every component of the address will be
exactly two hexadecimals (with a leading zero if necessary), and the
components will be separated by a colon.

The C<subs> method will not work for binary MAC addresses if the
Perl version predates 5.6.0.

=head2 C<$RE{net}{MAC}{dec}{-sep}>

Returns a pattern that matches a valid MAC address as colon separated
decimals.

If C<< -sep=I<P> >> is specified the pattern I<P> is used as the separator.
By default I<P> is C<qr/:/>. 

=head2 C<$RE{net}{MAC}{hex}{-sep}>

Returns a pattern that matches a valid MAC address as colon separated
hexadecimals, with the letters C<a> to C<f> in lower case.

If C<< -sep=I<P> >> is specified the pattern I<P> is used as the separator.
By default I<P> is C<qr/:/>.

=head2 C<$RE{net}{MAC}{oct}{-sep}>

Returns a pattern that matches a valid MAC address as colon separated
octals.

If C<< -sep=I<P> >> is specified the pattern I<P> is used as the separator.
By default I<P> is C<qr/:/>.

=head2 C<$RE{net}{MAC}{bin}{-sep}>

Returns a pattern that matches a valid MAC address as colon separated
binary numbers.

If C<< -sep=I<P> >> is specified the pattern I<P> is used as the separator.
By default I<P> is C<qr/:/>.

=head2 C<$RE{net}{IPv6}{-sep => ':'}{-style => 'HeX'}>

Returns a pattern matching IPv6 numbers. An IPv6 address consists of
eigth groups of four hexadecimal digits, separated by colons. In each
group, leading zeros may be omitted. Two or more consecutive groups
consisting of only zeros may be omitted (including any colons separating
them), resulting into two sets of groups, separated by a double colon.
(Each of the groups may be empty; C<< :: >> is a valid address, equal to
C<< 0000:0000:0000:0000:0000:0000:0000:0000 >>). The hex numbers may be
in either case.

If the C<< -sep >> option is used, its argument is a pattern that matches
the separator that separates groups. This defaults to C<< : >>. The 
C<< -style >> option is used to denote which case the hex numbers may be.
The default style, C<< 'HeX' >> indicates both lower case letters C<< 'a' >>
to C<< 'f' >> and upper case letters C<< 'A' >> to C<< 'F' >> will be 
matched. The style C<< 'HEX' >> restricts matching to upper case letters,
and C<< 'hex' >> only matches lower case letters.

If C<< {-keep} >> is used, C<< $1 >> to C<< $9 >> will be set. C<< $1 >>
will be set to the matched address, while C<< $2 >> to C<< $9 >> will be
set to each matched group. If a group is omitted because it contains all
zeros, its matching variable will be the empty string.

Example:

  "2001:db8:85a3::8a2e:370:7334" =~ /$RE{net}{IPv6}{-keep}/;
  print $2;    # '2001'
  print $4;    # '85a3'
  print $6;    # Empty string
  print $8;    # '370'

Perl 5.10 (or later) is required for this pattern.

=head2 C<$RE{net}{domain}>

Returns a pattern to match domains (and hosts) as defined in RFC 1035.
Under I{-keep} only the entire domain name is returned.

RFC 1035 says that a single space can be a domainname too. So, the
pattern returned by C<$RE{net}{domain}> recognizes a single space
as well. This is not always what people want. If you want to recognize
domainnames, but not a space, you can do one of two things, either use

    /(?! )$RE{net}{domain}/

or use the C<{-nospace}> option (without an argument).

RFC 1035 does B<not> allow host or domain names to start with a digits;
however, this restriction is relaxed in RFC 1101; this RFC allows host
and domain names to start with a digit, as long as the first part of
a domain does not look like an IP address. If the C<< {-rfc1101} >> option
is given (as in C<< $RE {net} {domain} {-rfc1101} >>), we will match using
the relaxed rules.

=head1 REFERENCES

=over 4

=item B<RFC 1035>

Mockapetris, P.: I<DOMAIN NAMES - IMPLEMENTATION AND SPECIFICATION>.
November 1987.

=item B<RFC 1101>

Mockapetris, P.: I<DNS Encoding of Network Names and Other Types>.
April 1987.

=back

=head1 SEE ALSO

L<Regexp::Common> for a general description of how to use this interface.

=head1 AUTHOR

Damian Conway I<damian@conway.org>.

=head1 MAINTAINANCE

This package is maintained by Abigail S<(I<regexp-common@abigail.be>)>.

=head1 BUGS AND IRRITATIONS

Bound to be plenty.

For a start, there are many common regexes missing.
Send them in to I<regexp-common@abigail.be>.

=head1 LICENSE and COPYRIGHT

This software is Copyright (c) 2001 - 2013, Damian Conway and Abigail.

This module is free software, and maybe used under any of the following
licenses:

 1) The Perl Artistic License.     See the file COPYRIGHT.AL.
 2) The Perl Artistic License 2.0. See the file COPYRIGHT.AL2.
 3) The BSD Licence.               See the file COPYRIGHT.BSD.
 4) The MIT Licence.               See the file COPYRIGHT.MIT.

=cut
