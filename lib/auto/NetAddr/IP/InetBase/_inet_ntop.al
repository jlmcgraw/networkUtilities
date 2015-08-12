# NOTE: Derived from ../../blib/lib/NetAddr/IP/InetBase.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::InetBase;

#line 575 "../../blib/lib/NetAddr/IP/InetBase.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/InetBase/_inet_ntop.al)"
sub _inet_ntop {
  my($af,$naddr) = @_;
  die 'Unsupported address family for '. __PACKAGE__ ."::inet_ntop, af is $af"
	unless $af == AF_INET6() || $af == AF_INET();
  if ($af == AF_INET()) {
    inet_ntoa($naddr);
  } else {
    return ($case)
	? lc packzeros(ipv6_n2x($naddr))
	: _packzeros(ipv6_n2x($naddr));
  }
}

# end of NetAddr::IP::InetBase::_inet_ntop
1;
