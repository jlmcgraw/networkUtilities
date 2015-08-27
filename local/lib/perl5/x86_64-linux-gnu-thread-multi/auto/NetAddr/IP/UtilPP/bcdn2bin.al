# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 586 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/bcdn2bin.al)"
#=item * $bits128 = bcdn2bin($bcdpacked,$ndigits);
#
# Convert a packed bcd string into a 128 bit string variable
#
# input:	packed bcd string
#		number of digits in string
# returns:	128 bit string variable
#

sub bcdn2bin {
  my($bcd,$dc) = @_;
  $dc = 0 unless $dc;
  die "Bad argument length for ".__PACKAGE__.":bcdn2txt, is ".(2 * length($bcd)).", should be 1 to 40 digits"
	if length($bcd) > 20;
  die "Bad digit count for ".__PACKAGE__.":bcdn2bin, is $dc, should be 1 to 40 digits"
	if $dc < 1 || $dc > 40;
  return _bcd2bin(unpack("H$dc",$bcd));
}

# end of NetAddr::IP::UtilPP::bcdn2bin
1;
