# NOTE: Derived from ../../blib/lib/NetAddr/IP/UtilPP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::UtilPP;

#line 605 "../../blib/lib/NetAddr/IP/UtilPP.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/UtilPP/_bcd2bin.al)"
sub _bcd2bin {
  my @bcd = split('',$_[0]);
  my @hbits = (0,0,0,0);
  my @digit = (0,0,0,0);
  my $found = 0;
  foreach(@bcd) {
    my $bcd = $_ & 0xf;		# just the nibble
    unless ($found) {
      next unless $bcd;		# skip leading zeros
      $found = 1;
      $hbits[3] = $bcd;		# set the first digit, no x10 necessary
      next;
    }
    _128x10(\@hbits);
    $digit[3] = $bcd;
    _sa128(\@hbits,\@digit,0);
  }
  return pack('N4',@hbits);
}

# end of NetAddr::IP::UtilPP::_bcd2bin
1;
