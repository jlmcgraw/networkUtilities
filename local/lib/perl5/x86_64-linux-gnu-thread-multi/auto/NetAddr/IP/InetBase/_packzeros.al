# NOTE: Derived from ../../blib/lib/NetAddr/IP/InetBase.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::InetBase;

#line 596 "../../blib/lib/NetAddr/IP/InetBase.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/InetBase/_packzeros.al)"
sub _packzeros {
  my $x6 = shift;
  if ($x6 =~ /\:\:/) {				# already contains ::
# then re-optimize
    $x6 = ($x6 =~ /\:\d+\.\d+\.\d+\.\d+/)	# ipv4 notation ?
	? ipv6_n2d(ipv6_aton($x6))
	: ipv6_n2x(ipv6_aton($x6));
  }
  $x6 = ':'. lc $x6;				# prefix : & always lower case
  my $d = '';
  if ($x6 =~ /(.+\:)(\d+\.\d+\.\d+\.\d+)/) {	# if contains dot quad
    $x6 = $1;					# save hex piece
    $d = $2;					# and dot quad piece
  }
  $x6 .= ':';					# suffix :
  $x6 =~ s/\:0+/\:0/g;				# compress strings of 0's to single '0'
  $x6 =~ s/\:0([1-9a-f]+)/\:$1/g;		# eliminate leading 0's in hex strings
  my @x = $x6 =~ /(?:\:0)*/g;			# split only strings of :0:0..."

  my $m = 0;
  my $i = 0;

  for (0..$#x) {				# find next longest pattern :0:0:0...
    my $len = length($x[$_]);
    next unless $len > $m;
    $m = $len;
    $i = $_;					# index to first longest pattern
  }

  if ($m > 2) {					# there was a string of 2 or more zeros
    $x6 =~ s/$x[$i]/\:/;	  		# replace first longest :0:0:0... with "::"
    unless ($i) {				# if it is the first match, $i = 0
      $x6 = substr($x6,0,-1);			# keep the leading ::, remove trailing ':'
    } else {
      $x6 = substr($x6,1,-1);			# else remove leading & trailing ':'
    }
    $x6 .= ':' unless $x6 =~ /\:\:/;		# restore ':' if match and we can't see it, implies trailing '::'
  } else {					# there was no match
    $x6 = substr($x6,1,-1);			# remove leading & trailing ':'
  }
  $x6 .= $d;					# append digits if any
  return $case
	? uc $x6
	: $x6;
}

1;
1;
# end of NetAddr::IP::InetBase::_packzeros
