package Regexp::Common::balanced; {

use Regexp::Common qw /pattern clean no_defaults/;

use strict;
use warnings;

use vars qw /$VERSION/;
$VERSION = '2013030901';

my %closer = ( '{'=>'}', '('=>')', '['=>']', '<'=>'>' );
my %cache;

sub nested {
    my ($start, $finish) = @_;

    return $cache {$start} {$finish} if exists $cache {$start} {$finish};

    my @starts   = map {s/\\(.)/$1/g; $_} grep {length}
                        $start  =~ /([^|\\]+|\\.)+/gs;
    my @finishes = map {s/\\(.)/$1/g; $_} grep {length}
                        $finish =~ /([^|\\]+|\\.)+/gs;

    push @finishes => ($finishes [-1]) x (@starts - @finishes);

    my @re;
    local $" = "|";
    foreach my $begin (@starts) {
        my $end = shift @finishes;

        my $qb  = quotemeta $begin;
        my $qe  = quotemeta $end;
        my $fb  = quotemeta substr $begin => 0, 1;
        my $fe  = quotemeta substr $end   => 0, 1;

        my $tb  = quotemeta substr $begin => 1;
        my $te  = quotemeta substr $end   => 1;

        my $add;
        if ($fb eq $fe) {
            push @re =>
                   qq /(?:$qb(?:(?>[^$fb]+)|$fb(?!$tb)(?!$te)|(?-1))*$qe)/;
        }
        else {
            my   @clauses =  "(?>[^$fb$fe]+)";
            push @clauses => "$fb(?!$tb)" if length $tb;
            push @clauses => "$fe(?!$te)" if length $te;
            push @clauses => "(?-1)";
            push @re      =>  qq /(?:$qb(?:@clauses)*$qe)/;
        }
    }

    $cache {$start} {$finish} = qr /(@re)/;
}


pattern name    => [qw /balanced -parens=() -begin= -end=/],
        create  => sub {
            my $flag = $_[1];
            unless (defined $flag -> {-begin} && length $flag -> {-begin} &&
                    defined $flag -> {-end}   && length $flag -> {-end}) {
                my @open  = grep {index ($flag->{-parens}, $_) >= 0}
                             ('[','(','{','<');
                my @close = map {$closer {$_}} @open;
                $flag -> {-begin} = join "|" => @open;
                $flag -> {-end}   = join "|" => @close;
            }
            return nested @$flag {qw /-begin -end/};
        },
        version => 5.010,
        ;

}

1;

__END__

=pod

=head1 NAME

Regexp::Common::balanced -- provide regexes for strings with balanced
parenthesized delimiters or arbitrary delimiters.

=head1 SYNOPSIS

    use Regexp::Common qw /balanced/;

    while (<>) {
        /$RE{balanced}{-parens=>'()'}/
                                   and print q{balanced parentheses\n};
    }


=head1 DESCRIPTION

Please consult the manual of L<Regexp::Common> for a general description
of the works of this interface.

Do not use this module directly, but load it via I<Regexp::Common>.

=head2 C<$RE{balanced}{-parens}>

Returns a pattern that matches a string that starts with the nominated
opening parenthesis or bracket, contains characters and properly nested
parenthesized subsequences, and ends in the matching parenthesis.

More than one type of parenthesis can be specified:

        $RE{balanced}{-parens=>'(){}'}

in which case all specified parenthesis types must be correctly balanced within
the string.

Since version 2013030901, C<< $1 >> will always be set (to the entire
matched substring), regardless whether C<< {-keep} >> is used or not.

=head2 C<< $RE{balanced}{-begin => "begin"}{-end => "end"} >>

Returns a pattern that matches a string that is properly balanced
using the I<begin> and I<end> strings as start and end delimiters.
Multiple sets of begin and end strings can be given by separating
them by C<|>s (which can be escaped with a backslash).

    qr/$RE{balanced}{-begin => "do|if|case"}{-end => "done|fi|esac"}/

will match properly balanced strings that either start with I<do> and
end with I<done>, start with I<if> and end with I<fi>, or start with
I<case> and end with I<esac>.

If I<-end> contains less cases than I<-begin>, the last case of I<-end>
is repeated. If it contains more cases than I<-begin>, the extra cases
are ignored. If either of I<-begin> or I<-end> isn't given, or is empty,
I<< -begin => '(' >> and I<< -end => ')' >> are assumed.

Since version 2013030901, C<< $1 >> will always be set (to the entire
matched substring), regardless whether C<< {-keep} >> is used or not.

=head2 Note

Since version 2013030901 the pattern will make of the recursive construct
C<< (?-1) >>, instead of using the problematic C<< (??{ }) >> construct.
This fixes an problem that was introduced in the 5.17 development track.
This also means the pattern is no longer available for Perls older than 5.010.

=head1 SEE ALSO

L<Regexp::Common> for a general description of how to use this interface.

=head1 AUTHOR

Damian Conway (damian@conway.org)

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
