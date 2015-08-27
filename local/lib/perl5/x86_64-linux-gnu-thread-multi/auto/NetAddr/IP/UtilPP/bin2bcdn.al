# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 503 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/bin2bcdn.al)"
#=item * $bcdpacked = bin2bcdn($bits128);
#
#Convert a 128 bit binary string into binary coded decimal digits.
#This function is for testing only.
#
#  input:	128 bit string variable
#  returns:	string of packed decimal digits
#
#  i.e.	text = unpack("H*", $bcd);
#
#=cut

sub bin2bcdn {
  _deadlen(length($_[0]))
	if length($_[0]) != 16;
# perl 5.8.4 fails with this operation. see perl bug [ 23429]
#  goto &_bin2bcdn;
  &_bin2bcdn;
}

# end of NetAddr::IP::UtilPP::bin2bcdn
1;
