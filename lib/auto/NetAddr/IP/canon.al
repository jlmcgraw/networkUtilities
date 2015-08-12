# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 869 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/canon.al)"
sub canon($) {
  my $addr = $_[0]->addr;
  return $_[0]->{isv6} ? lc _compV6($addr) : $addr;
}

# end of NetAddr::IP::canon
1;
