# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 306 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/sub128.al)"
sub sub128 {
  _deadlen(length($_[0]))
	if length($_[0]) != 16;
  _deadlen(length($_[1]))
	if length($_[1]) != 16;
  my $a128 = $_[0];
  my $b128 = ~$_[1];
  @_ = ($a128,$b128,1);
# perl 5.8.4 fails with this operation. see perl bug [ 23429]
#  goto &slowadd128;
  slowadd128(@_);
}

# end of NetAddr::IP::UtilPP::sub128
1;
