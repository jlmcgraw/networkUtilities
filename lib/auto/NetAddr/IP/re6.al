# NOTE: Derived from blib/lib/NetAddr/IP.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP;

#line 1464 "blib/lib/NetAddr/IP.pm (autosplit into blib/lib/auto/NetAddr/IP/re6.al)"
sub re6($) {
  my @net = split('',sprintf("%04X%04X%04X%04X%04X%04X%04X%04X",unpack('n8',$_[0]->network->{addr})));
  my @brd = split('',sprintf("%04X%04X%04X%04X%04X%04X%04X%04X",unpack('n8',$_[0]->broadcast->{addr})));

  my @dig;

  foreach(0..$#net) {
    my $n = $net[$_];
    my $b = $brd[$_];
    my $m;
    if ($n.'' eq $b.'') {
      if ($n =~ /\d/) {
	push @dig, $n;
      } else {
	push @dig, '['.(lc $n).$n.']';
      }
    } else {
      my $n = $net[$_];
      my $b = $brd[$_];
      if ($n.'' eq 0 && $b =~ /F/) {
	push @dig, 'x';
      }
      elsif ($n =~ /\d/ && $b =~ /\d/) {
	push @dig, '['.$n.'-'.$b.']';
      }
      elsif ($n =~ /[A-F]/ && $b =~ /[A-F]/) {
	$n .= '-'.$b;
	push @dig, '['.(lc $n).$n.']';
      }
      elsif ($n =~ /\d/ && $b =~ /[A-F]/) {
	$m = ($n == 9) ? 9 : $n .'-9';
	if ($b =~ /A/) {
	  $m .= 'aA';
	} else {
	  $b = 'A-'. $b;
	  $m .= (lc $b). $b;
	}
	push @dig, '['.$m.']';
      }
      elsif ($n =~ /[A-F]/ && $b =~ /\d/) {
	if ($n =~ /A/) {
	  $m = 'aA';
	} else {
	  $n .= '-F';
	  $m = (lc $n).$n;
	}
	if ($b == 9) {
	  $m .= 9;
	} else {
	  $m .= $b .'-9';
	}
	push @dig, '['.$m.']';
      }
    }
  }
  my @grp;
  do {
    my $grp = join('',splice(@dig,0,4));
    if ($grp =~ /^(0+)/) {
      my $l = length($1);
      if ($l == 4) {
	$grp = '0{1,4}';
      } else {
	$grp =~ s/^${1}/0\{0,$l\}/;
      }
    }
    if ($grp =~ /(x+)$/) {
      my $l = length($1);
      if ($l == 4) {
	$grp = '[0-9a-fA-F]{1,4}';
      } else {
	$grp =~ s/x+/\[0\-9a\-fA\-F\]\{$l\}/;
      }
    }
    push @grp, $grp;
  } while @dig > 0;
  return '('. join(':',@grp) .')';
}

# end of NetAddr::IP::re6
1;
