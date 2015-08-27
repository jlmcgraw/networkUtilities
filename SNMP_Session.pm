### -*- mode: Perl -*-
######################################################################
### SNMP Request/Response Handling
######################################################################
### Copyright (c) 1995-2009, Simon Leinen.
###
### This program is free software; you can redistribute it under the
### "Artistic License 2.0" included in this distribution
### (file "Artistic").
######################################################################
### Created by: See AUTHORS below
######################################################################

package SNMP_Session;

=head1 NAME

SNMP_Session - SNMPv1/v2 Protocol Handling

=head1 SYNOPSIS

    use SNMP_Session;
    $session = SNMP_Session->open ($host, $community, $port)
	or die "couldn't open SNMP session to $host";
    if ($session->get_request_response ($oid1, $oid2, ...)) {
	($bindings) = $session->decode_get_response ($session->{pdu_buffer});
	while ($bindings ne '') {
	    ($binding,$bindings) = decode_sequence ($bindings);
	    ($oid,$value) = decode_by_template ($binding, "%O%@");
	    print pretty_print ($oid)," => ", pretty_print ($value), "\n";
	}
    } else {
	die "No response from agent on $host";
    }

=cut

require 5.002;

use strict;
use Exporter;
use vars qw(@ISA $VERSION @EXPORT $errmsg
  $suppress_warnings
  $default_avoid_negative_request_ids
  $default_use_16bit_request_ids);
use Socket;
use BER '1.05';
use Carp;

sub map_table ($$$ );
sub map_table_4 ($$$$);
sub map_table_start_end ($$$$$$);
sub index_compare ($$);
sub oid_diff ($$);

$VERSION = '1.14';

@ISA = qw(Exporter);

@EXPORT =
  qw(errmsg suppress_warnings index_compare oid_diff recycle_socket ipv6available);

=head1 VARIABLES

The C<default_...> variables all specify default values that are used
for C<SNMP_Session> objects when no other value is specified.  These
values can be overridden on a per-session basis, for example by
passing additional arguments to the constructor.

=cut

my $default_debug = 0;

### Default values for the TIMEOUT, RETRIES, and BACKOFF slots of
### SNMP_Session objects - see their documentation below.
###
my $default_timeout = 2.0;
my $default_retries = 5;
my $default_backoff = 1.0;

=head2 $default_max_repetitions - default value for C<maxRepetitions>.

This specifies how many table rows are requested in C<getBulk>
requests.  Used when walking tables using C<getBulk> (only available
in SNMPv2(c) and later).  If this is too small, then a table walk will
need unnecessarily many request/response exchanges.  If it is too big,
the agent may compute many variables after the end of the table.  It
is recommended to set this explicitly for each table walk by using
C<map_table_4()>.

=cut

my $default_max_repetitions = 12;

=head2 $default avoid_negative_request_ids - default value for
    C<avoid_negative_request_ids>.

Set this to non-zero if you have agents that have trouble with
negative request IDs, and don't forget to complain to your agent
vendor.  According to the spec (RFC 1905), the request-id is an
C<Integer32>, i.e. its range is from -(2^31) to (2^31)-1.  However,
some agents erroneously encode the response ID as an unsigned, which
prevents this code from matching such responses to requests.

=cut

$SNMP_Session::default_avoid_negative_request_ids = 0;

=head2 $default_use_16bit_request_ids - default value for C<use_16bit_request_ids>.

Set this to non-zero if you have agents that use 16bit request IDs,
and don't forget to complain to your agent vendor.

=cut

$SNMP_Session::default_use_16bit_request_ids = 0;

### Whether all SNMP_Session objects should share a single UDP socket.
###
$SNMP_Session::recycle_socket = 0;

### IPv6 initialization code: check that IPv6 libraries are available,
### and if so load them.

### We store the length of an IPv6 socket address structure in the class
### so we can determine if a socket address is IPv4 or IPv6 just by checking
### its length. The proper way to do this would be to use sockaddr_family(),
### but this function is only available in recent versions of Socket.pm.
my $ipv6_addr_len;

### Flags to be passed to recv() when non-blocking behavior is
### desired.  On most POSIX-like systems this will be set to
### MSG_DONTWAIT, on other systems we leave it at zero.
###
my $dont_wait_flags;

BEGIN {
    $ipv6_addr_len               = undef;
    $SNMP_Session::ipv6available = 0;
    $dont_wait_flags             = 0;

    if (
        eval { local $SIG{__DIE__}; require Socket6; } && eval {
            local $SIG{__DIE__};
            require IO::Socket::INET6;
            IO::Socket::INET6->VERSION("1.26");
        }
      )
    {
        import Socket6;
        $ipv6_addr_len =
          length( pack_sockaddr_in6( 161, inet_pton( AF_INET6(), "::1" ) ) );
        $SNMP_Session::ipv6available = 1;
    }
    eval
      'local $SIG{__DIE__};local $SIG{__WARN__};$dont_wait_flags = MSG_DONTWAIT();';
}

### Cache for reusable sockets.  This is indexed by socket (address)
### family, so that we don't try to reuse an IPv4 socket for IPv6 or
### vice versa.
###
my %the_socket = ();

=head2 $errmsg - error message from last failed operation.

When they encounter errors, the routines in this module will generally
return C<undef>) and leave an informative error message in C<$errmsg>).

=cut

$SNMP_Session::errmsg = '';

=head2 $suppress_warnings - whether warnings should be suppressed.

If this variable is zero, as is the default, this code will output
informative error messages whenever it encounters an error.  Set this
to a non-zero value if you want to suppress these messages.  In any
case, the last error message can be found in C<$errmsg>.

=cut

$SNMP_Session::suppress_warnings = 0;

=head1 METHODS in package SNMP_Session

The abstract class C<SNMP_Session> defines objects that can be used to
communicate with SNMP entities.  It has methods to send requests to
and receive responses from an agent.

Two instantiable subclasses are defined: C<SNMPv1_Session> implements
SNMPv1 (RFC 1157) functionality C<SNMPv2c_Session> implements
community-based SNMPv2 (RFC 3410-3417).

=cut

sub get_request     { 0 | context_flag() }
sub getnext_request { 1 | context_flag() }
sub get_response    { 2 | context_flag() }
sub set_request     { 3 | context_flag() }
sub trap_request    { 4 | context_flag() }
sub getbulk_request { 5 | context_flag() }
sub inform_request  { 6 | context_flag() }
sub trap2_request   { 7 | context_flag() }

sub standard_udp_port { 161 }

=head2 open() - create an SNMP session object

    $session = SNMP_Session->open
      ($host, $community, $port,
       $max_pdu_len, $local_port, $max_repetitions,
       $local_host, $ipv4only);

The calling and return conventions are identical to
C<SNMPv1_Session::open()>.

=cut

sub open {
    return SNMPv1_Session::open(@_);
}

=head2 timeout() - return timeout value.

Initial timeout, in seconds, to wait for a response PDU after a
request is sent.  Note that when a request is retried, the timeout is
increased by B<backoff> (see below).  The standard value is 2.0
(seconds).

=cut

sub timeout { $_[0]->{timeout} }

=head2 retries() - number of attempts to get a reply.

Maximum number of attempts to get a reply for an SNMP request.  If no
response is received after B<timeout> seconds, the request is resent
and a new response awaited with a longer timeout, see the
documentation on B<backoff> below.  The B<retries> value should be at
least 1, because the first attempt counts, too (the name "retries" is
confusing, sorry for that).

=cut

sub retries { $_[0]->{retries} }

=head2 backoff() - backoff factor.for timeout on successive retries.

Default backoff factor for C<SNMP_Session> objects.  This factor is
used to increase the TIMEOUT every time an SNMP request is retried.
The standard value is 1.0, which means the same timeout is used for
all attempts.

