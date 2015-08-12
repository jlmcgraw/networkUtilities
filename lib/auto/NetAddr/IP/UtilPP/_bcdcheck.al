# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 625 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/_bcdcheck.al)"
#=item * $bcdpacked = simple_pack($bcdtext);
#
#Convert a numeric string into a packed bcd string, left fill with zeros
#This function is for testing only.
#
#  input:	string of decimal digits
#  returns:	string of packed decimal digits
#
#Similar to pack("H*", $bcdtext);
#
sub _bcdcheck {
  my($bcd) = @_;;
  my $sub = (caller(1))[3];
  my $len = length($bcd);
  die "Bad bcd number length $_ ".__PACKAGE__.":simple_pack, should be 1 to 40 digits"
	if $len > 40 || $len < 1;
  die "Bad character in decimal input string '$1' for ".__PACKAGE__.":simple_pack"
	if $bcd =~ /(\D)/;
}

# end of NetAddr::IP::UtilPP::_bcdcheck
1;
