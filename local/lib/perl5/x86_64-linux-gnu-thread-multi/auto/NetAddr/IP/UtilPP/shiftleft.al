# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 183 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/shiftleft.al)"
sub shiftleft {
  _deadlen(length($_[0]))
	if length($_[0]) != 16;
  my($bits,$shifts) = @_;
  return $bits unless $shifts;
  die "Bad arg value for ".__PACKAGE__.":shiftleft, length should be 0 thru 128"
	if $shifts < 0 || $shifts > 128;
  my @uint32t = unpack('N4',$bits);
  do {
    $bits = _128x2(\@uint32t);
    $shifts--
  } while $shifts > 0;
   pack('N4',@uint32t);
}

# end of NetAddr::IP::UtilPP::shiftleft
1;
