=head1 NAME

Params::Classify - argument type classification

=head1 SYNOPSIS

	use Params::Classify qw(
		scalar_class
		is_undef check_undef
		is_string check_string
		is_number check_number
		is_glob check_glob
		is_regexp check_regexp
		is_ref check_ref ref_type
		is_blessed check_blessed blessed_class
		is_strictly_blessed check_strictly_blessed
		is_able check_able
	);

	$c = scalar_class($arg);

	if(is_undef($arg)) {
	check_undef($arg);

	if(is_string($arg)) {
	check_string($arg);
	if(is_number($arg)) {
	check_number($arg);

	if(is_glob($arg)) {
	check_glob($arg);
	if(is_regexp($arg)) {
	check_regexp($arg);

	if(is_ref($arg)) {
	check_ref($arg);
	$t = ref_type($arg);
	if(is_ref($arg, "HASH")) {
	check_ref($arg, "HASH");

	if(is_blessed($arg)) {
	check_blessed($arg);
	if(is_blessed($arg, "IO::Handle")) {
	check_blessed($arg, "IO::Handle");
	$c = blessed_class($arg);
	if(is_strictly_blessed($arg, "IO::Pipe::End")) {
	check_strictly_blessed($arg, "IO::Pipe::End");
	if(is_able($arg, ["print", "flush"])) {
	check_able($arg, ["print", "flush"]);

=head1 DESCRIPTION

This module provides various type-testing functions.  These are intended
for functions that, unlike most Perl code, care what type of data they
are operating on.  For example, some functions wish to behave differently
depending on the type of their arguments (like overloaded functions
in C++).

There are two flavours of function in this module.  Functions of the first
flavour only provide type classification, to allow code to discriminate
between argument types.  Functions of the second flavour package up the
most common type of type discrimination: checking that an argument is
of an expected type.  The functions come in matched pairs, of the two
flavours, and so the type enforcement functions handle only the simplest
requirements for arguments of the types handled by the classification
functions.  Enforcement of more complex types may, of course, be built
using the classification functions, or it may be more convenient to use
a module designed for the more complex job, such as L<Params::Validate>.

This module is implemented in XS, with a pure Perl backup version for
systems that can't handle XS.

=cut

package Params::Classify;

{ use 5.006001; }
use warnings;
use strict;

our $VERSION = "0.013";

use parent "Exporter";
our @EXPORT_OK = qw(
	scalar_class
	is_undef check_undef
	is_string check_string
	is_number check_number
	is_glob check_glob
	is_regexp check_regexp
	is_ref check_ref ref_type
	is_blessed check_blessed blessed_class
	is_strictly_blessed check_strictly_blessed
	is_able check_able
);

eval { local $SIG{__DIE__};
	require XSLoader;
	XSLoader::load(__PACKAGE__, $VERSION);
};

if($@ eq "") {
	close(DATA);
} else {
	(my $filename = __FILE__) =~ tr# -~##cd;
	local $/ = undef;
	my $pp_code = "#line 128 \"$filename\"\n".<DATA>;
	close(DATA);
	{
		local $SIG{__DIE__};
		eval $pp_code;
	}
	die $@ if $@ ne "";
}

sub is_string($);
sub is_number($) {
	return 0 unless &is_string;
	my $warned;
	local $SIG{__WARN__} = sub { $warned = 1; };
	my $arg = $_[0];
	{ no warnings "void"; 0 + $arg; }
	return !$warned;
}

sub check_number($) {
	die "argument is not a number\n" unless &is_number;
}

1;

__DATA__

use Scalar::Util 1.01 qw(blessed reftype);

=head1 TYPE CLASSIFICATION

This module divides up scalar values into the following classes:

=over

=item *

undef

=item *

string (defined ordinary scalar)

=item *

typeglob (yes, typeglobs fit into scalar variables)

=item *

regexp (first-class regular expression objects in Perl 5.11 onwards)

=item *

reference to unblessed object (further classified by physical data type
of the referenced object)

=item *

reference to blessed object (further classified by class blessed into)

=back

These classes are mutually exclusive and should be exhaustive.  This
classification has been chosen as the most useful when one wishes to
discriminate between types of scalar.  Other classifications are possible.
(For example, the two reference classes are distinguished by a feature of
the referenced object; Perl does not internally treat this as a feature
of the reference.)

=head1 FUNCTIONS

Each of these functions takes one scalar argument (I<ARG>) to be tested,
possibly with other arguments specifying details of the test.  Any scalar
value is acceptable for the argument to be tested.  Each C<is_> function
returns a simple truth value result, which is true iff I<ARG> is of the
type being checked for.  Each C<check_> function will return normally
if the argument is of the type being checked for, or will C<die> if it
is not.

=head2 Classification

=over

=item scalar_class(ARG)

Determines which of the five classes described above I<ARG> falls into.
Returns "B<UNDEF>", "B<STRING>", "B<GLOB>", "B<REGEXP>", "B<REF>", or
"B<BLESSED>" accordingly.

=cut

sub scalar_class($) {
	my $type = reftype(\$_[0]);
	if($type eq "SCALAR") {
		$type = defined($_[0]) ? "STRING" : "UNDEF";
	} elsif($type eq "REF") {
		$type = "BLESSED" if defined(blessed($_[0]));
	}
	$type;
}

=back

=head2 The Undefined Value

=over

=item is_undef(ARG)

=item check_undef(ARG)

Check whether I<ARG> is C<undef>.  C<is_undef(ARG)> is precisely
equivalent to C<!defined(ARG)>, and is included for completeness.

=cut

sub is_undef($) { !defined($_[0]) }

sub check_undef($) {
	die "argument is not undefined\n" unless &is_undef;
}

=back

=head2 Strings

=over

=item is_string(ARG)

=item check_string(ARG)

Check whether I<ARG> is defined and is an ordinary scalar value (not a
reference, typeglob, or regexp).  This is what one usually thinks of as a
string in Perl.  In fact, any scalar (including C<undef> and references)
can be coerced to a string, but if you're trying to classify a scalar
then you don't want to do that.

=cut

sub is_string($) { defined($_[0]) && reftype(\$_[0]) eq "SCALAR" }

sub check_string($) {
	die "argument is not a string\n" unless &is_string;
}

=item is_number(ARG)

=item check_number(ARG)

Check whether I<ARG> is defined and an ordinary scalar (i.e.,
satisfies L</is_string> above) and is an acceptable number to Perl.
This is what one usually thinks of as a number.

Note that simple (L</is_string>-satisfying) scalars may have independent
numeric and string values, despite the usual pretence that they have
only one value.  Such a scalar is deemed to be a number if I<either> it
already has a numeric value (e.g., was generated by a numeric literal
or an arithmetic computation) I<or> its string value has acceptable
syntax for a number (so it can be converted).  Where a scalar has
separate numeric and string values (see L<Scalar::Util/dualvar>), it is
possible for it to have an acceptable numeric value while its string
value does I<not> have acceptable numeric syntax.  Be careful to use
such a value only in a numeric context, if you are using it as a number.
L<Scalar::Number/scalar_num_part> extracts the numeric part of a
scalar as an ordinary number.  (C<0+ARG> suffices for that unless you
need to preserve floating point signed zeroes.)

A number may be either a native integer or a native floating point
value, and there are several subtypes of floating point value.
For classification, and other handling of numbers in scalars, see
L<Scalar::Number>.  For details of the two numeric data types, see
L<Data::Integer> and L<Data::Float>.

This function differs from C<looks_like_number> (see
L<Scalar::Util/looks_like_number>; also L<perlapi/looks_like_number>
for a lower-level description) in excluding C<undef>, typeglobs,
and references.  Why C<looks_like_number> returns true for C<undef>
or typeglobs is anybody's guess.  References, if treated as numbers,
evaluate to the address in memory that they reference; this is useful
for comparing references for equality, but it is not otherwise useful
to treat references as numbers.  Blessed references may have overloaded
numeric operators, but if so then they don't necessarily behave like
ordinary numbers.  C<looks_like_number> is also confused by dualvars:
it looks at the string portion of the scalar.

=back

=head2 Typeglobs

=over

=item is_glob(ARG)

=item check_glob(ARG)

Check whether I<ARG> is a typeglob.

=cut

sub is_glob($) { reftype(\$_[0]) eq "GLOB" }

sub check_glob($) {
	die "argument is not a typeglob\n" unless &is_glob;
}

=back

=head2 Regexps

=over

=item is_regexp(ARG)

=item check_regexp(ARG)

Check whether I<ARG> is a regexp object.

=cut

sub is_regexp($) { reftype(\$_[0]) eq "REGEXP" }

sub check_regexp($) {
	die "argument is not a regexp\n" unless &is_regexp;
}

=back

=head2 References to Unblessed Objects

=over

=item is_ref(ARG)

=item check_ref(ARG)

Check whether I<ARG> is a reference to an unblessed object.  If it
is, then the referenced data type can be determined using C<ref_type>
(see below), which will return a string such as "HASH" or "SCALAR".

=item ref_type(ARG)

Returns C<undef> if I<ARG> is not a reference to an unblessed object.
Otherwise, determines what type of object is referenced.  Returns
"B<SCALAR>", "B<ARRAY>", "B<HASH>", "B<CODE>", "B<FORMAT>", or "B<IO>"
accordingly.

Note that, unlike C<ref>, this does not distinguish between different
types of referenced scalar.  A reference to a string and a reference to
a reference will both return "B<SCALAR>".  Consequently, what C<ref_type>
returns for a particular reference will not change due to changes in
the value of the referent, except for the referent being blessed.

=item is_ref(ARG, TYPE)

=item check_ref(ARG, TYPE)

Check whether I<ARG> is a reference to an unblessed object of type
I<TYPE>, as determined by L</ref_type>.  I<TYPE> must be a string.
Possible I<TYPE>s are "B<SCALAR>", "B<ARRAY>", "B<HASH>", "B<CODE>",
"B<FORMAT>", and "B<IO>".

=cut

{
	my %xlate_reftype = (
		REF    => "SCALAR",
		SCALAR => "SCALAR",
		LVALUE => "SCALAR",
		GLOB   => "SCALAR",
		REGEXP => "SCALAR",
		ARRAY  => "ARRAY",
		HASH   => "HASH",
		CODE   => "CODE",
		FORMAT => "FORMAT",
		IO     => "IO",
	);

	my %reftype_ok = map { ($_ => undef) } qw(
		SCALAR ARRAY HASH CODE FORMAT IO
	);

	sub ref_type($) {
		my $reftype = &reftype;
		return undef unless
			defined($reftype) && !defined(blessed($_[0]));
		my $xlated_reftype = $xlate_reftype{$reftype};
		die "unknown reftype `$reftype', please update Params::Classify"
			unless defined $xlated_reftype;
		$xlated_reftype;
	}

	sub is_ref($;$) {
		if(@_ == 2) {
			die "reference type argument is not a string\n"
				unless is_string($_[1]);
			die "invalid reference type\n"
				unless exists $reftype_ok{$_[1]};
		}
		my $reftype = reftype($_[0]);
		return undef unless
			defined($reftype) && !defined(blessed($_[0]));
		return 1 if @_ != 2;
		my $xlated_reftype = $xlate_reftype{$reftype};
		die "unknown reftype `$reftype', please update Params::Classify"
			unless defined $xlated_reftype;
		return $xlated_reftype eq $_[1];
	}
}

sub check_ref($;$) {
	unless(&is_ref) {
		die "argument is not a reference to plain ".
			(@_ == 2 ? lc($_[1]) : "object")."\n";
	}
}

=back

=head2 References to Blessed Objects

=over

=item is_blessed(ARG)

=item check_blessed(ARG)

Check whether I<ARG> is a reference to a blessed object.  If it is,
then the class into which the object was blessed can be determined using
L</blessed_class>.

=item is_blessed(ARG, CLASS)

=item check_blessed(ARG, CLASS)

Check whether I<ARG> is a reference to a blessed object that claims to
be an instance of I<CLASS> (via its C<isa> method; see L<perlobj/isa>).
I<CLASS> must be a string, naming a Perl class.

=cut

sub is_blessed($;$) {
	die "class argument is not a string\n"
		if @_ == 2 && !is_string($_[1]);
	return defined(blessed($_[0])) && (@_ != 2 || $_[0]->isa($_[1]));
}

sub check_blessed($;$) {
	unless(&is_blessed) {
		die "argument is not a reference to blessed ".
			(@_ == 2 ? $_[1] : "object")."\n";
	}
}

=item blessed_class(ARG)

Returns C<undef> if I<ARG> is not a reference to a blessed object.
Otherwise, returns the class into which the object is blessed.

C<ref> (see L<perlfunc/ref>) gives the same result on references
to blessed objects, but different results on other types of value.
C<blessed_class> is actually identical to L<Scalar::Util/blessed>.

=cut

*blessed_class = \&blessed;

=item is_strictly_blessed(ARG)

=item check_strictly_blessed(ARG)

Check whether I<ARG> is a reference to a blessed object, identically
to L</is_blessed>.  This exists only for symmetry; the useful form of
C<is_strictly_blessed> appears below.

=item is_strictly_blessed(ARG, CLASS)

=item check_strictly_blessed(ARG, CLASS)

Check whether I<ARG> is a reference to an object blessed into I<CLASS>
exactly.  I<CLASS> must be a string, naming a Perl class.  Because this
excludes subclasses, this is rarely what one wants, but there are some
specialised occasions where it is useful.

=cut

sub is_strictly_blessed($;$) {
	return &is_blessed unless @_ == 2;
	die "class argument is not a string\n" unless is_string($_[1]);
	my $blessed = blessed($_[0]);
	return defined($blessed) && $blessed eq $_[1];
}

sub check_strictly_blessed($;$) {
	return &check_blessed unless @_ == 2;
	unless(&is_strictly_blessed) {
		die "argument is not a reference to strictly blessed $_[1]\n";
	}
}

=item is_able(ARG)

=item check_able(ARG)

Check whether I<ARG> is a reference to a blessed object, identically
to L</is_blessed>.  This exists only for symmetry; the useful form of
C<is_able> appears below.

=item is_able(ARG, METHODS)

=item check_able(ARG, METHODS)

Check whether I<ARG> is a reference to a blessed object that claims to
implement the methods specified by I<METHODS> (via its C<can> method;
see L<perlobj/can>).  I<METHODS> must be either a single method name or
a reference to an array of method names.  Each method name is a string.
This interface check is often more appropriate than a direct ancestry
check (such as L</is_blessed> performs).

=cut

sub _check_methods_arg($) {
	return if &is_string;
	die "methods argument is not a string or array\n"
		unless is_ref($_[0], "ARRAY");
	foreach(@{$_[0]}) {
		die "method name is not a string\n" unless is_string($_);
	}
}

sub is_able($;$) {
	return &is_blessed unless @_ == 2;
	_check_methods_arg($_[1]);
	return 0 unless defined blessed $_[0];
	foreach my $method (ref($_[1]) eq "" ? $_[1] : @{$_[1]}) {
		return 0 unless $_[0]->can($method);
	}
	return 1;
}

sub check_able($;$) {
	return &check_blessed unless @_ == 2;
	_check_methods_arg($_[1]);
	unless(defined blessed $_[0]) {
		my $desc = ref($_[1]) eq "" ?
				"method \"$_[1]\""
			: @{$_[1]} == 0 ?
				"at all"
			:
				"method \"".$_[1]->[0]."\"";
		die "argument is not able to perform $desc\n";
	}
	foreach my $method (ref($_[1]) eq "" ? $_[1] : @{$_[1]}) {
		die "argument is not able to perform method \"$method\"\n"
			unless $_[0]->can($method);
	}
}

=back

=head1 BUGS

Probably ought to handle something like L<Params::Validate>'s scalar
type specification system, which makes much the same distinctions.

=head1 SEE ALSO

L<Data::Float>,
L<Data::Integer>,
L<Params::Validate>,
L<Scalar::Number>,
L<Scalar::Util>

=head1 AUTHOR

Andrew Main (Zefram) <zefram@fysh.org>

=head1 COPYRIGHT

Copyright (C) 2004, 2006, 2007, 2009, 2010
Andrew Main (Zefram) <zefram@fysh.org>

Copyright (C) 2009, 2010 PhotoBox Ltd

=head1 LICENSE

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