=cut

sub backoff { $_[0]->{backoff} }

=head2 set_timeout() - set initial timeout for session

=head2 set_retries() - set maximum number of attempts for session

=head2 set_backoff() - set backoff factor for session

Example usage:

    $session->set_backoff (1.5);

=cut

sub set_timeout {
    my ( $session, $timeout ) = @_;
    croak("timeout ($timeout) must be a positive number") unless $timeout > 0.0;
    $session->{'timeout'} = $timeout;
}

sub set_retries {
    my ( $session, $retries ) = @_;
    croak("retries ($retries) must be a non-negative integer")
      unless $retries == int($retries) && $retries >= 0;
    $session->{'retries'} = $retries;
}

sub set_backoff {
    my ( $session, $backoff ) = @_;
    croak("backoff ($backoff) must be a number >= 1.0")
      unless $backoff == int($backoff) && $backoff >= 1.0;
    $session->{'backoff'} = $backoff;
}

sub encode_request_3 ($$$@) {
    my ( $this, $reqtype, $encoded_oids_or_pairs, $i1, $i2 ) = @_;
    my ($request);
    local ($_);

    $this->{request_id} =
      ( $this->{request_id} == 0x7fffffff )
      ? -0x80000000
      : $this->{request_id} + 1;
    $this->{request_id} += 0x80000000
      if ( $this->{avoid_negative_request_ids} && $this->{request_id} < 0 );
    $this->{request_id} &= 0x0000ffff
      if ( $this->{use_16bit_request_ids} );
    foreach $_ ( @{$encoded_oids_or_pairs} ) {
        if ( ref($_) eq 'ARRAY' ) {
            $_ = &encode_sequence( $_->[0], $_->[1] )
              || return $this->ber_error("encoding pair");
        }
        else {
            $_ = &encode_sequence( $_, encode_null() )
              || return $this->ber_error("encoding value/null pair");
        }
    }
    $request = encode_tagged_sequence(
        $reqtype,
        encode_int( $this->{request_id} ),
        defined $i1 ? encode_int($i1) : encode_int_0(),
        defined $i2 ? encode_int($i2) : encode_int_0(),
        encode_sequence( @{$encoded_oids_or_pairs} )
    ) || return $this->ber_error("encoding request PDU");
    return $this->wrap_request($request);
}

sub encode_get_request {
    my ( $this, @oids ) = @_;
    return encode_request_3( $this, get_request, \@oids );
}

sub encode_getnext_request {
    my ( $this, @oids ) = @_;
    return encode_request_3( $this, getnext_request, \@oids );
}

sub encode_getbulk_request {
    my ( $this, $non_repeaters, $max_repetitions, @oids ) = @_;
    return encode_request_3( $this, getbulk_request, \@oids,
        $non_repeaters, $max_repetitions );
}

sub encode_set_request {
    my ( $this, @encoded_pairs ) = @_;
    return encode_request_3( $this, set_request, \@encoded_pairs );
}

sub encode_trap_request ($$$$$$@) {
    my ( $this, $ent, $agent, $gen, $spec, $dt, @pairs ) = @_;
    my ($request);
    local ($_);

    foreach $_ (@pairs) {
        if ( ref($_) eq 'ARRAY' ) {
            $_ = &encode_sequence( $_->[0], $_->[1] )
              || return $this->ber_error("encoding pair");
        }
        else {
            $_ = &encode_sequence( $_, encode_null() )
              || return $this->ber_error("encoding value/null pair");
        }
    }
    $request =
      encode_tagged_sequence( trap_request, $ent, $agent, $gen, $spec, $dt,
        encode_sequence(@pairs) )
      || return $this->ber_error("encoding trap PDU");
    return $this->wrap_request($request);
}

sub encode_v2_trap_request ($@) {
    my ( $this, @pairs ) = @_;

    return encode_request_3( $this, trap2_request, \@pairs );
}

sub decode_get_response {
    my ( $this, $response ) = @_;
    my @rest;
    @{ $this->{'unwrapped'} };
}

sub wait_for_response {
    my ($this) = shift;
    my ($timeout) = shift || 10.0;
    my ( $rin, $win, $ein ) = ( '', '', '' );
    my ( $rout, $wout, $eout );
    vec( $rin, $this->sockfileno, 1 ) = 1;
    select( $rout = $rin, $wout = $win, $eout = $ein, $timeout );
}

=head2 ..._request_response() - Send some request and receive response.

Encodes a specific SNMP request, sends it to the destination address
of the session, and waits for a matching response.  If such a response
is received, this function will return the size of the response, which
is necessarily greater than zero.

An undefined value is returned if some error happens during encoding
or sending, or if no matching response is received after the
wait/retry schedule is exhausted.  See the documentation on the
C<timeout()>, C<retries()>, and C<backoff()> methods on how the
wait/retry logic works.

=head2 get_request_response() - Send C<get> request and receive response.

=head2 getnext_request_response() - Send C<get-next> request and receive response.

    $result = $session->get_request_response (@encoded_oids);
    $result = $session->getnext_request_response (@encoded_oids);

=cut

sub get_request_response ($@) {
    my ( $this, @oids ) = @_;
    return $this->request_response_5( $this->encode_get_request(@oids),
        get_response, \@oids, 1 );
}

sub getnext_request_response ($@) {
    my ( $this, @oids ) = @_;
    return $this->request_response_5( $this->encode_getnext_request(@oids),
        get_response, \@oids, 1 );
}

=head2 set_request_response() - Send C<set> request and receive response.

    $result = $session->set_request_response (@encoded_pair_list);

This method takes its arguments in a different form; they are a list
of pairs - references to two-element arrays - which respresent the
variables to be set and the intended values, e.g.

    ([$encoded_oid_0, $encoded_value_0],
     [$encoded_oid_1, $encoded_value_1],
     [$encoded_oid_2, $encoded_value_2], ...)

=cut

sub set_request_response ($@) {
    my ( $this, @pairs ) = @_;
    return $this->request_response_5( $this->encode_set_request(@pairs),
        get_response, \@pairs, 1 );
}

sub getbulk_request_response ($$$@) {
    my ( $this, $non_repeaters, $max_repetitions, @oids ) = @_;
    return $this->request_response_5(
        $this->encode_getbulk_request(
            $non_repeaters, $max_repetitions, @oids
        ),
        get_response,
        \@oids,
        1
    );
}

=head2 trap_request_send() - send SNMPv1 Trap.

    $result = $session->trap_request_send ($ent, $gent, $gen, $spec, $dt, @pairs);

=cut

sub trap_request_send ($$$$$$@) {
    my ( $this, $ent, $agent, $gen, $spec, $dt, @pairs ) = @_;
    my ($req);

    $req = $this->encode_trap_request( $ent, $agent, $gen, $spec, $dt, @pairs );
    ## Encoding may have returned an error.
    return undef unless defined $req;
    $this->send_query($req)
      || return $this->error("send_trap: $!");
    return 1;
}

=head2 v2_trap_request_send() - send SNMPv2 Trap.

    $result = $session->v2_trap_request_send ($trap_oid, $dt, @pairs);

=cut

sub v2_trap_request_send ($$$@) {
    my ( $this, $trap_oid, $dt, @pairs ) = @_;
    my @sysUptime_OID = ( 1, 3, 6, 1, 2, 1, 1, 3 );
    my @snmpTrapOID_OID = ( 1, 3, 6, 1, 6, 3, 1, 1, 4, 1 );
    my ($req);

    unshift @pairs,
      [ encode_oid( @snmpTrapOID_OID, 0 ), encode_oid( @{$trap_oid} ) ];
    unshift @pairs, [ encode_oid( @sysUptime_OID, 0 ), encode_timeticks($dt) ];
    $req = $this->encode_v2_trap_request(@pairs);
    ## Encoding may have returned an error.
    return undef unless defined $req;
    $this->send_query($req)
      || return $this->error("send_trap: $!");
    return 1;
}

