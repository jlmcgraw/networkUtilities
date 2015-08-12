# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 757 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/wildcard.al)"
sub wildcard($) {
  my $copy = $_[0]->copy;
  $copy->{addr} = ~ $copy->{mask};
  $copy->{addr} &= V4net unless $copy->{isv6};
  if (wantarray) {
    return ($_[0]->addr, $copy->addr);
  }
  return $copy->addr;
}

# end of NetAddr::IP::wildcard
1;
