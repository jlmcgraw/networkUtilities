# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 381 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/mask4to6.al)"
sub mask4to6 {
  _deadlen(length($_[0]),32)
        if length($_[0]) != 4;
#  return pack('L3H8',0xffffffff,0xffffffff,0xffffffff,unpack('H8',$_[0]));
  return pack('L3a4',0xffffffff,0xffffffff,0xffffffff,$_[0]);
}

# end of NetAddr::IP::UtilPP::mask4to6
1;
