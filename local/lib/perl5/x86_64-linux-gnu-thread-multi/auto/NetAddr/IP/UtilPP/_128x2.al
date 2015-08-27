# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 145 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/_128x2.al)"
#=item * $rv = isIPv4($bits128);
#
#This function returns true if there are no on bits present in the IPv6
#portion of the 128 bit string and false otherwise.
#
#=cut
#
#sub xisIPv4 {
#  _deadlen(length($_[0]))
#	if length($_[0]) != 16;
#  return 0 if vec($_[0],0,32);
#  return 0 if vec($_[0],1,32);
#  return 0 if vec($_[0],2,32);
#  return 1;
#}


# multiply x 2
#
sub _128x2 {
  my $inp = shift;
  $$inp[0] = ($$inp[0] << 1 & 0xffffffff) + (($$inp[1] & 0x80000000) ? 1:0);
  $$inp[1] = ($$inp[1] << 1 & 0xffffffff) + (($$inp[2] & 0x80000000) ? 1:0);
  $$inp[2] = ($$inp[2] << 1 & 0xffffffff) + (($$inp[3] & 0x80000000) ? 1:0);
  $$inp[3] = $$inp[3] << 1 & 0xffffffff;
}

# end of NetAddr::IP::UtilPP::_128x2
1;
