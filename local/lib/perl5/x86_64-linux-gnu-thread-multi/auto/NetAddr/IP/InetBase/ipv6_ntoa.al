# NOTE: Derived from ../../blib/lib/NetAddr/IP/InetBase.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::InetBase;

#line 448 "../../blib/lib/NetAddr/IP/InetBase.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/InetBase/ipv6_ntoa.al)"
sub ipv6_ntoa {
  return inet_ntop(AF_INET6(),$_[0]);
}

# end of NetAddr::IP::InetBase::ipv6_ntoa
1;
