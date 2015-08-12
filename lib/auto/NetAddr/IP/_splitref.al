# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 1082 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/_splitref.al)"
# input:	$rev,	# t/f
#		$naip,
#		@bits	# list of masks for split
#
sub _splitref {
  my $rev = shift;
  my($plan,$masks) = &_splitplan;
# bug report 82719
  croak("netmask error: overrange or spurious bits") unless defined $plan;
#  return undef unless $plan;
  my $net = $_[0]->network();
  return [$net] unless $masks;
  my $addr = $net->{addr};
  my $isV6 = $net->{isv6};
  my @plan = $rev ? reverse @$plan : @$plan;
# print "plan @plan\n";

# create splits
  my @ret;
  while ($_ = shift @plan) {
    my $mask = $masks->{$_};
    push @ret, $net->_new($addr,$mask,$isV6);
    last unless @plan;
    $addr = (sub128($addr,$mask))[1];
  }
  return \@ret;
}

# end of NetAddr::IP::_splitref
1;
