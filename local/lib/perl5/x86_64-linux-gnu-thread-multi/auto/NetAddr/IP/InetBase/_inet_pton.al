# NOTE: Derived from ../../blib/lib/NetAddr/IP/InetBase.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::InetBase;

#line 551 "../../blib/lib/NetAddr/IP/InetBase.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/InetBase/_inet_pton.al)"
sub _inet_pton {
  my($af,$ip) = @_;
  die 'Bad address family for '. __PACKAGE__ ."::inet_pton, got $af"
	unless $af == AF_INET6() || $af == AF_INET();
  if ($af == AF_INET()) {
    inet_aton($ip);
  } else {
    ipv6_aton($ip);
  }
}

# end of NetAddr::IP::InetBase::_inet_pton
1;