sub request_response_5 ($$$$$) {
    my ( $this, $req, $response_tag, $oids, $errorp ) = @_;
    my $retries = $this->retries;
    my $timeout = $this->timeout;
    my ( $nfound, $timeleft );

    ## Encoding may have returned an error.
    return undef unless defined $req;

    $timeleft = $timeout;
    while ( $retries > 0 ) {
        $this->send_query($req)
          || return $this->error("send_query: $!");

        # IlvJa
        # Add request pdu to capture_buffer
        push @{ $this->{'capture_buffer'} }, $req
          if ( defined $this->{'capture_buffer'}
            and ref $this->{'capture_buffer'} eq 'ARRAY' );
        #
      wait_for_response:
        ( $nfound, $timeleft ) = $this->wait_for_response($timeleft);
        if ( $nfound > 0 ) {
            my ($response_length);

            $response_length =
              $this->receive_response_3( $response_tag, $oids, $errorp, 1 );
            if ($response_length) {

                # IlvJa
                # Add response pdu to capture_buffer
                push(
                    @{ $this->{'capture_buffer'} },
                    substr( $this->{'pdu_buffer'}, 0, $response_length )
                  )
                  if ( defined $this->{'capture_buffer'}
                    and ref $this->{'capture_buffer'} eq 'ARRAY' );
                #
                return $response_length;
            }
            elsif ( defined($response_length) ) {
                goto wait_for_response;

                # A response has been received, but for a different
                # request ID or from a different IP address.
            }
            else {
                return undef;
            }
        }
        else {
            ## No response received - retry
            --$retries;
            $timeout *= $this->backoff;
            $timeleft = $timeout;
        }
    }

    # IlvJa
    # Add empty packet to capture_buffer
    push @{ $this->{'capture_buffer'} }, ""
      if ( defined $this->{'capture_buffer'}
        and ref $this->{'capture_buffer'} eq 'ARRAY' );
    #
    return $this->error("no response received");
}

=head2 map_table() - traverse an SNMP table.

    $result = $session->map_table ([$col0, $col1, ...], $mapfn);

This will call the provided function (C<&$mapfn>) once for each row of
the table defined by the column OIDs C<$col0>, C<$col1>...  If the
session can handle SNMPv2 operations, C<get-bulk> will be used to
traverse the table.  Otherwise, C<get-next> will be used.

If the first argument is a list of I<n> columns, the mapping function
will be called with I<n+1> arguments.  The first argument will be the
row index, i.e. the list of sub-IDs that was appended to the provided
column OIDs for this row.  Note that the row index will be represented
as a string, using dot-separated numerical OID notation.

The remaining arguments to the mapping function will be the values of
each column at the current index.  It is possible that the table has
"holes", i.e. that for a given row index, not all columns have a
value.  For columns with no value at the current row index, C<undef>
will be passed to the mapping function.

If an error is encountered at any point during the table traversal,
this method will return undef and leave an error message in C<$errmsg>
(which is also written out unless C<$suppress_warnings> is non-zero).

Otherwise, the function will return the number of rows traversed,
i.e. the number of times that the mapping function has been called.

=cut

sub map_table ($$$) {
    my ( $session, $columns, $mapfn ) = @_;
    return $session->map_table_4( $columns, $mapfn,
        $session->default_max_repetitions() );
}

=head2 map_table_4() - traverse an SNMP table with more control.

=cut

sub map_table_4 ($$$$) {
    my ( $session, $columns, $mapfn, $max_repetitions ) = @_;
    return $session->map_table_start_end( $columns, $mapfn, "", undef,
        $max_repetitions );
}

=head2 map_table_start_end() - traverse an SNMP table with lower/upper index limits.

    $result = $session->map_table_start_end ($columns, $mapfn,
        $start, $end, $max_repetition);

Similar to C<map_table_4()>, except that the start and end index can
be specified.

=cut

sub map_table_start_end ($$$$$$) {
    my ( $session, $columns, $mapfn, $start, $end, $max_repetitions ) = @_;

    my @encoded_oids;
    my $call_counter = 0;
    my $base_index   = $start;

    do {
        foreach ( @encoded_oids = @{$columns} ) {
            $_ = encode_oid( @{$_}, split '\.', $base_index )
              || return $session->ber_error("encoding OID $base_index");
        }
        if ( $session->getnext_request_response(@encoded_oids) ) {
            my $response         = $session->pdu_buffer;
            my ($bindings)       = $session->decode_get_response($response);
            my $smallest_index   = undef;
            my @collected_values = ();

            my @bases = @{$columns};
            while ( $bindings ne '' ) {
                my ( $binding, $oid, $value );
                my $base = shift @bases;
                ( $binding, $bindings ) = decode_sequence($bindings);
                ( $oid, $value ) = decode_by_template( $binding, "%O%@" );

                my $out_index;

                $out_index = oid_diff( $base, $oid );
                my $cmp;
                if ( !defined $smallest_index
                    || ( $cmp = index_compare( $out_index, $smallest_index ) )
                    == -1 )
                {
                    $smallest_index = $out_index;
                    grep ( $_ = undef, @collected_values );
                    push @collected_values, $value;
                }
                elsif ( $cmp == 1 ) {
                    push @collected_values, undef;
                }
                else {
                    push @collected_values, $value;
                }
            }
            ( ++$call_counter, &$mapfn( $smallest_index, @collected_values ) )
              if defined $smallest_index;
            $base_index = $smallest_index;
        }
        else {
            return undef;
        }
      } while ( defined $base_index
        && ( !defined $end || index_compare( $base_index, $end ) < 0 ) );
    $call_counter;
}

sub index_compare ($$) {
    my ( $i1, $i2 ) = @_;
    $i1 = '' unless defined $i1;
    $i2 = '' unless defined $i2;
    if ( $i1 eq '' ) {
        return $i2 eq '' ? 0 : 1;
    }
    elsif ( $i2 eq '' ) {
        return 1;
    }
    elsif ( !$i1 ) {
        return $i2 eq '' ? 1 : !$i2 ? 0 : 1;
    }
    elsif ( !$i2 ) {
        return -1;
    }
    else {
        my ( $f1, $r1 ) = split( '\.', $i1, 2 );
        my ( $f2, $r2 ) = split( '\.', $i2, 2 );

        if ( $f1 < $f2 ) {
            return -1;
        }
        elsif ( $f1 > $f2 ) {
            return 1;
        }
        else {
            return index_compare( $r1, $r2 );
        }
    }
}

sub oid_diff ($$) {
    my ( $base, $full ) = @_;
    my $base_dotnot = join( '.', @{$base} );
    my $full_dotnot = BER::pretty_oid($full);

    return undef
      unless substr( $full_dotnot, 0, length $base_dotnot ) eq $base_dotnot
      && substr( $full_dotnot, length $base_dotnot, 1 ) eq '.';
    substr( $full_dotnot, length($base_dotnot) + 1 );
}

# Pretty_address returns a human-readable representation of an IPv4 or IPv6 address.
sub pretty_address {
    my ($addr) = shift;
    my ( $port, $addrunpack, $addrstr );

    # Disable strict subs to stop old versions of perl from
    # complaining about AF_INET6 when Socket6 is not available

    if ( ( defined $ipv6_addr_len ) && ( length $addr == $ipv6_addr_len ) ) {
        ( $port, $addrunpack ) = unpack_sockaddr_in6($addr);
        $addrstr = inet_ntop( AF_INET6(), $addrunpack );
    }
    else {
        ( $port, $addrunpack ) = unpack_sockaddr_in($addr);
        $addrstr = inet_ntoa($addrunpack);
    }

    return sprintf( "[%s].%d", $addrstr, $port );
}

