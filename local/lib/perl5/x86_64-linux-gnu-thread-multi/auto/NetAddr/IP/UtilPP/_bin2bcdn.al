# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 523 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/_bin2bcdn.al)"
sub _bin2bcdn {
  my($b128) = @_;
  my @binary = unpack('N4',$b128);
  my @nbcd = (0,0,0,0,0);	# 5 - 32 bit registers
  my ($add3, $msk8, $bcd8, $carry, $tmp);
  my $j = 0;
  my $k = -1;
  my $binmsk = 0;
  foreach(0..127) {
    unless ($binmsk) {
      $binmsk = 0x80000000;
      $k++;
    }
    $carry = $binary[$k] & $binmsk;
    $binmsk >>= 1;
    next unless $carry || $j;				# skip leading zeros
    foreach(4,3,2,1,0) {
      $bcd8 = $nbcd[$_];
      $add3 = 3;
      $msk8 = 8;

      $j = 0;
      while ($j < 8) {
	$tmp = $bcd8 + $add3;
	if ($tmp & $msk8) {
	  $bcd8 = $tmp;
	}
	$add3 <<= 4;
	$msk8 <<= 4;
	$j++;
      }
      $tmp = $bcd8 & 0x80000000;	# propagate carry
      $bcd8 <<= 1;			# x2
      if ($carry) {
	$bcd8 += 1;
      }
      $nbcd[$_] = $bcd8;
      $carry = $tmp;
    }
  }
  pack('N5',@nbcd);
}

# end of NetAddr::IP::UtilPP::_bin2bcdn
1;
