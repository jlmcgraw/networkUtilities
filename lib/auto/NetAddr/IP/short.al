# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 850 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/short.al)"
sub short($) {
  my $addr = $_[0]->addr;
  if (! $_[0]->{isv6} && isIPv4($_[0]->{addr})) {
    my @o = split(/\./, $addr, 4);
    splice(@o, 1, 2) if $o[1] == 0 and $o[2] == 0;
    return join '.', @o;
  }
  return _compV6($addr);
}

# end of NetAddr::IP::short
1;