sub version { $VERSION; }

sub error_return ($$) {
    my ( $this, $message ) = @_;
    $SNMP_Session::errmsg = $message;
    unless ($SNMP_Session::suppress_warnings) {
        $message =~ s/^/  /mg;
        carp( "Error:\n" . $message . "\n" );
    }
    return undef;
}

sub error ($$) {
    my ( $this, $message ) = @_;
    my $session = $this->to_string;
    $SNMP_Session::errmsg = $message . "\n" . $session;
    unless ($SNMP_Session::suppress_warnings) {
        $session =~ s/^/  /mg;
        $message =~ s/^/  /mg;
        carp( "SNMP Error:\n" . $SNMP_Session::errmsg . "\n" );
    }
    return undef;
}

sub ber_error ($$) {
    my ( $this, $type ) = @_;
    my ($errmsg) = $BER::errmsg;

    $errmsg =~ s/^/  /mg;
    return $this->error("$type:\n$errmsg");
}

=head2 receive_trap_1() - receive message on trap socket.

This method waits until a message is received on the trap socket.  If
successful, it returns two values: the message that was received, and
the address of the sender as a C<sockaddr> structure.  This address
can be passed to C<getnameinfo()> to convert it to readable output.

This method doesn't check whether the message actually encodes a trap
or anything else - the caller should use C<decode_trap_request()> to
find out.

=cut

sub receive_trap_1 ($ ) {
    my ($this) = @_;
    my ( $remote_addr, $iaddr, $port, $trap, $af );
    $remote_addr =
      recv( $this->sock, $this->{'pdu_buffer'}, $this->max_pdu_len, 0 );
    return undef unless $remote_addr;
    $trap = $this->{'pdu_buffer'};
    return ( $trap, $remote_addr );
}

=head2 receive_trap() - receive message on trap socket (deprecated version).

This function is identical to C<receive_trap_1()>, except that it
returns the sender address as three (formerly two) separate values:
The host IP address, the port, and (since version 1.14) the address
family.  If you use this, please consider moving to
C<receive_trap_1()>, because it is easier to process the sender
address in sockaddr format, in particular in a world where IPv4 and
IPv6 coexist.

=cut

sub receive_trap ($ ) {
    my ($this) = @_;
    my ( $trap, $remote_addr ) = $this->receive_trap_1();
    return undef unless defined $trap;

    my ( $iaddr, $port, $af );
    if (   ( defined $ipv6_addr_len )
        && ( length $remote_addr == $ipv6_addr_len ) )
    {
        ( $port, $iaddr ) = unpack_sockaddr_in6($remote_addr);
        $af = AF_INET6;
    }
    else {
        ( $port, $iaddr ) = unpack_sockaddr_in($remote_addr);
        $af = AF_INET;
    }
    return ( $trap, $iaddr, $port, $af );
}

=head2 decode_trap_request()

    ($community, $ent, $agent, $gen, $spec, $dt, $bindings)
      = $session->decode_trap_request ($trap);

Given a message such as one returned as the first return value from
C<receive_trap_1()> or C<receive_trap()>, try to decode it as some
notification PDU.  The code can handle SNMPv1 and SNMPv2 traps as well
as SNMPv2 INFORMs, although it fails to distinguish traps from
informs, which makes it hard to handle informs correctly (they should
be acknowledged).

The C<$ent>, C<$agent>, C<$gen>, C<$spec>, and C<$dt> values will only
be defined for SNMPv1 traps.  For SNMPv2 traps and informs, some of
this information will be encoded as bindings.

=cut

sub decode_trap_request ($$) {
    my ( $this, $trap ) = @_;
    my (
        $snmp_version, $community,   $ent, $agent,
        $gen,          $spec,        $dt,  $request_id,
        $error_status, $error_index, $bindings
    );
    ( $snmp_version, $community, $ent, $agent, $gen, $spec, $dt, $bindings ) =
      decode_by_template( $trap, "%{%i%s%*{%O%A%i%i%u%{%@", trap_request );
    if ( !defined $snmp_version ) {
        (
            $snmp_version, $community,   $request_id,
            $error_status, $error_index, $bindings
        ) = decode_by_template( $trap, "%{%i%s%*{%i%i%i%{%@", trap2_request );
        if ( !defined $snmp_version ) {
            (
                $snmp_version, $community,   $request_id,
                $error_status, $error_index, $bindings
              )
              = decode_by_template( $trap, "%{%i%s%*{%i%i%i%{%@",
                inform_request );
        }
        return $this->error_return(
                "v2 trap/inform request contained errorStatus/errorIndex "
              . $error_status . "/"
              . $error_index )
          if defined $error_status
          && defined $error_index
          && ( $error_status != 0 || $error_index != 0 );
    }
    if ( !defined $snmp_version ) {
        return $this->error_return(
            "BER error decoding trap:\n  " . $BER::errmsg );
    }
    return ( $community, $ent, $agent, $gen, $spec, $dt, $bindings );
}

=head1 METHODS in package SNMPv1_Session

=cut

package SNMPv1_Session;

use strict qw(vars subs);    # see above
use vars qw(@ISA);
use SNMP_Session;
use Socket;
use BER;
use IO::Socket;
use Carp;

BEGIN {
    if ($SNMP_Session::ipv6available) {
        import IO::Socket::INET6;
        import Socket6;
    }
}

@ISA = qw(SNMP_Session);

sub snmp_version { 0 }

=head2 open() - create an SNMPv1 session object

    $session = SNMPv1_Session->open
      ($host, $community, $port,
       $max_pdu_len, $local_port, $max_repetitions,
       $local_host, $ipv4only);

Note that all arguments except for C<$host> are optional.  The
C<$host> can be specified either as a hostname or as a numeric
address.  Numeric IPv6 addresses must be enclosed in square brackets
[]

C<$community> defaults to C<public>.

C<$port> defaults to 161, the standard UDP port to send SNMP requests
to.

C<$max_pdu_len> defaults to 8000.

C<$local_port> can be specified if a specific local port is desired,
for example because of firewall rules for the response packets.  If
none is specified, the operating system will choose a random port.

C<$max_repetitions> is the maximum number of repetitions requested in
C<get-bulk> requests.  It is only relevant in SNMPv2(c) and later.

C<$local_host> can be used to specify a specific address/interface.
It is useful on hosts that have multiple addresses if a specific
address should be used, for example because of firewall rules.

If C<$ipv4only> is either not present or non-zero, then an IPv4-only
socket will be used.  This is also the case if the system only
supports IPv4.  Otherwise, an IPv6 socket is created.  IPv6 sockets
support both IPv6 and IPv4 requests and responses.

=cut

