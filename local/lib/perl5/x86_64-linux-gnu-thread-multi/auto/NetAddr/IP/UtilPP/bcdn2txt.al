# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 566 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/bcdn2txt.al)"
#=item * $bcdtext = bcdn2txt($bcdpacked);
#
#Convert a packed bcd string into text digits, suppress the leading zeros.
#This function is for testing only.
#
#  input:	string of packed decimal digits
#		consisting of exactly 40 digits
#  returns:	hexdecimal digits
#
#Similar to unpack("H*", $bcd);
#
#=cut

sub bcdn2txt {
  die "Bad argument length for ".__PACKAGE__.":bcdn2txt, is ".(2 * length($_[0])).", should be exactly 40 digits"
	if length($_[0]) != 20;
  (unpack('H40',$_[0])) =~ /^0*(.+)/;
  $1;
}

# end of NetAddr::IP::UtilPP::bcdn2txt
1;
