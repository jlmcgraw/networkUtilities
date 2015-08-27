# NOTE: Derived from ../../blib/lib/NetAddr/IP/InetBase.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::InetBase;

#line 531 "../../blib/lib/NetAddr/IP/InetBase.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/InetBase/inet_n2ad.al)"
sub inet_n2ad($) {
  my($nadr) = @_;
  my $addr = ipv6_n2d($nadr);
  return $addr unless isAnyIPv4($nadr);
  local $1;
  $addr =~ /([^:]+)$/;
  return $1;
}

# end of NetAddr::IP::InetBase::inet_n2ad
1;
