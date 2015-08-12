# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 994 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/_splitplan.al)"
# input:	$naip,
#		@bits,		 list of masks for splits
#
#  returns:	empty array request will not fit in submitted net
#		(\@bits,undef)	 if there is just one plan item i.e. return original net
#		(\@bits,\%masks) for a real plan
#
sub _splitplan {
  my($ip,@bits) = @_;
  my $addr = $ip->addr();
  my $isV6 = $ip->{isv6};
  unless (@bits) {
    $bits[0] = $isV6 ? 128 : 32;
  }
  my $basem = $ip->masklen();

  my(%nets,$dif);
  my $denom = 0;

  my($x,$maddr);
  foreach(@bits) {
    if (ref $_) {	# is a NetAddr::IP
      $x = $_->{isv6} ? $_->{addr} : $_->{addr} | V4mask;
      ($x,$maddr) = notcontiguous($x);
      return () if $x;	# spurious bits
      $_ = $isV6 ? $maddr : $maddr - 96;
    }
    elsif ( $_ =~ /^d+$/ ) {		# is a negative number of the form -nnnn
	;
    }
    elsif ($_ = NetAddr::IP->new($addr,$_,$isV6)) { # will be undefined if bad mask and will fall into oops!
      $_ = $_->masklen();
    }
    else {
      return ();	# oops!
    }
    $dif = $_ - $basem;			# for normalization
    return () if $dif < 0;		# overange nets not allowed
    return (\@bits,undef) unless ($dif || $#bits);	# return if original net = mask alone
    $denom = $dif if $dif > $denom;
    next if exists $nets{$_};
    $nets{$_} = $_ - $basem;		# for normalization
  }

# $denom is the normalization denominator, since these are all exponents
# normalization can use add/subtract to accomplish normalization
#
# keys of %nets are the masks used by this split
# values of %nets are the normalized weighting for
# calculating when the split is "full" or complete
# %masks values contain the actual masks for each split subnet
# @bits contains the masks in the order the user actually wants them
#
  my %masks;					# calculate masks
  my $maskbase = $isV6 ? 128 : 32;
  foreach( keys %nets ) {
    $nets{$_} = 2 ** ($denom - $nets{$_});
    $masks{$_} = shiftleft(Ones, $maskbase - $_);
  }

  my @plan;
  my $idx = 0;
  $denom = 2 ** $denom;
  PLAN:
  while ($denom > 0) {				# make a net plan
    my $nexmask = ($idx < $#bits) ? $bits[$idx] : $bits[$#bits];
    ++$idx;
    unless (($denom -= $nets{$nexmask}) < 0) {
      return () if (push @plan, $nexmask) > $_netlimit;
      next;
    }
# a fractional net is needed that is not in the mask list or the replicant
    $denom += $nets{$nexmask};			# restore mistake
  TRY:
    foreach (sort { $a <=> $b } keys %nets) {
      next TRY if $nexmask > $_;
      do {
	next TRY if $denom - $nets{$_} < 0;
	return () if (push @plan, $_) > $_netlimit;
	$denom -= $nets{$_};
      } while $denom;
    }
    die 'ERROR: miscalculated weights' if $denom;
  }
  return () if $idx < @bits;			# overrange original subnet request
  return (\@plan,\%masks);
}

# end of NetAddr::IP::_splitplan
1;
