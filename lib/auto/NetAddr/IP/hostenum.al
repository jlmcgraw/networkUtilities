# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 1124 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/hostenum.al)"
sub hostenum ($) {
    return @{$_[0]->hostenumref};
}

# end of NetAddr::IP::hostenum
1;
