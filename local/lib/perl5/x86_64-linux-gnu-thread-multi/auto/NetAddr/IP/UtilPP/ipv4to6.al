# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 363 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/ipv4to6.al)"
sub ipv4to6 {
  _deadlen(length($_[0]),32)
        if length($_[0]) != 4;
#  return pack('L3H8',0,0,0,unpack('H8',$_[0]));
  return pack('L3a4',0,0,0,$_[0]);
}

# end of NetAddr::IP::UtilPP::ipv4to6
1;
