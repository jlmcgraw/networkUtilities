# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 276 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/add128.al)"
sub add128 {
  my($a128,$b128) = @_;
  _deadlen(length($a128))
	if length($a128) != 16;
  _deadlen(length($b128))
	if length($b128) != 16;
  @_ = ($a128,$b128,0);
# perl 5.8.4 fails with this operation. see perl bug [ 23429]
#  goto &slowadd128;
  slowadd128(@_);
}

# end of NetAddr::IP::UtilPP::add128
1;
