# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 198 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/slowadd128.al)"
sub slowadd128 {
  my @ua = unpack('N4',$_[0]);
  my @ub = unpack('N4',$_[1]);
  my $carry = _sa128(\@ua,\@ub,$_[2]);
  return ($carry,pack('N4',@ua))
        if wantarray;
  return $carry;
}

# end of NetAddr::IP::UtilPP::slowadd128
1;
