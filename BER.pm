### -*- mode: Perl -*-
######################################################################
### BER (Basic Encoding Rules) encoding and decoding.
######################################################################
### Copyright (c) 1995-2009, Simon Leinen.
###
### This program is free software; you can redistribute it under the
### "Artistic License 2.0" included in this distribution
### (file "Artistic").
######################################################################
### This module implements encoding and decoding of ASN.1-based data
### structures using the Basic Encoding Rules (BER).  Only the subset
### necessary for SNMP is implemented.
######################################################################
### Create by: See AUTHORS below
######################################################################

package BER;

=head1 NAME

BER

=head1 SYNOPSIS

    use BER;
    $encoded = encode_sequence (encode_int (123), encode_string ("foo"));
    ($i, $s) = decode_by_template ($encoded, "%{%i%s");
    # $i will now be 123, $s the string "foo".

=head1 DESCRIPTION

This is a simple library to encode and decode data using the Basic
Encoding Rules (BER) of Abstract Syntax Notation One (ASN.1).  It does
not claim to be a complete implementation of the standard, but
implements enough of the BER standard to encode and decode SNMP
messages.

=cut

require 5.002;

use strict;
use vars qw(@ISA @EXPORT $VERSION $pretty_print_timeticks
  %pretty_printer %default_printer $errmsg);
use Exporter;

$VERSION = '1.14';

@ISA = qw(Exporter);

@EXPORT = qw(context_flag constructor_flag
  encode_int encode_int_0 encode_null encode_oid
  encode_sequence encode_tagged_sequence
  encode_string encode_ip_address encode_timeticks
  encode_uinteger32 encode_counter32 encode_counter64
  encode_gauge32
  decode_sequence decode_by_template
  pretty_print pretty_print_timeticks
  hex_string hex_string_of_type
  encoded_oid_prefix_p errmsg
  register_pretty_printer unregister_pretty_printer);

=head1 VARIABLES

=cut

=head2 $pretty_print_timeticks (default: 1)

If non-zero (the default), C<pretty_print> will convert TimeTicks to
"human readable" strings containing days, hours, minutes and seconds.

If the variable is zero, C<pretty_print> will simply return an
unsigned integer representing hundredths of seconds.  If you prefer
this, bind C<$pretty_print_timeticks> to zero.

=cut

$pretty_print_timeticks = 1;

=head2 $errmsg - error message from last failed operation.

When they encounter errors, the routines in this module will generally
return C<undef>) and leave an informative error message in
C<$errmsg>).

=cut

### Prototypes
sub encode_header ($$);
sub encode_int_0 ();
sub encode_int ($);
sub encode_oid (@);
sub encode_null ();
sub encode_sequence (@);
sub encode_tagged_sequence ($@);
sub encode_string ($);
sub encode_ip_address ($);
sub encode_timeticks ($);
sub pretty_print ($);
sub pretty_using_decoder ($$);
sub pretty_string ($);
sub pretty_intlike ($);
sub pretty_unsignedlike ($);
sub pretty_oid ($);
sub pretty_uptime ($);
sub pretty_uptime_value ($);
sub pretty_ip_address ($);
sub pretty_generic_sequence ($);
sub register_pretty_printer ($);
sub unregister_pretty_printer ($);
sub hex_string ($);
sub hex_string_of_type ($$);
sub decode_oid ($);
sub decode_by_template;
sub decode_by_template_2;
sub decode_sequence ($);
sub decode_int ($);
sub decode_intlike ($);
sub decode_unsignedlike ($);
sub decode_intlike_s ($$);
sub decode_string ($);
sub decode_length ($@);
sub encoded_oid_prefix_p ($$);
sub decode_subid ($$$);
sub decode_generic_tlv ($);
sub error (@);
sub template_error ($$$);

sub version () { $VERSION; }

=head1 METHODS
=cut

### Flags for different types of tags

sub universal_flag   { 0x00 }
sub application_flag { 0x40 }
sub context_flag     { 0x80 }
sub private_flag     { 0xc0 }

sub primitive_flag   { 0x00 }
sub constructor_flag { 0x20 }

### Universal tags

sub boolean_tag      { 0x01 }
sub int_tag          { 0x02 }
sub bit_string_tag   { 0x03 }
sub octet_string_tag { 0x04 }
sub null_tag         { 0x05 }
sub object_id_tag    { 0x06 }
sub sequence_tag     { 0x10 }
sub set_tag          { 0x11 }
sub uptime_tag       { 0x43 }

### Flag for length octet announcing multi-byte length field

sub long_length { 0x80 }

### SNMP specific tags

sub snmp_ip_address_tag   { 0x00 | application_flag() }
sub snmp_counter32_tag    { 0x01 | application_flag() }
sub snmp_gauge32_tag      { 0x02 | application_flag() }
sub snmp_timeticks_tag    { 0x03 | application_flag() }
sub snmp_opaque_tag       { 0x04 | application_flag() }
sub snmp_nsap_address_tag { 0x05 | application_flag() }
sub snmp_counter64_tag    { 0x06 | application_flag() }
sub snmp_uinteger32_tag   { 0x07 | application_flag() }

