# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 438 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/ipv6to4.al)"
sub ipv6to4 {
  my $naddr = shift;
_deadlen(length($naddr))
	if length($naddr) != 16;
  @_ = unpack('L3H8',$naddr);
  return pack('H8',@{_}[3..10]);
}

# end of NetAddr::IP::UtilPP::ipv6to4
1;
