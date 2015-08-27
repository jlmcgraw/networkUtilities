# NOTE: Derived from ../../blib/lib/NetAddr/IP/InetBase.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::InetBase;

#line 406 "../../blib/lib/NetAddr/IP/InetBase.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/InetBase/ipv6_aton.al)"
sub ipv6_aton {
  my($ipv6) = @_;
  return undef unless $ipv6;
  local($1,$2,$3,$4,$5);
  if ($ipv6 =~ /^(.*:)(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/) {	# mixed hex, dot-quad
    return undef if $2 > 255 || $3 > 255 || $4 > 255 || $5 > 255;
    $ipv6 = sprintf("%s%X%02X:%X%02X",$1,$2,$3,$4,$5);			# convert to pure hex
  }
  my $c;
  return undef if
	$ipv6 =~ /[^:0-9a-fA-F]/ ||			# non-hex character
	(($c = $ipv6) =~ s/::/x/ && $c =~ /(?:x|:):/) ||	# double :: ::?
	$ipv6 =~ /[0-9a-fA-F]{5,}/;			# more than 4 digits
  $c = $ipv6 =~ tr/:/:/;				# count the colons
  return undef if $c < 7 && $ipv6 !~ /::/;
  if ($c > 7) {						# strip leading or trailing ::
    return undef unless
	$ipv6 =~ s/^::/:/ ||
	$ipv6 =~ s/::$/:/;
    return undef if --$c > 7;
  }
  while ($c++ < 7) {					# expand compressed fields
    $ipv6 =~ s/::/:::/;
  }
  $ipv6 .= 0 if $ipv6 =~ /:$/;
  my @hex = split(/:/,$ipv6);
  foreach(0..$#hex) {
    $hex[$_] = hex($hex[$_] || 0);
  }
  pack("n8",@hex);
}

# end of NetAddr::IP::InetBase::ipv6_aton
1;
