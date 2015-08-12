# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 1400 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/re.al)"
sub re ($)
{
    return &re6 unless isIPv4($_[0]->{addr});
    my $self = shift->network;	# Insure a "zero" host part
    my ($addr, $mlen) = ($self->addr, $self->masklen);
    my @o = split('\.', $addr, 4);

    my $octet= '(?:[0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])';
    my @r = @o;
    my $d;

#    for my $i (0 .. $#o)
#    {
#	warn "# $self: $r[$i] == $o[$i]\n";
#    }

    if ($mlen != 32)
    {
	if ($mlen > 24)
	{
	     $d	= 2 ** (32 - $mlen) - 1;
	     $r[3] = '(?:' . join('|', ($o[3]..$o[3] + $d)) . ')';
	}
	else
	{
	    $r[3] = $octet;
	    if ($mlen > 16)
	    {
		$d = 2 ** (24 - $mlen) - 1;
		$r[2] = '(?:' . join('|', ($o[2]..$o[2] + $d)) . ')';
	    }
	    else
	    {
		$r[2] = $octet;
		if ($mlen > 8)
		{
		    $d = 2 ** (16 - $mlen) - 1;
		    $r[1] = '(?:' . join('|', ($o[1]..$o[1] + $d)) . ')';
		}
		else
		{
		    $r[1] = $octet;
		    if ($mlen > 0)
		    {
			$d = 2 ** (8 - $mlen) - 1;
			$r[0] = '(?:' . join('|', ($o[0] .. $o[0] + $d)) . ')';
		    }
		    else { $r[0] = $octet; }
		}
	    }
	}
    }

    ### no digit before nor after (look-behind, look-ahead)
    return "(?:(?<![0-9])$r[0]\\.$r[1]\\.$r[2]\\.$r[3](?![0-9]))";
}

# end of NetAddr::IP::re
1;