sub open {
    my (
        $this,            $remote_hostname, $community,
        $port,            $max_pdu_len,     $local_port,
        $max_repetitions, $local_hostname,  $ipv4only
    ) = @_;
    my ( $remote_addr, $socket, $sockfamily );

    $ipv4only = 1 unless defined $ipv4only;
    $sockfamily = AF_INET;

    $community   = 'public'                        unless defined $community;
    $port        = SNMP_Session::standard_udp_port unless defined $port;
    $max_pdu_len = 8000                            unless defined $max_pdu_len;
    $max_repetitions = $default_max_repetitions
      unless defined $max_repetitions;

    if ( $ipv4only || !$SNMP_Session::ipv6available ) {

        # IPv4-only code, uses only Socket and INET calls
        if ( defined $remote_hostname ) {
            $remote_addr = inet_aton($remote_hostname)
              or return $this->error_return(
                "can't resolve \"$remote_hostname\" to IP address");
        }
        if ( $SNMP_Session::recycle_socket && exists $the_socket{$sockfamily} )
        {
            $socket = $the_socket{$sockfamily};
        }
        else {
            $socket = IO::Socket::INET->new(
                Proto     => 17,
                Type      => SOCK_DGRAM,
                LocalAddr => $local_hostname,
                LocalPort => $local_port
            ) || return $this->error_return("creating socket: $!");
            $the_socket{$sockfamily} = $socket
              if $SNMP_Session::recycle_socket;
        }
        $remote_addr = pack_sockaddr_in( $port, $remote_addr )
          if defined $remote_addr;
    }
    else {
        # IPv6-capable code. Will use IPv6 or IPv4 depending on the address.
        # Uses Socket6 and INET6 calls.

        if ( defined $remote_hostname ) {

            # If it's a numeric IPv6 addresses, remove square brackets
            if ( $remote_hostname =~ /^\[(.*)\]$/ ) {
                $remote_hostname = $1;
            }
            my ( @res, $socktype_tmp, $proto_tmp, $canonname_tmp );
            @res =
              getaddrinfo( $remote_hostname, $port, AF_UNSPEC, SOCK_DGRAM );
            (
                $sockfamily,  $socktype_tmp, $proto_tmp,
                $remote_addr, $canonname_tmp
            ) = @res;
            if ( scalar(@res) < 5 ) {
                return $this->error_return(
                    "can't resolve \"$remote_hostname\" to IPv6 address");
            }
        }
        else {
            $sockfamily = AF_INET6;
        }

        if ( $SNMP_Session::recycle_socket && exists $the_socket{$sockfamily} )
        {
            $socket = $the_socket{$sockfamily};
        }
        elsif ( $sockfamily == AF_INET ) {
            $socket = IO::Socket::INET->new(
                Proto     => 17,
                Type      => SOCK_DGRAM,
                LocalAddr => $local_hostname,
                LocalPort => $local_port
            ) || return $this->error_return("creating socket: $!");
        }
        else {
            $socket = IO::Socket::INET6->new(
                Domain    => AF_INET6,
                Proto     => 17,
                Type      => SOCK_DGRAM,
                LocalAddr => $local_hostname,
                LocalPort => $local_port
            ) || return $this->error_return("creating socket: $!");
            $the_socket{$sockfamily} = $socket
              if $SNMP_Session::recycle_socket;
        }
    }
    bless {
        'sock'            => $socket,
        'sockfileno'      => fileno($socket),
        'community'       => $community,
        'remote_hostname' => $remote_hostname,
        'remote_addr'     => $remote_addr,
        'sockfamily'      => $sockfamily,
        'max_pdu_len'     => $max_pdu_len,
        'pdu_buffer'      => '\0' x $max_pdu_len,
        'request_id'      => ( int( rand 0x10000 ) << 16 ) +
          int( rand 0x10000 ) - 0x80000000,
        'timeout'                         => $default_timeout,
        'retries'                         => $default_retries,
        'backoff'                         => $default_backoff,
        'debug'                           => $default_debug,
        'error_status'                    => 0,
        'error_index'                     => 0,
        'default_max_repetitions'         => $max_repetitions,
        'use_getbulk'                     => 1,
        'lenient_source_address_matching' => 1,
        'lenient_source_port_matching'    => 1,
        'avoid_negative_request_ids' =>
          $SNMP_Session::default_avoid_negative_request_ids,
        'use_16bit_request_ids' => $SNMP_Session::default_use_16bit_request_ids,
        'capture_buffer'        => undef,
    };
}

=head2 open_trap_session() - create a session for receiving SNMP traps.

    $session = open_trap_session ($port, $ipv4only);

C<$port> defaults to 162, the standard UDP port that SNMP
notifications are sent to.

If C<$ipv4only> is either not present or non-zero, then an IPv4-only
socket will be used.  This is also the case if the system only
supports IPv4.  Otherwise, an IPv6 socket is created.  IPv6 sockets
can receive messages over both IPv6 and IPv4.

=cut

sub open_trap_session (@) {
    my ( $this, $port, $ipv4only ) = @_;
    $port     = 162 unless defined $port;
    $ipv4only = 1   unless defined $ipv4only;
    return $this->open( undef, "", 161, undef, $port, undef, undef, $ipv4only );
}

sub sock        { $_[0]->{sock} }
sub sockfileno  { $_[0]->{sockfileno} }
sub remote_addr { $_[0]->{remote_addr} }
sub pdu_buffer  { $_[0]->{pdu_buffer} }
sub max_pdu_len { $_[0]->{max_pdu_len} }

sub default_max_repetitions {
    defined $_[1]
      ? $_[0]->{default_max_repetitions} = $_[1]
      : $_[0]->{default_max_repetitions};
}
sub debug { defined $_[1] ? $_[0]->{debug} = $_[1] : $_[0]->{debug} }

sub close {
    my ($this) = shift;
    ## Avoid closing the socket if it may be shared with other session
    ## objects.
    if ( !exists $the_socket{ $this->{sockfamily} }
        or $this->sock ne $the_socket{ $this->{sockfamily} } )
    {
        close( $this->sock ) || $this->error("close: $!");
    }
}

sub wrap_request {
    my ($this)    = shift;
    my ($request) = shift;

    encode_sequence( encode_int( $this->snmp_version ),
        encode_string( $this->{community} ), $request )
      || return $this->ber_error("wrapping up request PDU");
}

my @error_status_code = qw(noError tooBig noSuchName badValue readOnly
  genErr noAccess wrongType wrongLength
  wrongEncoding wrongValue noCreation
  inconsistentValue resourceUnavailable
  commitFailed undoFailed authorizationError
  notWritable inconsistentName);

sub unwrap_response_5b {
    my ( $this, $response, $tag, $oids, $errorp ) = @_;
    my ( $community, $request_id, @rest, $snmpver );

    (
        $snmpver, $community, $request_id, $this->{error_status},
        $this->{error_index}, @rest
    ) = decode_by_template( $response, "%{%i%s%*{%i%i%i%{%@", $tag );
    return $this->ber_error("Error decoding response PDU")
      unless defined $snmpver;
    return $this->error(
        "Received SNMP response with unknown snmp-version field $snmpver")
      unless $snmpver == $this->snmp_version;
    if ( $this->{error_status} != 0 ) {
        if ($errorp) {
            my ( $oid, $errmsg );
            $errmsg = $error_status_code[ $this->{error_status} ]
              || $this->{error_status};
            $oid = $oids->[ $this->{error_index} - 1 ]
              if $this->{error_index} > 0
              && $this->{error_index} - 1 <= $#{$oids};
            $oid = $oid->[0]
              if ref($oid) eq 'ARRAY';
            return (
                $community,
                $request_id,
                $this->error(
                        "Received SNMP response with error code\n"
                      . "  error status: $errmsg\n"
                      . "  index "
                      . $this->{error_index}
                      . (
                        defined $oid
                        ? " (OID: " . &BER::pretty_oid($oid) . ")"
                        : ""
                      )
                )
            );
        }
        else {
            if ( $this->{error_index} == 1 ) {
                @rest[ $this->{error_index} - 1 .. $this->{error_index} ] = ();
            }
        }
    }
    ( $community, $request_id, @rest );
}

sub send_query ($$) {
    my ( $this, $query ) = @_;
    send( $this->sock, $query, 0, $this->remote_addr );
}

