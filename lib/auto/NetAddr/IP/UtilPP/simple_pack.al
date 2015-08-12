# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 645 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/simple_pack.al)"
sub simple_pack {
  &_bcdcheck;
  my($bcd) = @_;
  while (length($bcd) < 40) {
    $bcd = '0'. $bcd;
  }
  return pack('H40',$bcd);
}

1;
1;
# end of NetAddr::IP::UtilPP::simple_pack