## Error codes (SNMPv2 and later)
##
sub snmp_nosuchobject   { context_flag() | 0x00 }
sub snmp_nosuchinstance { context_flag() | 0x01 }
sub snmp_endofmibview   { context_flag() | 0x02 }

### pretty-printer initialization code.  Create a hash with
### the most common types of pretty-printer routines.

BEGIN {
    $default_printer{ int_tag() }             = \&pretty_intlike;
    $default_printer{ snmp_counter32_tag() }  = \&pretty_unsignedlike;
    $default_printer{ snmp_gauge32_tag() }    = \&pretty_unsignedlike;
    $default_printer{ snmp_counter64_tag() }  = \&pretty_unsignedlike;
    $default_printer{ snmp_uinteger32_tag() } = \&pretty_unsignedlike;
    $default_printer{ octet_string_tag() }    = \&pretty_string;
    $default_printer{ object_id_tag() }       = \&pretty_oid;
    $default_printer{ snmp_ip_address_tag() } = \&pretty_ip_address;

    %pretty_printer = %default_printer;
}

#### Encoding

sub encode_header ($$) {
    my ( $type, $length ) = @_;
    return pack( "CC", $type, $length ) if $length < 128;
    return pack( "CCC", $type, long_length | 1, $length ) if $length < 256;
    return pack( "CCn", $type, long_length | 2, $length ) if $length < 65536;
    return error("Cannot encode length $length yet");
}

=head2 encode_int_0() - encode the integer 0.

This is functionally identical to C<encode_int(0)>.

=cut

sub encode_int_0 () {
    return pack( "CCC", 2, 1, 0 );
}

=head2 encode_int() - encode an integer using the generic
    "integer" type tag.

=cut

sub encode_int ($) {
    return encode_intlike( $_[0], int_tag );
}

=head2 encode_uinteger32() - encode an integer using the SNMP
    UInteger32 tag.

=cut

sub encode_uinteger32 ($) {
    return encode_intlike( $_[0], snmp_uinteger32_tag );
}

=head2 encode_counter32() - encode an integer using the SNMP
    Counter32 tag.

=cut

sub encode_counter32 ($) {
    return encode_intlike( $_[0], snmp_counter32_tag );
}

=head2 encode_counter64() - encode an integer using the SNMP
    Counter64 tag.

=cut

sub encode_counter64 ($) {
    return encode_intlike( $_[0], snmp_counter64_tag );
}

=head2 encode_gauge32() - encode an integer using the SNMP Gauge32
    tag.

=cut

sub encode_gauge32 ($) {
    return encode_intlike( $_[0], snmp_gauge32_tag );
}

