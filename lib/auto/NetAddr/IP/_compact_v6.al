# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 779 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/_compact_v6.al)"
sub _compact_v6 ($) {
    my $addr = shift;

    my @o = split /:/, $addr;
    return $addr unless @o and grep { $_ =~ m/^0+$/ } @o;

    my @candidates	= ();
    my $start		= undef;

    for my $i (0 .. $#o)
    {
	if (defined $start)
	{
	    if ($o[$i] !~ m/^0+$/)
	    {
		push @candidates, [ $start, $i - $start ];
		$start = undef;
	    }
	}
	else
	{
	    $start = $i if $o[$i] =~ m/^0+$/;
	}
    }

    push @candidates, [$start, 8 - $start] if defined $start;

    my $l = (sort { $b->[1] <=> $a->[1] } @candidates)[0];

    return $addr unless defined $l;

    $addr = $l->[0] == 0 ? '' : join ':', @o[0 .. $l->[0] - 1];
    $addr .= '::';
    $addr .= join ':', @o[$l->[0] + $l->[1] .. $#o];
    $addr =~ s/(^|:)0{1,3}/$1/g;

    return $addr;
}

# end of NetAddr::IP::_compact_v6
1;
