# NOTE: Derived from ../../blib/lib/NetAddr/IP/InetBase.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package NetAddr::IP::InetBase;

#line 378 "../../blib/lib/NetAddr/IP/InetBase.pm (autosplit into ../../blib/lib/auto/NetAddr/IP/InetBase/inet_ntoa.al)"
sub inet_ntoa {
  die 'Bad arg length for '. __PACKAGE__ ."::inet_ntoa, length is ". length($_[0]) ." should be 4"
        unless length($_[0]) == 4;
  my @hex = (unpack("n2",$_[0]));
  $hex[3] = $hex[1] & 0xff;
  $hex[2] = $hex[1] >> 8;
  $hex[1] = $hex[0] & 0xff;
  $hex[0] >>= 8;
  return sprintf("%d.%d.%d.%d",@hex);
}

# end of NetAddr::IP::InetBase::inet_ntoa
1;
