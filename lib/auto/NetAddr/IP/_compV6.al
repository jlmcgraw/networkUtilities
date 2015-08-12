# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 819 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/_compV6.al)"
#sub _old_compV6 {
#  my @addr = split(':',shift);
#  my $found = 0;
#  my $v;
#  foreach(0..$#addr) {
#    ($v = $addr[$_]) =~ s/^0+//;
#    $addr[$_] = $v || 0;
#  }
#  @_ = reverse(1..$#addr);
#  foreach(@_) {
#    if ($addr[$_] || $addr[$_ -1]) {
#      last if $found;
#      next;
#    }
#    $addr[$_] = $addr[$_ -1] = '';
#    $found = '1';
#  }
#  (my $rv = join(':',@addr)) =~ s/:+:/::/;
#  return $rv;
#}

# thanks to Rob Riepel <riepel@networking.Stanford.EDU>
# for this faster and more compact solution 11-17-08
sub _compV6 ($) {
    my $ip = shift;
    return $ip unless my @candidates = $ip =~ /((?:^|:)0(?::0)+(?::|$))/g;
    my $longest = (sort { length($b) <=> length($a) } @candidates)[0];
    $ip =~ s/$longest/::/;
    return $ip;
}

# end of NetAddr::IP::_compV6
1;
