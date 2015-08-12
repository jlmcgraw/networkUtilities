# NOTE: Derived from ../../blib/lib/NetAddr/IP/InetBase.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::InetBase;

#line 485 "../../blib/lib/NetAddr/IP/InetBase.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/InetBase/inet_any2n.al)"
sub inet_any2n($) {
  my($addr) = @_;
  $addr = '' unless $addr;
  $addr = '::' . $addr
	unless $addr =~ /:/;
  return ipv6_aton($addr);
}

# end of NetAddr::IP::InetBase::inet_any2n
1;
