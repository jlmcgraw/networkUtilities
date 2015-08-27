# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 117 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/_deadlen.al)"
sub _deadlen {
  my($len,$should) = @_;
  $len *= 8;
  $should = 128 unless $should;
  my $sub = (caller(1))[3];
  die "Bad argument length for $sub, is $len, should be $should";
}

# end of NetAddr::IP::UtilPP::_deadlen
1;
