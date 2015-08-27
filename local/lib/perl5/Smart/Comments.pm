package Smart::Comments;

our $VERSION = '1.000005';

use warnings;
use strict;
use Carp;

use List::Util qw(sum);

use Filter::Simple;

my $maxwidth           = 69;  # Maximum width of display
my $showwidth          = 35;  # How wide to make the indicator
my $showstarttime      = 6;   # How long before showing time-remaining estimate
my $showmaxtime        = 10;  # Don't start estimate if less than this to go
my $whilerate          = 30;  # Controls the rate at which while indicator grows
my $minfillwidth       = 5;   # Fill area must be at least this wide
my $average_over       = 5;   # Number of time-remaining estimates to average
my $minfillreps        = 2;   # Minimum size of a fill and fill cap indicator
my $forupdatequantum   = 0.01;  # Only update every 1% of elapsed distance

# Synonyms for asserts and requirements...
my $require = qr/require|ensure|assert|insist/;
my $check   = qr/check|verify|confirm/;

# Horizontal whitespace...
my $hws     = qr/[^\S\n]/;

# Optional colon...
my $optcolon = qr/$hws*;?/;

# Automagic debugging as well...
my $DBX = '$DB::single = $DB::single = 1;';

# Implement comments-to-code source filter...
FILTER {
    shift;        # Don't need the package name
    s/\r\n/\n/g;  # Handle win32 line endings

    # Default introducer pattern...
    my $intro = qr/#{3,}/;

    # Handle args...
    my @intros;
    while (@_) {
        my $arg = shift @_;

        if ($arg =~ m{\A -ENV \Z}xms) {
            my $env =  $ENV{Smart_Comments} || $ENV{SMART_COMMENTS}
                    || $ENV{SmartComments}  || $ENV{SMARTCOMMENTS}
                    ;

            return if !$env;   # i.e. if no filtering

            if ($env !~ m{\A \s* 1 \s* \Z}xms) {
                unshift @_, split m{\s+|\s*:\s*}xms, $env;
            }
        }
        else {
            push @intros, $arg;
        }
    }

    if (my @unknowns = grep {!/$intro/} @intros) {
        croak "Incomprehensible arguments: @unknowns\n",
              "in call to 'use Smart::Comments'";
    }

    # Make non-default introducer pattern...
    if (@intros) {
        $intro = '(?-x:'.join('|',@intros).')(?!\#)';
    }

    # Preserve DATA handle if any...
    if (s{ ^ __DATA__ \s* $ (.*) \z }{}xms) {
        no strict qw< refs >;
        my $DATA = $1;
        open *{caller(1).'::DATA'}, '<', \$DATA or die "Internal error: $!";
    }

    # Progress bar on a for loop...
    s{ ^ $hws* ( (?: [^\W\d]\w*: \s*)? for(?:each)? \s* (?:my)? \s* (?:\$ [^\W\d]\w*)? \s* ) \( ([^;\n]*?) \) \s* \{
            [ \t]* $intro \s (.*) \s* $
     }
     { _decode_for($1, $2, $3) }xgem;

    # Progress bar on a while loop...
    s{ ^ $hws* ( (?: [^\W\d]\w*: \s*)? (?:while|until) \s* \( .*? \) \s* ) \{
            [ \t]* $intro \s (.*) \s* $
     }
     { _decode_while($1, $2) }xgem;

    # Progress bar on a C-style for loop...
    s{ ^ $hws* ( (?: [^\W\d]\w*: \s*)? for \s* \( .*? ; .*? ; .*? \) \s* ) \{
            $hws* $intro $hws (.*) $hws* $
     }
     { _decode_while($1, $2) }xgem;

    # Requirements...
    s{ ^ $hws* $intro [ \t] $require : \s* (.*?) $optcolon $hws* $ }
     { _decode_assert($1,"fatal") }gemx;

    # Assertions...
    s{ ^ $hws* $intro [ \t] $check : \s* (.*?) $optcolon $hws* $ }
     { _decode_assert($1) }gemx;

    # Any other smart comment is a simple dump.
    # Dump a raw scalar (the varname is used as the label)...
    s{ ^ $hws* $intro [ \t]+ (\$ [\w:]* \w) $optcolon $hws* $ }
     {Smart::Comments::_Dump(pref=>q{$1:},var=>[$1]);$DBX}gmx;

    # Dump a labelled scalar...
    s{ ^ $hws* $intro [ \t] (.+ :) [ \t]* (\$ [\w:]* \w) $optcolon $hws* $ }
     {Smart::Comments::_Dump(pref=>q{$1},var=>[$2]);$DBX}gmx;

    # Dump a raw hash or array (the varname is used as the label)...
    s{ ^ $hws* $intro [ \t]+ ([\@%] [\w:]* \w) $optcolon $hws* $ }
     {Smart::Comments::_Dump(pref=>q{$1:},var=>[\\$1]);$DBX}gmx;

    # Dump a labelled hash or array...
    s{ ^ $hws* $intro [ \t]+ (.+ :) [ \t]* ([\@%] [\w:]* \w) $optcolon $hws* $ }
     {Smart::Comments::_Dump(pref=>q{$1},var=>[\\$2]);$DBX}gmx;

    # Dump a labelled expression...
    s{ ^ $hws* $intro [ \t]+ (.+ :) (.+) }
     {Smart::Comments::_Dump(pref=>q{$1},var=>[$2]);$DBX}gmx;

    # Dump an 'in progress' message
    s{ ^ $hws* $intro $hws* (.+ [.]{3}) $hws* $ }
     {Smart::Comments::_Dump(pref=>qq{$1});$DBX}gmx;

    # Dump an unlabelled expression (the expression is used as the label)...
    s{ ^ $hws* $intro $hws* (.*) $optcolon $hws* $ }
     {Smart::Comments::_Dump(pref=>q{$1:},var=>Smart::Comments::_quiet_eval(q{[$1]}));$DBX}gmx;

    # An empty comment dumps an empty line...
    s{ ^ $hws* $intro [ \t]+ $ }
     {warn qq{\n};}gmx;

    # Anything else is a literal string to be printed...
    s{ ^ $hws* $intro $hws* (.*) }
     {Smart::Comments::_Dump(pref=>q{$1});$DBX}gmx;
};

sub _quiet_eval {
    local $SIG{__WARN__} = sub{};
    return scalar eval shift;
}

sub _uniq { my %seen; grep { !$seen{$_}++ } @_ }

# Converts an assertion to the equivalent Perl code...
sub _decode_assert {
    my ($assertion, $fatal) = @_;

    # Choose the right signalling mechanism...
    $fatal = $fatal ? 'die "\n"' : 'warn "\n"';

    my $dump = 'Smart::Comments::_Dump';
    use Text::Balanced qw(extract_variable extract_multiple);

    # Extract variables from assertion and enreference any arrays or hashes...
    my @vars = map { /^$hws*[%\@]/ ? "$dump(pref=>q{    $_ was:},var=>[\\$_], nonl=>1);"
                                   : "$dump(pref=>q{    $_ was:},var=>[$_],nonl=>1);"
                   }
                _uniq extract_multiple($assertion, [\&extract_variable], undef, 1);

    # Generate the test-and-report code...
    return qq{unless($assertion){warn "\\n", q{### $assertion was not true};@vars; $fatal}};
}

# Generate progress-bar code for a Perlish for loop...
my $ID = 0;
sub _decode_for {
    my ($for, $range, $mesg) = @_;

    # Give the loop a unique ID...
    $ID++;

    # Rewrite the loop with a progress bar as its first statement...
    return "my \$not_first__$ID;$for (my \@SmartComments__range__$ID = $range) { Smart::Comments::_for_progress(qq{$mesg}, \$not_first__$ID, \\\@SmartComments__range__$ID);";
}

# Generate progress-bar code for a Perlish while loop...
sub _decode_while {
    my ($while, $mesg) = @_;

    # Give the loop a unique ID...
    $ID++;

    # Rewrite the loop with a progress bar as its first statement...
    return "my \$not_first__$ID;$while { Smart::Comments::_while_progress(qq{$mesg}, \\\$not_first__$ID);";
}

# Generate approximate time descriptions...
sub _desc_time {
    my ($seconds) = @_;
    my $hours = int($seconds/3600);    $seconds -= 3600*$hours;
    my $minutes = int($seconds/60);    $seconds -= 60*$minutes;
    my $remaining;

    # Describe hours to the nearest half-hour (and say how close to it)...
    if ($hours) {
        $remaining =
          $minutes < 5   ? "about $hours hour".($hours==1?"":"s")
        : $minutes < 25  ? "less than $hours.5 hours"
        : $minutes < 35  ? "about $hours.5 hours"
        : $minutes < 55  ? "less than ".($hours+1)." hours"
        :                  "about ".($hours+1)." hours";
    }
    # Describe minutes to the nearest minute
    elsif ($minutes) {
        $remaining = "about $minutes minutes";
        chop $remaining if $minutes == 1;
    }
    # Describe tens of seconds to the nearest ten seconds...
    elsif ($seconds > 10) { 
        $seconds = int(($seconds+5)/10);
        $remaining = "about ${seconds}0 seconds";
    }
    # Never be more accurate than ten seconds...
    else {  
        $remaining = "less than 10 seconds";
    }
    return $remaining;
}

# Update the moving average of a series given the newest measurement...
my %started;
my %moving;
sub _moving_average {
    my ($context, $next) = @_;
    my $moving = $moving{$context} ||= [];
    push @$moving, $next;
    if (@$moving >= $average_over) {
        splice @$moving, 0, $#$moving-$average_over;
    }
    return sum(@$moving)/@$moving;
}

# Recognize progress bars...
my @progress_pats = (
   #    left     extending                 end marker of bar      right
   #    anchor   bar ("fill")               |    gap after bar    anchor
   #    ======   =======================   === =================  ====
   qr{^(\s*.*?) (\[\]\[\])                 ()    \s*               (\S?.*)}x,
   qr{^(\s*.*?) (\(\)\(\))                 ()    \s*               (\S?.*)}x,
   qr{^(\s*.*?) (\{\}\{\})                 ()    \s*               (\S?.*)}x,
   qr{^(\s*.*?) (\<\>\<\>)                 ()    \s*               (\S?.*)}x,
   qr{^(\s*.*?) (?>(\S)\2{$minfillreps,})  (\S+) \s{$minfillreps,} (\S.*)}x,
   qr{^(\s*.*?) (?>(\S)\2{$minfillreps,})  ()    \s{$minfillreps,} (\S.*)}x,
   qr{^(\s*.*?) (?>(\S)\2{$minfillreps,})  (\S*)                   (?=\s*$)}x,
   qr{^(\s*.*?) ()                         ()                      () \s*$ }x,
);

# Clean up components of progress bar (inserting defaults)...
sub _prog_pat {
    for my $pat (@progress_pats) {
        $_[0] =~ $pat or next;
        return ($1, $2||"", $3||"", $4||""); 
    }
    return;
}

# State information for various progress bars...
my (%count, %max, %prev_elapsed, %prev_fraction, %showing);

# Animate the progress bar of a for loop...
sub _for_progress {
    my ($mesg, $not_first, $data) = @_;
    my ($at, $max, $elapsed, $remaining, $fraction);

    # Update progress bar...
    if ($not_first) {
        # One more iteration towards the maximum...
        $at = ++$count{$data};
        $max = $max{$data};

        # How long now (both absolute and relative)...
        $elapsed = time - $started{$data};
        $fraction = $max>0 ? $at/$max : 1;

        # How much change occurred...
        my $motion = $fraction - $prev_fraction{$data};

        # Don't update if count wrapped (unlikely) or if finished
        # or if no visible change...
        return unless $not_first < 0
                   || $at == $max
                   || $motion > $forupdatequantum;

        # Guestimate how long still to go...
        $remaining = _moving_average $data,
                                    $fraction ? $elapsed/$fraction-$elapsed
                                              : 0;
    }
    # If first iteration...
    else {
        # Start at the beginning...
        $at = $count{$data} = 0;

        # Work out where the end will be...
        $max = $max{$data} = $#$data;

        # Start the clock...
        $started{$data} = time;
        $elapsed = 0;
        $fraction = 0;

        # After which, it will no longer be the first iteration.
        $_[1] = 1;  # $not_first
    }

    # Remember the previous increment fraction...
    $prev_fraction{$data} = $fraction;

    # Now draw the progress bar (if it's a valid one)...
    if (my ($left, $fill, $leader, $right) = _prog_pat($mesg)) {
        # Insert the percentage progress in place of a '%'...
        s/%/int(100*$fraction).'%'/ge for ($left, $leader, $right);

        # Work out how much space is available for the bar itself...
        my $fillwidth = $showwidth - length($left) - length($right);

        # But no less than the prespecified minimum please...
        $fillwidth = $minfillwidth if $fillwidth < $minfillwidth;

        # Make enough filler...
        my $totalfill = $fill x $fillwidth;

        # How big is the end of the bar...
        my $leaderwidth = length($leader);

        # Truncate where?
        my $fillend = $at==$max ? $fillwidth 
                    :             $fillwidth*$fraction-$leaderwidth;
        $fillend = 0 if $fillend < 0;

        # Now draw the bar, using carriage returns to overwrite it...
        print STDERR "\r", " "x$maxwidth,
                     "\r", $left,
                     sprintf("%-${fillwidth}s",
                               substr($totalfill, 0, $fillend)
                             . $leader),
                     $right;

        # Work out whether to show an ETA estimate...
        if ($elapsed >= $showstarttime &&
            $at < $max &&
            ($showing{$data} || $remaining && $remaining >= $showmaxtime)
        ) {
            print STDERR "  (", _desc_time($remaining), " remaining)";
            $showing{$data} = 1;
        }

        # Close off the line, if we're finished...
        print STDERR "\r", " "x$maxwidth, "\n" if $at >= $max;
    }
}

my %shown;
my $prev_length = -1;

# Animate the progress bar of a while loop...
sub _while_progress {
    my ($mesg, $not_first_ref) = @_;
    my $at;

    # If we've looped this one before, recover the current iteration count...
    if ($$not_first_ref) {
        $at = ++$count{$not_first_ref};
    }
    # Otherwise set the iteration count to zero...
    else {
        $at = $count{$not_first_ref} = 0;
        $$not_first_ref = 1;
    }

    # Extract the components of the progress bar...
    if (my ($left, $fill, $leader, $right) = _prog_pat($mesg)) {
        # Replace any '%' with the current iteration count...
        s/%/$at/ge for ($left, $leader, $right);

        # How much space is there for the progress bar?
        my $fillwidth = $showwidth - length($left) - length($right);

        # Make it at least the prespecified minimum amount...
        $fillwidth = $minfillwidth if $fillwidth < $minfillwidth;

        # How big is the end of the bar?
        my $leaderwidth = length($leader);

        # How big does that make the bar itself (use reciprocal growth)...
        my $length = int(($fillwidth-$leaderwidth)
                           *(1-$whilerate/($whilerate+$at)));

        # Don't update if the picture would look the same...
        return
            if length $fill && $prev_length == $length;

        # Otherwise, remember where we got to...
        $prev_length = $length;

        # And print the bar...
        print STDERR "\r", " "x$maxwidth,
                     "\r", $left,
                     sprintf("%-${fillwidth}s", substr($fill x $fillwidth, 0, $length) . $leader),
                     $right;
    }
}

# Vestigal (I think)...
#sub Assert {
#   my %arg = @_;
#   return unless $arg{pass}
#}

use Data::Dumper 'Dumper';

# Dump a variable and then reformat the resulting string more prettily...
my $prev_STDOUT = 0;
my $prev_STDERR = 0;
my %prev_caller = ( file => q{}, line => 0 );

sub _Dump {
    my %args = @_;
    my ($pref, $varref, $nonl) = @args{qw(pref var nonl)};

    # Handle timestamps and spacestamps...
    my (undef, $file, $line) = caller;
    $pref =~ s/<(?:now|time|when)>/scalar localtime()/ge;
    $pref =~ s/<(?:here|place|where)>/"$file", line $line/g;
    $pref =~ s/<(?:file)>/$file/g;
    $pref =~ s/<(?:line)>/$line/g;

    # Add a newline?
    my @caller = caller;
    my $spacer_required
        =  $prev_STDOUT != tell(*STDOUT)
        || $prev_STDERR != tell(*STDERR)
        || $prev_caller{file} ne $caller[1]
        || $prev_caller{line} != $caller[2]-1;
    $spacer_required &&= !$nonl;
    @prev_caller{qw<file line>} = @caller[1,2];

    # Handle a prefix with no actual variable...
    if ($pref && !defined $varref) {
        $pref =~ s/:$//;
        print STDERR "\n" if $spacer_required;
        warn "### $pref\n";
        $prev_STDOUT = tell(*STDOUT);
        $prev_STDERR = tell(*STDERR);
        return;
    }

    # Set Data::Dumper up for a tidy dump and do the dump...
    local $Data::Dumper::Quotekeys = 0;
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Indent    = 2;
    my $dumped = Dumper $varref;

    # Clean up the results...
    $dumped =~ s/\$VAR1 = \[\n//;
    $dumped =~ s/\s*\];\s*$//;
    $dumped =~ s/\A(\s*)//;

    # How much to shave off and put back on each line...
    my $indent  = length $1;
    my $outdent = " " x (length($pref) + 1);

    # Report "inside-out" and "flyweight" objects more cleanly...
    $dumped =~ s{bless[(] do[{]\\[(]my \$o = undef[)][}], '([^']+)' [)]}
                {<Opaque $1 object (blessed scalar)>}g;

    # Adjust the indents...
    $dumped =~ s/^[ ]{$indent}([ ]*)/### $outdent$1/gm;

    # Print the message...
    print STDERR "\n" if $spacer_required;
    warn "### $pref $dumped\n";
    $prev_STDERR = tell(*STDERR);
    $prev_STDOUT = tell(*STDOUT);
}

1; # Magic true value required at end of module
__END__

=head1 NAME

Smart::Comments - Comments that do more than just sit there


=head1 VERSION

This document describes Smart::Comments version 1.000005


=head1 SYNOPSIS

    use Smart::Comments;

    my $var = suspect_value();

    ### $var

    ### got: $var

    ### Now computing value...

    # and when looping:

    for my $big_num (@big_nums) {  ### Factoring...      done
        factor($big_num);
    }

    while ($error > $tolerance) {  ### Refining--->      done
        refine_approximation()
    }

    for (my $i=0; $i<$MAX_INT; $i++) {   ### Working===[%]     done
        do_something_expensive_with($i);
    }

  
=head1 DESCRIPTION

Smart comments provide an easy way to insert debugging and tracking code
into a program. They can report the value of a variable, track the
progress of a loop, and verify that particular assertions are true.

Best of all, when you're finished debugging, you don't have to remove them.
Simply commenting out the C<use Smart::Comments> line turns them back into
regular comments. Leaving smart comments in your code is smart because if you
needed them once, you'll almost certainly need them again later.


=head1 INTERFACE 

All smart comments start with three (or more) C<#> characters. That is,
they are regular C<#>-introduced comments whose first two (or more)
characters are also C<#>'s.

=head2 Using the Module

The module is loaded like any other:

    use Smart::Comments;

When loaded it filters the remaining code up to the next:

    no Smart::Comments;

directive, replacing any smart comments with smart code that implements the
comments behaviour.

If you're debugging an application you can also invoke it with the module from
the command-line:

    perl -MSmart::Comments $application.pl

Of course, this only enables smart comments in the application file itself,
not in any modules that the application loads.

You can also specify particular levels of smartness, by including one or more
markers as arguments to the C<use>:

    use Smart::Comments '###', '####';

These arguments tell the module to filter only those comments that start with
the same number of C<#>'s. So the above C<use> statement would "activate" any
smart comments of the form:

    ###   Smart...

    ####  Smarter...

but not those of the form:

    ##### Smartest...

This facility is useful for differentiating progress bars (see
L<Progress Bars>), which should always be active, from debugging
comments (see L<Debugging via Comments>), which should not:

    #### Debugging here...

    for (@values) {         ### Progress: 0...  100
        do_stuff();
    }

Note that, for simplicity, all smart comments described below will be
written with three C<#>'s; in all such cases, any number of C<#>'s
greater than three could be used instead.


=head2 Debugging via Comments

The simplest way to use smart comments is for debugging. The module
supports the following forms, all of which print to C<STDERR>:

=over

=item C<< ### LABEL : EXPRESSION >>

The LABEL is any sequence of characters up to the first colon. 
The EXPRESSION is any valid Perl expression, including a simple variable.
When active, the comment prints the label, followed by the value of the
expression. For example:

    ### Expected: 2 * $prediction
    ###      Got: $result

prints:

    ### Expected: 42
    ###      Got: 13


=item C<< ### EXPRESSION >>

The EXPRESSION is any valid Perl expression, including a simple
variable. When active, the comment prints the expression, followed by
the value of the expression. For example:

    ### 2 * $prediction
    ### $result

prints:

    ### 2 * $prediction: 42
    ### $result: 13


=item C<< ### TEXT... >>

The TEXT is any sequence of characters that end in three dots.
When active, the comment just prints the text, including the dots. For
example:

    ### Acquiring data...

    $data = get_data();

    ### Verifying data...

    verify_data($data);

    ### Assimilating data...

    assimilate_data($data);

    ### Tired now, having a little lie down...

    sleep 900;

would print:


    ### Acquiring data...

    ### Verifying data...

    ### Assimilating data...

    ### Tired now, having a little lie down...

as each phase commenced. This is particularly useful for tracking down
precisely where a bug is occurring. It is also useful in non-debugging
situations, especially when batch processing, as a simple progress
feedback mechanism.

Within a textual smart comment you can use the special sequence C<<
<now> >> (or C<< <time> >> or C<< <when> >>) which is replaced with a
timestamp. For example:

    ### [<now>] Acquiring data...

would produce something like:

    ### [Fri Nov 18 15:11:15 EST 2005] Acquiring data...

There are also "spacestamps": C<< <here> >>
(or C<< <loc> >> or C<< <place> >> or C<< <where> >>):

    ### Acquiring data at <loc>...

to produce something like:

    ### Acquiring data at "demo.pl", line 7...

You can also request just the filename (C<< <file> >>) or just the line
number (C<< <line> >>) to get finer control over formatting:

    ### Acquiring data at <file>[<line>]...

and produce something like:

    ### Acquiring data at demo.pl[7]...

You can, of course, use any combination of stamps in the one comment.

=back

=head2 Checks and Assertions via Comments

=over

=item C<< ### require: BOOLEAN_EXPR >>

=item C<< ### assert:  BOOLEAN_EXPR >>

=item C<< ### ensure:  BOOLEAN_EXPR >>

=item C<< ### insist:  BOOLEAN_EXPR >>

These four are synonyms for the same behaviour. The comment evaluates
the expression in a boolean context. If the result is true, nothing more
is done. If the result is false, the comment throws an exception listing
the expression, the fact that it failed, and the values of any variables
used in the expression.

For example, given the following assertion:

    ### require: $min < $result && $result < $max

if the expression evaluated false, the comment would die with the following
message:
 
    ### $min < $result && $result < $max was not true at demo.pl line 86.
    ###     $min was: 7
    ###     $result was: 1000004
    ###     $max was: 99


=item C<< ### check:   BOOLEAN_EXPR >>

=item C<< ### confirm: BOOLEAN_EXPR >>

=item C<< ### verify:  BOOLEAN_EXPR >>

These three are synonyms for the same behaviour. The comment evaluates
the expression in a boolean context. If the result is true, nothing more
is done. If the result is false, the comment prints a warning message
listing the expression, the fact that it failed, and the values of any
variables used in the expression.

The effect is identical to that of the four assertions listed earlier, except
that C<warn> is used instead of C<die>.

=back

=head2 Progress Bars

You can put a smart comment on the same line as any of the following
types of Perl loop:

    foreach my VAR ( LIST ) {       ### Progressing...   done

    for my VAR ( LIST ) {           ### Progressing...   done

    foreach ( LIST ) {              ### Progressing...   done

    for ( LIST ) {                  ### Progressing...   done

    while (CONDITION) {             ### Progressing...   done

    until (CONDITION) {             ### Progressing...   done

    for (INIT; CONDITION; INCR) {   ### Progressing...   done


In each case, the module animates the comment, causing the dots to
extend from the left text, reaching the right text on the last
iteration. For "open ended" loops (like C<while> and C-style C<for>
loops), the dots will never reach the right text and their progress
slows down as the number of iterations increases.

For example, a smart comment like:

    for (@candidates) {       ### Evaluating...     done

would be animated is the following sequence (which would appear
sequentially on a single line, rather than on consecutive lines):

    Evaluating                          done

    Evaluating......                    done

    Evaluating.............             done

    Evaluating...................       done

    Evaluating..........................done

The module animates the first sequence of three identical characters in
the comment, provided those characters are followed by a gap of at least
two whitespace characters. So you can specify different types of
progress bars. For example:

    for (@candidates) {       ### Evaluating:::     done

or:

    for (@candidates) {       ### Evaluating===     done

or:

    for (@candidates) {       ### Evaluating|||     done

If the characters to be animated are immediately followed by other
non-whitespace characters before the gap, then those other non-whitespace
characters are used as an "arrow head" or "leader" and are pushed right
by the growing progress bar. For example:

    for (@candidates) {       ### Evaluating===|    done

would animate like so:

    Evaluating|                         done

    Evaluating=====|                    done

    Evaluating============|             done

    Evaluating==================|       done

    Evaluating==========================done

If a percentage character (C<%>) appears anywhere in the comment, it is
replaced by the percentage completion. For example:

    for (@candidates) {       ### Evaluating [===|    ] % done

animates like so:

    Evaluating [|                ]   0% done

    Evaluating [===|             ]  25% done

    Evaluating [========|        ]  50% done

    Evaluating [============|    ]  75% done

    Evaluating [=================] 100% done

If the C<%> is in the "arrow head" it moves with the progress bar. For
example:

    for (@candidates) {       ### Evaluating |===[%]    |

would be animated like so:

    Evaluating |[0%]                       |

    Evaluating |=[25%]                     |

    Evaluating |========[50%]              |

    Evaluating |===============[75%]       |

    Evaluating |===========================|

For "open-ended" loops, the percentage completion is unknown, so the module
replaces each C<%> with the current iteration count. For example:

    while ($next ne $target) {       ### Evaluating |===[%]    |

would animate like so:

    Evaluating |[0]                        |

    Evaluating |=[2]                       |

    Evaluating |==[3]                      |

    Evaluating |===[5]                     |

    Evaluating |====[7]                    |

    Evaluating |=====[8]                   |

    Evaluating |======[11]                 |

Note that the non-sequential numbering in the above example is a result
of the "hurry up and slow down" algorithm that prevents open-ended
loops from ever reaching the right-hand side.

As a special case, if the progress bar is drawn as two pairs of
identical brackets:

    for (@candidates) {       ### Evaluating: [][]

    for (@candidates) {       ### Evaluating: {}{}

    for (@candidates) {       ### Evaluating: ()()

    for (@candidates) {       ### Evaluating: <><>

Then the bar grows by repeating bracket pairs:

    Evaluating: [

    Evaluating: []

    Evaluating: [][

    Evaluating: [][]

    Evaluating: [][][

etc.

Finally, progress bars don't have to have an animated component. They
can just report the loop's progress numerically:

    for (@candidates) {       ### Evaluating (% done)

which would animate (all of the same line):

    Evaluating (0% done)

    Evaluating (25% done)

    Evaluating (50% done)

    Evaluating (75% done)

    Evaluating (100% done)


=head2 Time-Remaining Estimates

When a progress bar is used with a C<for> loop, the module tracks how long
each iteration is taking and makes an estimate of how much time will be
required to complete the entire loop.

Normally this estimate is not shown, unless the estimate becomes large
enough to warrant informing the user. Specifically, the estimate will
be shown if, after five seconds, the time remaining exceeds ten seconds.
In other words, a time-remaining estimate is shown if the module
detects a C<for> loop that is likely to take more than 15 seconds in
total. For example:

    for (@seven_samurai) {      ### Fighting: [|||    ]
        fight();
        sleep 5;
    }

would be animated like so:

    Fighting: [                           ]

    Fighting: [||||                       ]

    Fighting: [|||||||||                  ]  (about 20 seconds remaining)

    Fighting: [||||||||||||||             ]  (about 20 seconds remaining)

    Fighting: [||||||||||||||||||         ]  (about 10 seconds remaining)

    Fighting: [|||||||||||||||||||||||    ]  (less than 10 seconds remaining)

    Fighting: [|||||||||||||||||||||||||||]

The precision of the reported time-remaining estimate is deliberately vague,
mainly to prevent it being annoyingly wrong.


=head1 DIAGNOSTICS

In a sense, everything this module does is a diagnostic. All comments that
print anything, print it to C<STDERR>.

However, the module itself has only one diagnostic:

=over

=item C<< Incomprehensible arguments: %s in call to 'use Smart::Comments >>

You loaded the module and passed it an argument that wasn't three-or-
more C<#>'s. Arguments like C<'###'>, C<'####'>, C<'#####'>, etc. are
the only ones that the module accepts.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Smart::Comments can make use of an environment variable from your shell:
C<Smart_Comments>. This variable can be specified either with a
true/false value (i.e. 1 or 0) or with the same arguments as may be
passed on the C<use> line when loading the module (see L<"INTERFACE">).
The following table summarizes the behaviour:

         Value of
    $ENV{Smart_Comments}          Equivalent Perl

            1                     use Smart::Comments;
            0                      no Smart::Comments;
        '###:####'                use Smart::Comments qw(### ####);
        '### ####'                use Smart::Comments qw(### ####);

To enable the C<Smart_Comments> environment variable, you need to load the
module with the C<-ENV> flag:

    use Smart::Comments -ENV;

Note that you can still specify other arguments in the C<use> statement:

    use Smart::Comments -ENV, qw(### #####);

In this case, the contents of the environment variable replace the C<-ENV> in
the argument list.


=head1 DEPENDENCIES

The module requires the following modules:

=over

=item *

Filter::Simple

=item *

version.pm

=item *

List::Util

=item *

Data::Dumper

=item *

Text::Balanced

=back

=head1 INCOMPATIBILITIES

None reported. This module is probably even relatively safe with other
Filter::Simple modules since it is very specific and limited in what
it filters.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.

This module has the usual limitations of source filters (i.e. it looks
smarter than it is).

Please report any bugs or feature requests to
C<bug-smart-comments@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Damian Conway  C<< <DCONWAY@cpan.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2005, Damian Conway C<< <DCONWAY@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
