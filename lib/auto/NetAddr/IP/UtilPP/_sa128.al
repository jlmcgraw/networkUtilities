# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 207 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/_sa128.al)"
sub _sa128 {
  my($uap,$ubp,$carry) = @_;
  if (($$uap[3] += $$ubp[3] + $carry) > 0xffffffff) {
    $$uap[3] -= 4294967296;	# 0x1_00000000
    $carry = 1;
  } else {
    $carry = 0;
  }

  if (($$uap[2] += $$ubp[2] + $carry) > 0xffffffff) {
    $$uap[2] -= 4294967296;
    $carry = 1;
  } else {
    $carry = 0;
  }

  if (($$uap[1] += $$ubp[1] + $carry) > 0xffffffff) {
    $$uap[1] -= 4294967296;
    $carry = 1;
  } else {
    $carry = 0;
  }

  if (($$uap[0] += $$ubp[0] + $carry) > 0xffffffff) {
    $$uap[0] -= 4294967296;
    $carry = 1;
  } else {
    $carry = 0;
  }
  $carry;
}

# end of NetAddr::IP::UtilPP::_sa128
1;