## Compare two sockaddr_in structures for equality.  This is used when
## matching incoming responses with outstanding requests.  Previous
## versions of the code simply did a bytewise comparison ("eq") of the
## two sockaddr_in structures, but this didn't work on some systems
## where sockaddr_in contains other elements than just the IP address
## and port number, notably FreeBSD.
##
## We allow for varying degrees of leniency when checking the source
## address.  By default we now ignore it altogether, because there are
## agents that don't respond from UDP port 161, and there are agents
## that don't respond from the IP address the query had been sent to.
##
## The address family is stored in the session object. We could use
## sockaddr_family() to determine it from the sockaddr, but this function
## is only available in recent versions of Socket.pm.
sub sa_equal_p ($$$) {
    my ( $this, $sa1, $sa2 ) = @_;
    my ( $p1, $a1, $p2, $a2 );

    # Disable strict subs to stop old versions of perl from
    # complaining about AF_INET6 when Socket6 is not available
    if ( $this->{'sockfamily'} == AF_INET ) {

        # IPv4 addresses
        ( $p1, $a1 ) = unpack_sockaddr_in($sa1);
        ( $p2, $a2 ) = unpack_sockaddr_in($sa2);
    }
    elsif ( $this->{'sockfamily'} == AF_INET6() ) {

        # IPv6 addresses
        ( $p1, $a1 ) = unpack_sockaddr_in6($sa1);
        ( $p2, $a2 ) = unpack_sockaddr_in6($sa2);
    }
    else {
        return 0;
    }
    use strict "subs";

    if ( !$this->{'lenient_source_address_matching'} ) {
        return 0 if $a1 ne $a2;
    }
    if ( !$this->{'lenient_source_port_matching'} ) {
        return 0 if $p1 != $p2;
    }
    return 1;
}

sub receive_response_3 {
    my ( $this, $response_tag, $oids, $errorp, $dont_block_p ) = @_;
    my ($remote_addr);
    my $flags = 0;
    $flags = $dont_wait_flags if defined $dont_block_p and $dont_block_p;
    $remote_addr =
      recv( $this->sock, $this->{'pdu_buffer'}, $this->max_pdu_len, $flags );
    return $this->error("receiving response PDU: $!")
      unless defined $remote_addr;
    return $this->error(
        "short (" . length $this->{'pdu_buffer'} . " bytes) response PDU" )
      unless length $this->{'pdu_buffer'} > 2;
    my $response = $this->{'pdu_buffer'};
    ##
    ## Check whether the response came from the address we've sent the
    ## request to.  If this is not the case, we should probably ignore
    ## it, as it may relate to another request.
    ##
    if ( defined $this->{'remote_addr'} ) {
        if ( !$this->sa_equal_p( $remote_addr, $this->{'remote_addr'} ) ) {
            if ( $this->{'debug'} && !$SNMP_Session::recycle_socket ) {
                carp(   "Response came from "
                      . &SNMP_Session::pretty_address($remote_addr)
                      . ", not "
                      . &SNMP_Session::pretty_address( $this->{'remote_addr'} )
                ) unless $SNMP_Session::suppress_warnings;
            }
            return 0;
        }
    }
    $this->{'last_sender_addr'} = $remote_addr;
    my ( $response_community, $response_id, @unwrapped ) =
      $this->unwrap_response_5b( $response, $response_tag, $oids, $errorp );
    if (   $response_community ne $this->{community}
        || $response_id ne $this->{request_id} )
    {
        if ( $this->{'debug'} ) {
            carp("$response_community != $this->{community}")
              unless $SNMP_Session::suppress_warnings
              || $response_community eq $this->{community};
            carp("$response_id != $this->{request_id}")
              unless $SNMP_Session::suppress_warnings
              || $response_id == $this->{request_id};
        }
        return 0;
    }
    if ( !defined $unwrapped[0] ) {
        $this->{'unwrapped'} = undef;
        return undef;
    }
    $this->{'unwrapped'} = \@unwrapped;
    return length $this->pdu_buffer;
}

sub describe {
    my ($this) = shift;
    print $this->to_string(), "\n";
}

sub to_string {
    my ($this) = shift;
    my ( $class, $prefix );

    $class = ref($this);
    $prefix = ' ' x ( length($class) + 2 );
    (
        $class
          . (
            defined $this->{remote_hostname}
            ? " (remote host: \""
              . $this->{remote_hostname} . "\"" . " "
              . &SNMP_Session::pretty_address( $this->remote_addr ) . ")"
            : " (no remote host specified)"
          )
          . "\n"
          . $prefix
          . "  community: \""
          . $this->{'community'} . "\"\n"
          . $prefix
          . " request ID: "
          . $this->{'request_id'} . "\n"
          . $prefix
          . "PDU bufsize: "
          . $this->{'max_pdu_len'}
          . " bytes\n"
          . $prefix
          . "    timeout: "
          . $this->{timeout} . "s\n"
          . $prefix
          . "    retries: "
          . $this->{retries} . "\n"
          . $prefix
          . "    backoff: "
          . $this->{backoff} . ")"
    );
##    sprintf ("SNMP_Session: %s (size %d timeout %g)",
##    &SNMP_Session::pretty_address ($this->remote_addr),$this->max_pdu_len,
##	       $this->timeout);
}

### SNMP Agent support
### contributed by Mike McCauley <mikem@open.com.au>
###
sub receive_request {
    my ($this) = @_;
    my ( $remote_addr, $iaddr, $port, $request );

    $remote_addr =
      recv( $this->sock, $this->{'pdu_buffer'}, $this->{'max_pdu_len'}, 0 );
    return undef unless $remote_addr;

    if (   ( defined $ipv6_addr_len )
        && ( length $remote_addr == $ipv6_addr_len ) )
    {
        ( $port, $iaddr ) = unpack_sockaddr_in6($remote_addr);
    }
    else {
        ( $port, $iaddr ) = unpack_sockaddr_in($remote_addr);
    }

    $request = $this->{'pdu_buffer'};
    return ( $request, $iaddr, $port );
}

sub decode_request {
    my ( $this, $request ) = @_;
    my (
        $snmp_version, $community,  $requestid,
        $errorstatus,  $errorindex, $bindings
    );

    (
        $snmp_version, $community,  $requestid,
        $errorstatus,  $errorindex, $bindings
      )
      = decode_by_template( $request, "%{%i%s%*{%i%i%i%@",
        SNMP_Session::get_request );
    if ( defined $snmp_version ) {

        # Its a valid get_request
        return ( SNMP_Session::get_request, $requestid, $bindings, $community );
    }

    (
        $snmp_version, $community,  $requestid,
        $errorstatus,  $errorindex, $bindings
      )
      = decode_by_template( $request, "%{%i%s%*{%i%i%i%@",
        SNMP_Session::getnext_request );
    if ( defined $snmp_version ) {

        # Its a valid getnext_request
        return ( SNMP_Session::getnext_request, $requestid, $bindings,
            $community );
    }

    (
        $snmp_version, $community,  $requestid,
        $errorstatus,  $errorindex, $bindings
      )
      = decode_by_template( $request, "%{%i%s%*{%i%i%i%@",
        SNMP_Session::set_request );
    if ( defined $snmp_version ) {

        # Its a valid set_request
        return ( SNMP_Session::set_request, $requestid, $bindings, $community );
    }

    # Something wrong with this packet
    # Decode failed
    return undef;
}

=head1 METHODS in package SNMPv2c_Session

=cut

package SNMPv2c_Session;
use strict qw(vars subs);    # see above
use vars qw(@ISA);
use SNMP_Session;
use BER;
use Carp;

@ISA = qw(SNMPv1_Session);

sub snmp_version { 1 }

=head2 open() - create an SNMPv2(c) session object

    $session = SNMPv2c_Session->open
      ($host, $community, $port,
       $max_pdu_len, $local_port, $max_repetitions,
       $local_host, $ipv4only);

The calling and return conventions are identical to
C<SNMPv1_Session::open()>, except that this returns a session object
that supports SNMPv2 operations.

=cut

sub open {
    my $session = SNMPv1_Session::open(@_);
    return undef unless defined $session;
    return bless $session;
}

