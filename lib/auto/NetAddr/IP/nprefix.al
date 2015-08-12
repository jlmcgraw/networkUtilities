# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 714 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/nprefix.al)"
# only applicable to ipV4
sub nprefix($) {
    return undef if $_[0]->{isv6};
    my $mask = (notcontiguous($_[0]->{mask}))[1];
    return $_[0]->addr if $mask == 128;
    $mask -= 96;
    my @faddr = split (/\./, $_[0]->first->addr);
    my @laddr = split (/\./, $_[0]->last->addr);
    return do_prefix $mask, \@faddr, \@laddr;
}

# end of NetAddr::IP::nprefix
1;
