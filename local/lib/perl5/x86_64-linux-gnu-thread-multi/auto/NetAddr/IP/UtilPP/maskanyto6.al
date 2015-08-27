# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 418 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/maskanyto6.al)"
sub maskanyto6 {
  my $naddr = shift;
  my $len = length($naddr);
  return $naddr if $len == 16;
#  return pack('L3H8',0xffffffff,0xffffffff,0xffffffff,unpack('H8',$naddr))
  return pack('L3a4',0xffffffff,0xffffffff,0xffffffff,$naddr)
	if $len == 4;
  _deadlen($len,'32 or 128');
}

# end of NetAddr::IP::UtilPP::maskanyto6
1;
