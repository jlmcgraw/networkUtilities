# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 1253 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/coalesce.al)"
sub coalesce
{
    my $masklen	= shift;
    if (ref $masklen && ref $masklen eq __PACKAGE__ ) {	# if called as a method
      push @_,$masklen;
      $masklen = shift;
    }

    my $number	= shift;

    # Addresses are at @_
    return [] unless @_;
    my %ret = ();
    my $type = $_[0]->{isv6};
    return [] unless defined $type;

    for my $ip (@_)
    {
	return [] unless $ip->{isv6} == $type;
	$type = $ip->{isv6};
	my $n = NetAddr::IP->new($ip->addr . '/' . $masklen)->network;
	if ($ip->masklen > $masklen)
	{
	    $ret{$n} += $ip->num + $NetAddr::IP::Lite::Old_nth;
	}
    }

    my @ret = ();

    # Add to @ret any arguments with netmasks longer than our argument
    for my $c (sort { $a->masklen <=> $b->masklen }
	       grep { $_->masklen <= $masklen } @_)
    {
	next if grep { $_->contains($c) } @ret;
	push @ret, $c->network;
    }

    # Now add to @ret all the subnets with more than $number hits
    for my $c (map { new NetAddr::IP $_ }
	       grep { $ret{$_} >= $number }
	       keys %ret)
    {
	next if grep { $_->contains($c) } @ret;
	push @ret, $c;
    }

    return \@ret;
}

# end of NetAddr::IP::coalesce
1;
