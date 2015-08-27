# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 471 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/bcd2bin.al)"
sub bcd2bin {
  &_bcdcheck;
# perl 5.8.4 fails with this operation. see perl bug [ 23429]
#  goto &_bcd2bin;
  &_bcd2bin;
}

# end of NetAddr::IP::UtilPP::bcd2bin
1;
