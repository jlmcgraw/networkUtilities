# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 484 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/comp128.al)"
#=item * $onescomp = comp128($ipv6addr);
#
#This function is for testing, it is more efficient to use perl " ~ "
#on the bit string directly. This interface to the B<C> routine is published for
#module testing purposes because it is used internally in the B<sub128> routine. The
#function is very fast, but calling if from perl directly is very slow. It is almost
#33% faster to use B<sub128> than to do a 1's comp with perl and then call
#B<add128>. In the PurePerl version, it is a call to
#
#  sub {return ~ $_[0]};
#
#=cut

sub comp128 {
  _deadlen(length($_[0]))
	if length($_[0]) != 16;
  return ~ $_[0];
}

# end of NetAddr::IP::UtilPP::comp128
1;
