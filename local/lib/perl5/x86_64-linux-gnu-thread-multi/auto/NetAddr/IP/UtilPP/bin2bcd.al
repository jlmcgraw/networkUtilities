# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 455 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/bin2bcd.al)"
sub bin2bcd {
  _deadlen(length($_[0]))
	if length($_[0]) != 16;
  unpack("H40",&_bin2bcdn) =~ /^0*(.+)/;
  $1;
}

# end of NetAddr::IP::UtilPP::bin2bcd
1;
