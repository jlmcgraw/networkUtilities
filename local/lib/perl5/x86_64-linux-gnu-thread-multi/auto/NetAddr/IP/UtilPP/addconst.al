# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 250 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/addconst.al)"
sub addconst {
  my($a128,$const) = @_;
  _deadlen(length($a128))
	if length($a128) != 16;
  unless ($const) {
    return (wantarray) ? ($const,$a128) : $const;
  }
  my $sign = ($const < 0) ? 0xffffffff : 0;
  my $b128 = pack('N4',$sign,$sign,$sign,$const);
  @_ = ($a128,$b128,0);
# perl 5.8.4 fails with this operation. see perl bug [ 23429]
#  goto &slowadd128;
  slowadd128(@_);
}

# end of NetAddr::IP::UtilPP::addconst
1;
