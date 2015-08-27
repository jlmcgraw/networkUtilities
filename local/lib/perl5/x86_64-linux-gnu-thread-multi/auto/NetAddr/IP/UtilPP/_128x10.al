# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 172 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/_128x10.al)"
# multiply x 10
#
sub _128x10 {
  my($a128p) = @_;
  _128x2($a128p);		# x2
  my @x2 = @$a128p;		# save the x2 value
  _128x2($a128p);
  _128x2($a128p);		# x8
  _sa128($a128p,\@x2,0);	# add for x10
}

# end of NetAddr::IP::UtilPP::_128x10
1;