## map_table_start_end using get-bulk
##
sub map_table_start_end ($$$$$$) {
    my ( $session, $columns, $mapfn, $start, $end, $max_repetitions ) = @_;

    my @encoded_oids;
    my $call_counter     = 0;
    my $base_index       = $start;
    my $ncols            = @{$columns};
    my @collected_values = ();

    if ( !$session->{'use_getbulk'} ) {
        return SNMP_Session::map_table_start_end( $session, $columns, $mapfn,
            $start, $end, $max_repetitions );
    }
    $max_repetitions = $session->default_max_repetitions
      unless defined $max_repetitions;

    for ( ; ; ) {
        foreach ( @encoded_oids = @{$columns} ) {
            $_ = encode_oid( @{$_}, split '\.', $base_index )
              || return $session->ber_error("encoding OID $base_index");
        }
        if (
            $session->getbulk_request_response(
                0, $max_repetitions, @encoded_oids
            )
          )
        {
            my $response   = $session->pdu_buffer;
            my ($bindings) = $session->decode_get_response($response);
            my @colstack   = ();
            my $k          = 0;
            my $j;

            my $min_index = undef;

            my @bases      = @{$columns};
            my $n_bindings = 0;
            my $binding;

            ## Copy all bindings into the colstack.
            ## The colstack is a vector of vectors.
            ## It contains one vector for each "repeater" variable.
            ##
            while ( $bindings ne '' ) {
                ( $binding, $bindings ) = decode_sequence($bindings);
                my ( $oid, $value ) = decode_by_template( $binding, "%O%@" );

                push @{ $colstack[$k] }, [ $oid, $value ];
                ++$k;
                $k = 0 if $k >= $ncols;
            }

            ## Now collect rows from the column stack:
            ##
            ## Iterate through the column stacks to find the smallest
            ## index, collecting the values for that index in
            ## @collected_values.
            ##
            ## As long as a row can be assembled, the map function is
            ## called on it and the iteration proceeds.
            ##
            $base_index = undef;
          walk_rows_from_pdu:
            for ( ; ; ) {
                my $min_index = undef;

                for ( $k = 0 ; $k < $ncols ; ++$k ) {
                    $collected_values[$k] = undef;
                    my $pair = $colstack[$k]->[0];
                    unless ( defined $pair ) {
                        $min_index = undef;
                        last walk_rows_from_pdu;
                    }
                    my $this_index =
                      SNMP_Session::oid_diff( $columns->[$k], $pair->[0] );
                    if ( defined $this_index ) {
                        my $cmp =
                          !defined $min_index
                          ? -1
                          : SNMP_Session::index_compare( $this_index,
                            $min_index );
                        if ( $cmp == -1 ) {
                            for ( $j = 0 ; $j < $k ; ++$j ) {
                                unshift(
                                    @{ $colstack[$j] },
                                    [ $min_index, $collected_values[$j] ]
                                );
                                $collected_values[$j] = undef;
                            }
                            $min_index = $this_index;
                        }
                        if ( $cmp <= 0 ) {
                            $collected_values[$k] = $pair->[1];
                            shift @{ $colstack[$k] };
                        }
                    }
                }
                ( $base_index = undef ), last
                  if !defined $min_index;
                last
                  if defined $end
                  and SNMP_Session::index_compare( $min_index, $end ) >= 0;
                &$mapfn( $min_index, @collected_values );
                ++$call_counter;
                $base_index = $min_index;
            }
        }
        else {
            return undef;
        }
        last if !defined $base_index;
        last
          if defined $end
          and SNMP_Session::index_compare( $base_index, $end ) >= 0;
    }
    $call_counter;
}

1;

=head1 EXAMPLES

The basic usage of these routines works like this:

 use BER;
 use SNMP_Session;
 
 # Set $host to the name of the host whose SNMP agent you want
 # to talk to.  Set $community to the community name under
 # which you want to talk to the agent.	Set port to the UDP
 # port on which the agent listens (usually 161).
 
 $session = SNMP_Session->open ($host, $community, $port)
     or die "couldn't open SNMP session to $host";
 
 # Set $oid1, $oid2... to the BER-encoded OIDs of the MIB
 # variables you want to get.
 
 if ($session->get_request_response ($oid1, $oid2, ...)) {
     ($bindings) = $session->decode_get_response ($session->{pdu_buffer});
 
     while ($bindings ne '') {
 	($binding,$bindings) = decode_sequence ($bindings);
 	($oid,$value) = decode_by_template ($binding, "%O%@");
 	print pretty_print ($oid)," => ", pretty_print ($value), "\n";
     }
 } else {
     die "No response from agent on $host";
 }

=head2 Encoding OIDs

In order to BER-encode OIDs, you can use the function
B<BER::encode_oid>. It takes (a vector of) numeric subids as an
argument. For example,

 use BER;
 encode_oid (1, 3, 6, 1, 2, 1, 1, 1, 0)

will return the BER-encoded OID for the B<sysDescr.0>
(1.3.6.1.2.1.1.1.0) instance of MIB-2.

=head2 Decoding the results

When C<get_request_response()> returns success, you must decode the
response PDU from the remote agent. The function
C<decode_get_response()> can be used to do this. It takes a
C<get-response> PDU, checks its syntax and returns the I<bindings>
part of the PDU. This is where the remote agent actually returns the
values of the variables in your query.

You should iterate over the individual bindings in this I<bindings>
part and extract the value for each variable. In the example above,
the returned bindings are simply printed using the
C<BER::pretty_print()> function.

For better readability of the OIDs, you can also use the following
idiom, where the C<%pretty_oids> hash maps BER-encoded numerical OIDs
to symbolic OIDs. Note that this simple-minded mapping only works for
response OIDs that exactly match known OIDs, so it's unsuitable for
table walking (where the response OIDs include an additional row
index).

 %ugly_oids = qw(sysDescr.0	1.3.6.1.2.1.1.1.0
 		sysContact.0	1.3.6.1.2.1.1.4.0);
 foreach (keys %ugly_oids) {
     $ugly_oids{$_} = encode_oid (split (/\./, $ugly_oids{$_}));
     $pretty_oids{$ugly_oids{$_}} = $_;
 }
 ...
 if ($session->get_request_response ($ugly_oids{'sysDescr.0'},
 				    $ugly_oids{'sysContact.0'})) {
     ($bindings) = $session->decode_get_response ($session->{pdu_buffer});
     while ($bindings ne '') {
 	($binding,$bindings) = decode_sequence ($bindings);
 	($oid,$value) = decode_by_template ($binding, "%O%@");
 	print $pretty_oids{$oid}," => ",
 	      pretty_print ($value), "\n";
     }
 } ...

=head2 Set Requests

Set requests are generated much like C<get> or C<getNext> requests
are, with the exception that you have to specify not just OIDs, but
also the values the variables should be set to. Every binding is
passed as a reference to a two-element array, the first element being
the encoded OID and the second one the encoded value. See the
C<test/set-test.pl> script for an example, in particular the
subroutine C<snmpset>.

=head2 Walking Tables

Beginning with version 0.57 of C<SNMP_Session.pm>, there is API
support for walking tables. The C<map_table()> method can be used for
this as follows:

 sub walk_function ($$$) {
   my ($index, $val1, $val3) = @_;
   ...
 }
 
 ...
 $columns = [$base_oid1, $base_oid3];
 $n_rows = $session->map_table ($columns, \&walk_function);

The I<columns> argument must be a reference to a list of OIDs for table
columns sharing the same index. The method will traverse the table and
call the I<walk_function> for each row. The arguments for these calls
will be:

=over

=item 1. the I<row index> as a partial OID in dotted notation, e.g.
C<1.3>, or C<10.0.1.34>.

=item 2. the values of the requested table columns in that row, in
BER-encoded form. If you want to use the standard C<pretty_print()>
subroutine to decode the values, you can use the following idiom:

  grep (defined $_ && ($_=pretty_print $_), ($val1, $val3));

