# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 483 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/do_prefix.al)"
sub do_prefix ($$$) {
    my $mask	= shift;
    my $faddr	= shift;
    my $laddr	= shift;

    if ($mask > 24) {
	return "$faddr->[0].$faddr->[1].$faddr->[2].$faddr->[3]-$laddr->[3]";
    }
    elsif ($mask == 24) {
	return "$faddr->[0].$faddr->[1].$faddr->[2].";
    }
    elsif ($mask > 16) {
	return "$faddr->[0].$faddr->[1].$faddr->[2]-$laddr->[2].";
    }
    elsif ($mask == 16) {
	return "$faddr->[0].$faddr->[1].";
    }
    elsif ($mask > 8) {
	return "$faddr->[0].$faddr->[1]-$laddr->[1].";
    }
    elsif ($mask == 8) {
	return "$faddr->[0].";
    }
    else {
	return "$faddr->[0]-$laddr->[0]";
    }
}

# end of NetAddr::IP::do_prefix
1;
