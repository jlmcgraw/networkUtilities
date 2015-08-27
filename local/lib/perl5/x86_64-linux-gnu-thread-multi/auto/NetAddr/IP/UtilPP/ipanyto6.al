# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 398 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/ipanyto6.al)"
sub ipanyto6 {
  my $naddr = shift;
  my $len = length($naddr);
  return $naddr if $len == 16;
#  return pack('L3H8',0,0,0,unpack('H8',$naddr))
  return pack('L3a4',0,0,0,$naddr)
	if $len == 4;
  _deadlen($len,'32 or 128');
}

# end of NetAddr::IP::UtilPP::ipanyto6
1;