### encode_intlike ($int, $tag)
###
### Generic function to BER-encode an arbitrary integer using a given
### tag.  This function can handle large integers.  It doesn't check
### whether the integer is in a suitable range for the given type tag
### - that is expected to be done by the caller.
###
sub encode_intlike ($$) {
    my ( $int, $tag ) = @_;
    my ( $sign, $val, @vals );
    $sign = ( $int >= 0 ) ? 0 : 0xff;
    if ( ref $int && $int->isa("Math::BigInt") ) {
        for ( ; ; ) {
            $val = $int->copy()->bmod(256);
            unshift( @vals, $val );
            return encode_header( $tag, $#vals + 1 ) . pack( "C*", @vals )
              if ( $int >= -128 && $int < 128 );
            $int->bsub($sign)->bdiv(256);
        }
    }
    else {
        for ( ; ; ) {
            $val = $int & 0xff;
            unshift( @vals, $val );
            return encode_header( $tag, $#vals + 1 ) . pack( "C*", @vals )
              if ( $int >= -128 && $int < 128 );
            $int -= $sign, $int = int( $int / 256 );
        }
    }
}

=head2 encode_oid() - encode an object ID, passed as a list of
    sub-IDs.

    $encoded = encode_oid (1,3,6,1,...);
=cut

sub encode_oid (@) {
    my @oid = @_;
    my ( $result, $subid );

    $result = '';
    ## Ignore leading empty sub-ID.  The favourite reason for
    ## those to occur is that people cut&paste numeric OIDs from
    ## CMU/UCD SNMP including the leading dot.
    shift @oid if $oid[0] eq '';

    return error( "Object ID too short: ", join( '.', @oid ) )
      if $#oid < 1;
    ## The first two subids in an Object ID are encoded as a single
    ## byte in BER, according to a funny convention.  This poses
    ## restrictions on the ranges of those subids.  In the past, I
    ## didn't check for those.  But since so many people try to use
    ## OIDs in CMU/UCD SNMP's format and leave out the mib-2 or
    ## enterprises prefix, I introduced this check to catch those
    ## errors.
    ##
    return error( "first subid too big in Object ID ", join( '.', @oid ) )
      if $oid[0] > 2;
    $result = shift(@oid) * 40;
    $result += shift @oid;
    return error( "second subid too big in Object ID ", join( '.', @oid ) )
      if $result > 255;
    $result = pack( "C", $result );
    foreach $subid (@oid) {
        if ( ( $subid >= 0 ) && ( $subid < 128 ) ) {    #7 bits long subid
            $result .= pack( "C", $subid );
        }
        elsif ( ( $subid >= 128 ) && ( $subid < 16384 ) ) {  #14 bits long subid
            $result .= pack( "CC", 0x80 | $subid >> 7, $subid & 0x7f );
        }
        elsif ( ( $subid >= 16384 ) && ( $subid < 2097152 ) )
        {                                                    #21 bits long subid
            $result .= pack( "CCC",
                0x80 | ( ( $subid >> 14 ) & 0x7f ),
                0x80 | ( ( $subid >> 7 ) & 0x7f ),
                $subid & 0x7f );
        }
        elsif ( ( $subid >= 2097152 ) && ( $subid < 268435456 ) )
        {                                                    #28 bits long subid
            $result .= pack( "CCCC",
                0x80 | ( ( $subid >> 21 ) & 0x7f ),
                0x80 | ( ( $subid >> 14 ) & 0x7f ),
                0x80 | ( ( $subid >> 7 ) & 0x7f ),
                $subid & 0x7f );
        }
        elsif ( ( $subid >= 268435456 ) && ( $subid < 4294967296 ) )
        {                                                    #32 bits long subid
            $result .= pack(
                "CCCCC",
                0x80 | ( ( $subid >> 28 ) & 0x0f ),    #mask the bits beyond 32
                0x80 | ( ( $subid >> 21 ) & 0x7f ),
                0x80 | ( ( $subid >> 14 ) & 0x7f ),
                0x80 | ( ( $subid >> 7 ) & 0x7f ),
                $subid & 0x7f
            );
        }
        else {
            return error("Cannot encode subid $subid");
        }
    }
    encode_header( object_id_tag, length $result ) . $result;
}

=head2 encode_null() - encode a null object.

This is used e.g. in binding lists for variables that don't have a
value (yet)

=cut

sub encode_null () { encode_header( null_tag, 0 ); }

=head2 encode_sequence()

=head2 encode_tagged_sequence()

    $encoded = encode_sequence (encoded1, encoded2, ...);
    $encoded = encode_tagged_sequence (tag, encoded1, encoded2, ...);

Take already encoded values, and extend them to an encoded sequence.
C<encoded_sequence> uses the generic sequence tag, while with
C<encode_tagged_sequence> you can specify your own tag.
=cut

sub encode_sequence (@) { encode_tagged_sequence( sequence_tag, @_ ); }

sub encode_tagged_sequence ($@) {
    my ( $tag, $result );

    $tag = shift @_;
    $result = join '', @_;
    return encode_header( $tag | constructor_flag, length $result ) . $result;
}

=head2 encode_string() - encode a Perl string as an OCTET STRING.
=cut

sub encode_string ($) {
    my ($string) = @_;
    return encode_header( octet_string_tag, length $string ) . $string;
}

=head2 encode_ip_address() - encode an IPv4 address.

This can either be passed as a four-octet sequence in B<network byte
order>, or as a text string in dotted-quad notation,
e.g. "192.0.2.234".

=cut

sub encode_ip_address ($) {
    my ($addr) = @_;
    my @octets;

    if ( length $addr == 4 ) {
        ## Four bytes... let's suppose that this is a binary IP address
        ## in network byte order.
        return encode_header( snmp_ip_address_tag, length $addr ) . $addr;
    }
    elsif ( @octets = ( $addr =~ /^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/ ) )
    {
        return encode_ip_address( pack( "CCCC", @octets ) );
    }
    else {
        return error("IP address must be four bytes long or a dotted-quad");
    }
}

=head2 encode_timeticks() - encode an integer as a C<TimeTicks>
    object.

The integer should count hundredths of a second since the epoch
defined by C<sysUpTime.0>.

=cut

sub encode_timeticks ($) {
    my ($tt) = @_;
    return encode_intlike( $tt, snmp_timeticks_tag );
}

#### Decoding

=head2 pretty_print() - convert an encoded byte sequence into
    human-readable form.

This function can be extended by registering pretty-printing methods
for specific type codes.  Most BER type codes used in SNMP already
have such methods pre-registered by default.  See
C<register_pretty_printer> for how new methods can be added.

=cut

sub pretty_print ($) {
    my ($packet) = @_;
    return undef unless defined $packet;
    my $result = ord( substr( $packet, 0, 1 ) );
    if ( exists( $pretty_printer{$result} ) ) {
        return &{ $pretty_printer{$result} }($packet);
    }
    return (
        $pretty_print_timeticks
        ? pretty_uptime($packet)
        : pretty_unsignedlike($packet)
    ) if $result == uptime_tag;
    return "(null)" if $result == null_tag;
    return error("Exception code: noSuchObject")
      if $result == snmp_nosuchobject;
    return error("Exception code: noSuchInstance")
      if $result == snmp_nosuchinstance;
    return error("Exception code: endOfMibView")
      if $result == snmp_endofmibview;

    # IlvJa
    # pretty print sequences and their contents.

    my $ctx_cons_flags = context_flag | constructor_flag;

    if (
        $result == ( &constructor_flag | &sequence_tag )    # sequence
        || $result == ( 0 | $ctx_cons_flags )               #get_request
        || $result == ( 1 | $ctx_cons_flags )               #getnext_request
        || $result == ( 2 | $ctx_cons_flags )               #response
        || $result == ( 3 | $ctx_cons_flags )               #set_request
        || $result == ( 4 | $ctx_cons_flags )               #trap_request
        || $result == ( 5 | $ctx_cons_flags )               #getbulk_request
        || $result == ( 6 | $ctx_cons_flags )               #inform_request
        || $result == ( 7 | $ctx_cons_flags )               #trap2_request
      )
    {
        my $pretty_result = pretty_generic_sequence($packet);
        $pretty_result =~ s/^/    /gm;                      #Indent.

        my $seq_type_desc = {
            ( constructor_flag | sequence_tag ) => "Sequence",
            ( 0 | $ctx_cons_flags )             => "GetRequest",
            ( 1 | $ctx_cons_flags )             => "GetNextRequest",
            ( 2 | $ctx_cons_flags )             => "Response",
            ( 3 | $ctx_cons_flags )             => "SetRequest",
            ( 4 | $ctx_cons_flags )             => "Trap",
            ( 5 | $ctx_cons_flags )             => "GetBulkRequest",
            ( 6 | $ctx_cons_flags )             => "InformRequest",
            ( 7 | $ctx_cons_flags )             => "SNMPv2-Trap",
            ( 8 | $ctx_cons_flags )             => "Report",
        }->{ ($result) };

        return $seq_type_desc . "{\n" . $pretty_result . "\n}";
    }

    return sprintf( "#<unprintable BER type 0x%x>", $result );
}

sub pretty_using_decoder ($$) {
    my ( $decoder, $packet ) = @_;
    my ( $decoded, $rest );
    ( $decoded, $rest ) = &$decoder($packet);
    return error("Junk after object") unless $rest eq '';
    return $decoded;
}

sub pretty_string ($) {
    pretty_using_decoder( \&decode_string, $_[0] );
}

sub pretty_intlike ($) {
    my $decoded = pretty_using_decoder( \&decode_intlike, $_[0] );
    $decoded;
}

sub pretty_unsignedlike ($) {
    return pretty_using_decoder( \&decode_unsignedlike, $_[0] );
}

sub pretty_oid ($) {
    my ($oid) = shift;
    my ( $result, $subid, $next );
    my (@oid);
    $result = ord( substr( $oid, 0, 1 ) );
    return error("Object ID expected") unless $result == object_id_tag;
    ( $result, $oid ) = decode_length( $oid, 1 );
    return error("inconsistent length in OID") unless $result == length $oid;
    @oid = ();
    $subid = ord( substr( $oid, 0, 1 ) );
    push @oid, int( $subid / 40 );
    push @oid, $subid % 40;
    $oid = substr( $oid, 1 );

    while ( $oid ne '' ) {
        $subid = ord( substr( $oid, 0, 1 ) );
        if ( $subid < 128 ) {
            $oid = substr( $oid, 1 );
            push @oid, $subid;
        }
        else {
            $next  = $subid;
            $subid = 0;
            while ( $next >= 128 ) {
                $subid = ( $subid << 7 ) + ( $next & 0x7f );
                $oid = substr( $oid, 1 );
                $next = ord( substr( $oid, 0, 1 ) );
            }
            $subid = ( $subid << 7 ) + $next;
            $oid = substr( $oid, 1 );
            push @oid, $subid;
        }
    }
    join( '.', @oid );
}

sub pretty_uptime ($) {
    my ( $packet, $uptime );

    ( $uptime, $packet ) = &decode_unsignedlike(@_);
    pretty_uptime_value($uptime);
}

sub pretty_uptime_value ($) {
    my ($uptime) = @_;
    my ( $seconds, $minutes, $hours, $days, $result );
    ## We divide the uptime by hundred since we're not interested in
    ## sub-second precision.
    $uptime = int( $uptime / 100 );

    $days = int( $uptime / ( 60 * 60 * 24 ) );
    $uptime %= ( 60 * 60 * 24 );

    $hours = int( $uptime / ( 60 * 60 ) );
    $uptime %= ( 60 * 60 );

    $minutes = int( $uptime / 60 );
    $seconds = $uptime % 60;

    if ( $days == 0 ) {
        $result = sprintf( "%d:%02d:%02d", $hours, $minutes, $seconds );
    }
    elsif ( $days == 1 ) {
        $result =
          sprintf( "%d day, %d:%02d:%02d", $days, $hours, $minutes, $seconds );
    }
    else {
        $result =
          sprintf( "%d days, %d:%02d:%02d", $days, $hours, $minutes, $seconds );
    }
    return $result;
}

sub pretty_ip_address ($) {
    my $pdu = shift;
    my ( $length, $rest );
    return error( "IP Address tag (" . snmp_ip_address_tag . ") expected" )
      unless ord( substr( $pdu, 0, 1 ) ) == snmp_ip_address_tag;
    ( $length, $pdu ) = decode_length( $pdu, 1 );
    return error("Length of IP address should be four")
      unless $length == 4;
    sprintf "%d.%d.%d.%d", unpack( "CCCC", $pdu );
}

# IlvJa
# Returns a string with the pretty prints of all
# the elements in the sequence.
sub pretty_generic_sequence ($) {
    my ($pdu) = shift;

    my $rest;

    my $type = ord substr( $pdu, 0, 1 );
    my $flags = context_flag | constructor_flag;

    return error( sprintf( "Tag 0x%x is not a valid sequence tag", $type ) )
      unless (
        $type == ( &constructor_flag | &sequence_tag )    # sequence
        || $type == ( 0 | $flags )                        #get_request
        || $type == ( 1 | $flags )                        #getnext_request
        || $type == ( 2 | $flags )                        #response
        || $type == ( 3 | $flags )                        #set_request
        || $type == ( 4 | $flags )                        #trap_request
        || $type == ( 5 | $flags )                        #getbulk_request
        || $type == ( 6 | $flags )                        #inform_request
        || $type == ( 7 | $flags )                        #trap2_request
      );

    my $curelem;
    my $pretty_result;    # Holds the pretty printed sequence.
    my $pretty_elem;      # Holds the pretty printed current elem.
    my $first_elem = 'true';

    # Cut away the first Tag and Length from $packet and then
    # init $rest with that.
    ( undef, $rest ) = decode_length( $pdu, 1 );
    while ($rest) {
        ( $curelem, $rest ) = decode_generic_tlv($rest);
        $pretty_elem = pretty_print($curelem);

        $pretty_result .= "\n" if not $first_elem;
        $pretty_result .= $pretty_elem;

        # The rest of the iterations are not related to the
        # first element of the sequence so..
        $first_elem = '' if $first_elem;
    }
    return $pretty_result;
}

=head2 hex_string() - convert OCTET STRING to hexadecimal notation.

=cut

sub hex_string ($) {
    hex_string_of_type( $_[0], octet_string_tag );
}

=head2 hex_string_of_type() - convert octet string to hex, and check
type against given tag.

=cut

sub hex_string_of_type ($$) {
    my ( $pdu, $wanted_type ) = @_;
    my ($length);
    return error( "BER tag " . $wanted_type . " expected" )
      unless ord( substr( $pdu, 0, 1 ) ) == $wanted_type;
    ( $length, $pdu ) = decode_length( $pdu, 1 );
    hex_string_aux($pdu);
}

sub hex_string_aux ($) {
    my ($binary_string) = @_;
    my ( $c, $result );
    $result = '';
    for $c ( unpack "C*", $binary_string ) {
        $result .= sprintf "%02x", $c;
    }
    $result;
}

sub decode_oid ($) {
    my ($pdu) = @_;
    my ( $result, $pdu_rest );
    my (@result);
    $result = ord( substr( $pdu, 0, 1 ) );
    return error("Object ID expected") unless $result == object_id_tag;
    ( $result, $pdu_rest ) = decode_length( $pdu, 1 );
    return error("Short PDU")
      if $result > length $pdu_rest;
    @result = (
        substr( $pdu, 0, $result + ( length($pdu) - length($pdu_rest) ) ),
        substr( $pdu_rest, $result )
    );
    @result;
}

# IlvJa
# This takes a PDU and returns a two element list consisting of
# the first element found in the PDU (whatever it is) and the
# rest of the PDU
sub decode_generic_tlv ($) {
    my ($pdu) = @_;
    my (@result);
    my ( $elemlength, $pdu_rest ) = decode_length( $pdu, 1 );
    @result = (    # Extract the first element.
        substr( $pdu, 0, $elemlength + ( length($pdu) - length($pdu_rest) ) ),

        #Extract the rest of the PDU.
        substr( $pdu_rest, $elemlength )
    );
    @result;
}

=head2 decode_by_template() - decode complex object according to a
    template.

    ($var1, ...) = decode_by_template ($pdu, $template, ...);

The template can contain various %X directives.  Some directives
consume additional arguments following the template itself.  Most
directives will cause values to be returned.  The values are returned
as a sequence in the order of the directives that generated them.

=over 4

=item %{ - decode sequence.

This doesn't assign any return value, just checks and skips the
tag/length fields of the sequence.  By default, the tag should be the
generic sequence tag, but a tag can also be specified in the
directive.  The directive can either specify the tag as a prefix,
e.g. C<%99{> will require a sequence tag of 99, or if the directive is
given as C<%*{>, the tag will be taken from the next argument.

=item %s - decode string

=item %i - decode integer

=item %u - decode unsigned integer

=item %O - decode Object ID (OID)

=item %A - decode IPv4 address

=item %@ - assigns the remaining undecoded part of the PDU to the next
    return value.

=back

=cut

sub decode_by_template {
    my ($pdu) = shift;
    local ($_) = shift;
    return decode_by_template_2( $pdu, $_, 0, 0, @_ );
}

my $template_debug = 0;

sub decode_by_template_2 {
    my ( $pdu, $template, $pdu_index, $template_index );
    local ($_);
    $pdu            = shift;
    $template       = $_ = shift;
    $pdu_index      = shift;
    $template_index = shift;
    my (@results);
    my ( $length, $expected, $read, $rest );
    return undef unless defined $pdu;

    while ( 0 < length($_) ) {
        if ( substr( $_, 0, 1 ) eq '%' ) {
            print STDERR "template $_ ", length $pdu, " bytes remaining\n"
              if $template_debug;
            $_ = substr( $_, 1 );
            ++$template_index;
            if ( ($expected) = /^(\d+|\*|)\{(.*)/ ) {
                ## %{
                $template_index += length($expected) + 1;
                print STDERR "%{\n" if $template_debug;
                $_        = $2;
                $expected = shift | constructor_flag if ( $expected eq '*' );
                $expected = sequence_tag | constructor_flag
                  if $expected eq '';
                return template_error( "Unexpected end of PDU",
                    $template, $template_index )
                  if !defined $pdu or $pdu eq '';
                return template_error(
                    "Expected sequence tag $expected, got "
                      . ord( substr( $pdu, 0, 1 ) ),
                    $template,
                    $template_index
                ) unless ( ord( substr( $pdu, 0, 1 ) ) == $expected );
                ( $length, $pdu ) = decode_length( $pdu, 1 )
                  or return template_error( "cannot read length",
                    $template, $template_index );
                return template_error(
                    "Expected length $length, got " . length $pdu,
                    $template, $template_index )
                  unless length $pdu == $length;
            }
            elsif ( ( $expected, $rest ) = /^(\*|)s(.*)/ ) {
                ## %s
                $template_index += length($expected) + 1;
                ( $expected = shift ) if $expected eq '*';
                ( $read, $pdu ) = decode_string($pdu)
                  or return template_error( "cannot read string",
                    $template, $template_index );
                print STDERR "%s => $read\n" if $template_debug;
                if ( $expected eq '' ) {
                    push @results, $read;
                }
                else {
                    return template_error( "Expected $expected, read $read",
                        $template, $template_index )
                      unless $expected eq $read;
                }
                $_ = $rest;
            }
            elsif ( ($rest) = /^A(.*)/ ) {
                ## %A
                $template_index += 1;
                {
                    my ( $tag, $length, $value );
                    $tag = ord( substr( $pdu, 0, 1 ) );
                    return error( "Expected IP address, got tag " . $tag )
                      unless $tag == snmp_ip_address_tag;
                    ( $length, $pdu ) = decode_length( $pdu, 1 );
                    return error("Inconsistent length of InetAddress encoding")
                      if $length > length $pdu;
                    return template_error( "IP address must be four bytes long",
                        $template, $template_index )
                      unless $length == 4;
                    $read = substr( $pdu, 0, $length );
                    $pdu = substr( $pdu, $length );
                }
                print STDERR "%A => $read\n" if $template_debug;
                push @results, $read;
                $_ = $rest;
            }
            elsif (/^O(.*)/) {
                ## %O
                $template_index += 1;
                $_ = $1;
                ( $read, $pdu ) = decode_oid($pdu)
                  or return template_error( "cannot read OID",
                    $template, $template_index );
                print STDERR "%O => " . pretty_oid($read) . "\n"
                  if $template_debug;
                push @results, $read;
            }
            elsif ( ( $expected, $rest ) = /^(\d+|\*|)i(.*)/ ) {
                ## %i
                $template_index += length($expected) + 1;
                print STDERR "%i\n" if $template_debug;
                $_ = $rest;
                ( $read, $pdu ) = decode_int($pdu)
                  or return template_error( "cannot read int",
                    $template, $template_index );
                if ( $expected eq '' ) {
                    push @results, $read;
                }
                else {
                    $expected = int(shift) if $expected eq '*';
                    return template_error(
                        sprintf(
                            "Expected %d (0x%x), got %d (0x%x)",
                            $expected, $expected, $read, $read
                        ),
                        $template,
                        $template_index
                    ) unless ( $expected == $read );
                }
            }
            elsif ( ($rest) = /^u(.*)/ ) {
                ## %u
                $template_index += 1;
                print STDERR "%u\n" if $template_debug;
                $_ = $rest;
                ( $read, $pdu ) = decode_unsignedlike($pdu)
                  or return template_error( "cannot read uptime",
                    $template, $template_index );
                push @results, $read;
            }
            elsif (/^\@(.*)/) {
                ## %@
                $template_index += 1;
                print STDERR "%@\n" if $template_debug;
                $_ = $1;
                push @results, $pdu;
                $pdu = '';
            }
            else {
                return template_error(
                    "Unknown decoding directive in template: $_",
                    $template, $template_index );
            }
        }
        else {
            if ( substr( $_, 0, 1 ) ne substr( $pdu, 0, 1 ) ) {
                return template_error(
                    "Expected "
                      . substr( $_, 0, 1 )
                      . ", got "
                      . substr( $pdu, 0, 1 ),
                    $template, $template_index
                );
            }
            $_   = substr( $_,   1 );
            $pdu = substr( $pdu, 1 );
        }
    }
    return template_error( "PDU too long", $template, $template_index )
      if length($pdu) > 0;
    return template_error( "PDU too short", $template, $template_index )
      if length($_) > 0;
    @results;
}

=head2 decode_sequence() - Split sequence into components.

    ($first, $rest) = decode_sequence ($pdu);

Checks whether the PDU has a sequence type tag and a plausible length
field.  Splits the initial element off the list, and returns both this
and the remainder of the PDU.

=cut

sub decode_sequence ($) {
    my ($pdu) = @_;
    my ($result);
    my (@result);
    $result = ord( substr( $pdu, 0, 1 ) );
    return error("Sequence expected")
      unless $result == ( sequence_tag | constructor_flag );
    ( $result, $pdu ) = decode_length( $pdu, 1 );
    return error("Short PDU")
      if $result > length $pdu;
    @result = ( substr( $pdu, 0, $result ), substr( $pdu, $result ) );
    @result;
}

sub decode_int ($) {
    my ($pdu) = @_;
    my $tag = ord( substr( $pdu, 0, 1 ) );
    return error( "Integer expected, found tag " . $tag )
      unless $tag == int_tag;
    decode_intlike($pdu);
}

sub decode_intlike ($) {
    decode_intlike_s( $_[0], 1 );
}

sub decode_unsignedlike ($) {
    decode_intlike_s( $_[0], 0 );
}

my $have_math_bigint_p = 0;

sub decode_intlike_s ($$) {
    my ( $pdu, $signedp ) = @_;
    my ( $length, $result );
    ( $length, $pdu ) = decode_length( $pdu, 1 );
    my $ptr = 0;
    $result = unpack( $signedp ? "c" : "C", substr( $pdu, $ptr++, 1 ) );
    if ( $length > 5 || ( $length == 5 && $result > 0 ) ) {
        require 'Math/BigInt.pm' unless $have_math_bigint_p++;
        $result = new Math::BigInt($result);
    }
    while ( --$length > 0 ) {
        $result *= 256;
        $result += unpack( "C", substr( $pdu, $ptr++, 1 ) );
    }
    ( $result, substr( $pdu, $ptr ) );
}

sub decode_string ($) {
    my ($pdu) = shift;
    my ($result);
    $result = ord( substr( $pdu, 0, 1 ) );
    return error( "Expected octet string, got tag " . $result )
      unless $result == octet_string_tag;
    ( $result, $pdu ) = decode_length( $pdu, 1 );
    return error("Short PDU")
      if $result > length $pdu;
    return ( substr( $pdu, 0, $result ), substr( $pdu, $result ) );
}

sub decode_length ($@) {
    my ($pdu) = shift;
    my $index = shift || 0;
    my ($result);
    my (@result);
    $result = ord( substr( $pdu, $index, 1 ) );
    if ( $result & long_length ) {
        if ( $result == ( long_length | 1 ) ) {
            @result = (
                ord( substr( $pdu, $index + 1, 1 ) ),
                substr( $pdu, $index + 2 )
            );
        }
        elsif ( $result == ( long_length | 2 ) ) {
            @result = (
                ( ord( substr( $pdu, $index + 1, 1 ) ) << 8 ) +
                  ord( substr( $pdu, $index + 2, 1 ) ),
                substr( $pdu, $index + 3 )
            );
        }
        else {
            return error("Unsupported length");
        }
    }
    else {
        @result = ( $result, substr( $pdu, $index + 1 ) );
    }
    @result;
}

=head2 register_pretty_printer() - register pretty-printing methods for
    typecodes.

This function takes a hashref that specifies functions to call when
the specified value type is being printed.  It returns the number of
functions that were registered.
=cut

sub register_pretty_printer($) {
    my ($h_ref) = shift;
    my ( $type, $val, $cnt );

    $cnt = 0;
    while ( ( $type, $val ) = each %$h_ref ) {
        if ( ref $val eq "CODE" ) {
            $pretty_printer{$type} = $val;
            $cnt++;
        }
    }
    return ($cnt);
}

# This takes a hashref that specifies functions to call when
# the specified value type is being printed.  It removes the
# functions from the list for the types specified.
# It returns the number of functions that were unregistered.
sub unregister_pretty_printer($) {
    my ($h_ref) = shift;
    my ( $type, $val, $cnt );

    $cnt = 0;
    while ( ( $type, $val ) = each %$h_ref ) {
        if (   ( exists( $pretty_printer{$type} ) )
            && ( $pretty_printer{$type} == $val ) )
        {
            if ( exists( $default_printer{$type} ) ) {
                $pretty_printer{$type} = $default_printer{$type};
            }
            else {
                delete $pretty_printer{$type};
            }
            $cnt++;
        }
    }
    return ($cnt);
}

#### OID prefix check

### encoded_oid_prefix_p OID1 OID2
###
### OID1 and OID2 should be BER-encoded OIDs.
### The function returns non-zero iff OID1 is a prefix of OID2.
### This can be used in the termination condition of a loop that walks
### a table using GetNext or GetBulk.
###
sub encoded_oid_prefix_p ($$) {
    my ( $oid1, $oid2 ) = @_;
    my ( $i1,   $i2 );
    my ( $l1,   $l2 );
    my ( $subid1, $subid2 );
    return error("OID tag expected")
      unless ord( substr( $oid1, 0, 1 ) ) == object_id_tag;
    return error("OID tag expected")
      unless ord( substr( $oid2, 0, 1 ) ) == object_id_tag;
    ( $l1, $oid1 ) = decode_length( $oid1, 1 );
    ( $l2, $oid2 ) = decode_length( $oid2, 1 );

    for ( $i1 = 0, $i2 = 0 ; $i1 < $l1 && $i2 < $l2 ; ++$i1, ++$i2 ) {
        ( $subid1, $i1 ) = &decode_subid( $oid1, $i1, $l1 );
        ( $subid2, $i2 ) = &decode_subid( $oid2, $i2, $l2 );
        return 0 unless $subid1 == $subid2;
    }
    return $i2 if $i1 == $l1;
    return 0;
}

### decode_subid OID INDEX
###
### Decodes a subid field from a BER-encoded object ID.
### Returns two values: the field, and the index of the last byte that
### was actually decoded.
###
sub decode_subid ($$$) {
    my ( $oid, $i, $l ) = @_;
    my $subid = 0;
    my $next;

    while ( ( $next = ord( substr( $oid, $i, 1 ) ) ) >= 128 ) {
        $subid = ( $subid << 7 ) + ( $next & 0x7f );
        ++$i;
        return error("decoding object ID: short field")
          unless $i < $l;
    }
    return ( ( $subid << 7 ) + $next, $i );
}

sub error (@) {
    $errmsg = join( "", @_ );
    return undef;
}

sub template_error ($$$) {
    my ( $errmsg, $template, $index ) = @_;
    return error(
        $errmsg . "\n  " . $template . "\n  " . ( ' ' x $index ) . "^" );
}

1;

=head1 AUTHORS

Created by:  Simon Leinen  E<lt>simon.leinen@switch.chE<gt>

Contributions and fixes by:

=over

=item Andrzej Tobola E<lt>san@iem.pw.edu.plE<gt>:  Added long String decode

=item Tobias Oetiker E<lt>tobi@oetiker.chE<gt>:  Added 5 Byte Integer decode ...

=item Dave Rand E<lt>dlr@Bungi.comE<gt>:  Added C<SysUpTime> decode

=item Philippe Simonet E<lt>sip00@vg.swissptt.chE<gt>:  Support larger subids

=item Yufang HU E<lt>yhu@casc.comE<gt>:  Support even larger subids

=item Mike Mitchell E<lt>Mike.Mitchell@sas.comE<gt>: New generalized C<encode_int()>

=item Mike Diehn E<lt>mdiehn@mindspring.netE<gt>: C<encode_ip_address()>

=item Rik Hoorelbeke E<lt>rik.hoorelbeke@pandora.beE<gt>: C<encode_oid()> fix

=item Brett T Warden E<lt>wardenb@eluminant.comE<gt>: pretty C<UInteger32>

=item Bert Driehuis E<lt>driehuis@playbeing.orgE<gt>: Handle SNMPv2 exception codes

=item Jakob Ilves (/IlvJa) E<lt>jakob.ilves@oracle.comE<gt>: PDU decoding

=item Jan Kasprzak E<lt>kas@informatics.muni.czE<gt>: Fix for PDU syntax check

=item Milen Pavlov E<lt>milen@batmbg.comE<gt>: Recognize variant length for ints

=back

=head1 COPYRIGHT

Copyright (c) 1995-2009, Simon Leinen.

This program is free software; you can redistribute it under the
"Artistic License 2.0" included in this distribution (file "Artistic").

=cut