=back

=head2 Walking Tables With C<get-bulk>

Since version 0.67, C<SNMP_Session> uses a different C<get_table>
implementation for C<SNMPv2c_Session>s. This version uses the
``powerful C<get-bulk> operator'' to retrieve many table rows with
each request. In general, this will make table walking much faster
under SNMPv2c, especially when round-trip times to the agent are long.

There is one difficulty, however: With C<get-bulk>, a management
application can specify the maximum number of rows to return in a
single response. C<SNMP_Session.pm> provides a new function,
C<map_table_4>, in which this C<maxRepetitions> value can be specified
explicitly.

For maximum efficiency, it should be set to a value that is one
greater than the number of rows in the table. If it is smaller, then
C<map_table()> will use more request/response cycles than necessary;
if it is bigger, the agent will have to compute variable bindings
beyond the end of the table (which C<map_table()> will throw away).

Of course it is usually impossible to know the size of the table in
advance. If you don't specify C<maxRepetitions> when walking a table,
then C<map_table()> will use a per-session default
(C<$session-E<gt>default_max_repetitions>). The default value for this
default is 12.

If you walk a table multiple times, and the size of the table is
relatively stable, you should use the return value of C<map_table()>
(which is the number of rows it has encountered) to compute the next
value of C<maxRepetitions>. Remember to add one so that C<map_table()>
notices when the table is finished!

Note that for really big tables, this doesn't make a big difference,
since the table won't fit in a single response packet anyway.

=head2 Sending Traps

To send a trap, you have to open an SNMP session to the trap receiver.
Usually this is a process listening to UDP port 162 on a network
management station. Then you can use the C<trap_request_send()> method
to encode and send SNMPv1 traps. There is no way to find out whether
the trap was actually received at the management station - SNMP traps
are fundamentally unreliable.

When constructing an SNMPv1 trap, you must provide

=over

=item * the "enterprise" Object Identifier for the entity that
generates the trap

=item * your IP address

=item * the generic trap type

=item * the specific trap type

=item * the C<sysUpTime> at the time of trap generation

=item * a sequence (may be empty) of variable bindings further
describing the trap.

=back

For SNMPv2 traps, you need:

=over

=item * the trap's OID

=item * the C<sysUpTime> at the time of trap generation

=item * the bindings list as above

=back

For SNMPv2 traps, the uptime and trap OID are encoded as bindings which
are added to the front of the other bindings you provide.

Here is a short example:

 my $trap_receiver = "netman.noc";
 my $trap_community = "SNMP_Traps";
 my $trap_session = $version eq '1'
     ? SNMP_Session->open ($trap_receiver, $trap_community, 162)
     : SNMPv2c_Session->open ($trap_receiver, $trap_community, 162);
 my $myIpAddress = ...;
 my $start_time = time;
 
 ...
 
 sub link_down_trap ($$) {
   my ($if_index, $version) = @_;
   my $genericTrap = 2;		# linkDown
   my $specificTrap = 0;
   my @ifIndexOID = ( 1,3,6,1,2,1,2,2,1,1 );
   my $upTime = int ((time - $start_time) * 100.0);
   my @myOID = ( 1,3,6,1,4,1,2946,0,8,15 );
 
   warn "Sending trap failed"
     unless ($version eq '1')
 	? $trap_session->trap_request_send (encode_oid (@myOID),
 					    encode_ip_address ($myIpAddress),
 					    encode_int ($genericTrap),
 					    encode_int ($specificTrap),
 					    encode_timeticks ($upTime),
 					    [encode_oid (@ifIndex_OID,$if_index),
 					     encode_int ($if_index)],
 					    [encode_oid (@ifDescr_OID,$if_index),
 					     encode_string ("foo")])
 	    : $trap_session->v2_trap_request_send (\@linkDown_OID, $upTime,
 						   [encode_oid (@ifIndex_OID,$if_index),
 						    encode_int ($if_index)],
 						   [encode_oid (@ifDescr_OID,$if_index),
 						    encode_string ("foo")]);
 }

=head2 Receiving Traps

Since version 0.60, C<SNMP_Session.pm> supports the receipt and
decoding of SNMPv1 trap requests. Since version 0.75, SNMPv2 Trap PDUs
are also recognized.

To receive traps, you have to create a special SNMP session that
passively listens on the SNMP trap transport address, usually on UDP
port 162.  Then you can receive traps - actually, SNMPv1 traps, SNMPv2
traps, and SNMPv2 informs, using the C<receive_trap_1()> method and
decode them using C<decode_trap_request()>. The I<enterprise>,
I<agent>, I<generic>, I<specific> and I<sysUptime> return values are
only defined for SNMPv1 traps. In SNMPv2 traps and informs, the
equivalent information is contained in the bindings.

 my $trap_session = SNMPv1_Session->open_trap_session (162, 0)
   or die "cannot open trap session";
 my ($trap, $sender_sockaddr) = $trap_session->receive_trap_1 ()
   or die "cannot receive trap";
 my ($community, $enterprise, $agent,
     $generic, $specific, $sysUptime, $bindings)
   = $trap_session->decode_trap_request ($trap)
     or die "cannot decode trap received"
 ...
 my ($binding, $oid, $value);
 while ($bindings ne '') {
     ($binding,$bindings) = decode_sequence ($bindings);
     ($oid, $value) = decode_by_template ($binding, "%O%@");
     print BER::pretty_oid ($oid)," => ",pretty_print ($value),"\n";
 }

=head1 AUTHORS

Created by:  Simon Leinen  E<lt>simon.leinen@switch.chE<gt>

Contributions and fixes by:

=over

=item Matthew Trunnell E<lt>matter@media.mit.eduE<gt>

=item Tobias Oetiker E<lt>tobi@oetiker.chE<gt>

=item Heine Peters E<lt>peters@dkrz.deE<gt>

=item Daniel L. Needles E<lt>dan_needles@INS.COME<gt>

=item Mike Mitchell E<lt>mcm@unx.sas.comE<gt>

=item Clinton Wong E<lt>clintdw@netcom.comE<gt>

=item Alan Nichols E<lt>Alan.Nichols@Ebay.Sun.COME<gt>

=item Mike McCauley E<lt>mikem@open.com.auE<gt>

=item Andrew W. Elble E<lt>elble@icculus.nsg.nwu.eduE<gt>

=item Brett T Warden E<lt>wardenb@eluminant.comE<gt>: pretty C<UInteger32>

=item Michael Deegan E<lt>michael@cnspc18.murdoch.edu.auE<gt>

=item Sergio Macedo E<lt>macedo@tmp.com.brE<gt>

=item Jakob Ilves (/IlvJa) E<lt>jakob.ilves@oracle.comE<gt>: PDU capture

=item Valerio Bontempi E<lt>v.bontempi@inwind.itE<gt>: IPv6 support

=item Lorenzo Colitti E<lt>lorenzo@colitti.comE<gt>: IPv6 support

=item Philippe Simonet E<lt>Philippe.Simonet@swisscom.comE<gt>: Export C<avoid...>

=item Luc Pauwels E<lt>Luc.Pauwels@xalasys.comE<gt>: C<use_16bit_request_ids>

=item Andrew Cornford-Matheson E<lt>andrew.matheson@corenetworks.comE<gt>: inform

=item Gerry Dalton E<lt>gerry.dalton@consolidated.comE<gt>: C<strict subs> bug

=item Mike Fischer E<lt>mlf2@tampabay.rr.comE<gt>: pass MSG_DONTWAIT to C<recv()>

=back

=head1 COPYRIGHT

Copyright (c) 1995-2009, Simon Leinen.

This program is free software; you can redistribute it under the
"Artistic License 2.0" included in this distribution (file "Artistic").

=cut
