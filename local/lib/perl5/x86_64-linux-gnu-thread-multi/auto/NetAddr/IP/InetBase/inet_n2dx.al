# NOTE: Derived from ../../blib/lib/NetAddr/IP/InetBase.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::InetBase;

#line 507 "../../blib/lib/NetAddr/IP/InetBase.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/InetBase/inet_n2dx.al)"
sub inet_n2dx($) {
  my($nadr) = @_;
  if (isAnyIPv4($nadr)) {
    local $1;
    ipv6_n2d($nadr) =~ /([^:]+)$/;
    return $1;
  }
  return ipv6_n2x($nadr);
}

# end of NetAddr::IP::InetBase::inet_n2dx
1;
