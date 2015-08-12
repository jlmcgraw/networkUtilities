# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 333 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/notcontiguous.al)"
sub notcontiguous {
  _deadlen(length($_[0]))
	if length($_[0]) != 16;
  my @ua = unpack('N4', ~$_[0]);
  my $count;
  for ($count = 128;$count > 0; $count--) {
	last unless $ua[3] & 1;
	$ua[3] >>= 1;
	$ua[3] |= 0x80000000 if $ua[2] & 1;
	$ua[2] >>= 1;
	$ua[2] |= 0x80000000 if $ua[1] & 1;
	$ua[1] >>= 1;
	$ua[1] |= 0x80000000 if $ua[0] & 1;
	$ua[0] >>= 1;
  }

  my $spurious = $ua[0] | $ua[1] | $ua[2] | $ua[3];
  return $spurious unless wantarray;
  return ($spurious,$count);
}

# end of NetAddr::IP::UtilPP::notcontiguous
1;
