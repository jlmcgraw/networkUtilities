=encoding ISO8859-1
=cut

package Regexp::Grammars;
use re 'eval';

use warnings;
use strict;
use 5.010;

use Scalar::Util qw< blessed reftype >;
use Data::Dumper qw< Dumper  >;

our $VERSION = '1.036';

my $anon_scalar_ref = \do{my $var};
my %MAGIC_VARS = (
    '$CAPTURE' => $anon_scalar_ref,
    '$CONTEXT' => $anon_scalar_ref,
    '$DEBUG'   => $anon_scalar_ref,
    '$INDEX'   => $anon_scalar_ref,
    '$MATCH'   => $anon_scalar_ref,
    '%ARG'     => {},
    '%MATCH'   => {},
);

my $PROBLEM_WITH_5_18 = <<'END_ERROR_MSG';
Warning: Regexp::Grammars is currently unsupported (and unsupportable)
         under Perl 5.18 due to a bug in regex parsing under that version.

         The module runs correctly under Perl 5.16 and earlier.

         The module also runs correctly under Perl 5.20 or later
         (except that one special edge-case of rule arguments is
         no longer supported: See "Parametric Subrules" in the
         module's documentation for details).
END_ERROR_MSG

# Load the module...
sub import {
    # Signal lexical scoping (active, unless something was exported)...
    $^H{'Regexp::Grammars::active'} = 1;

    # Process any regexes in module's active lexical scope...
    use overload;
    overload::constant(
        qr => sub {
            my ($raw, $cooked, $type) = @_;

            # In active scope and really a regex...
            if (_module_is_active() && $type =~ /qq?/) {
                return bless \$cooked, 'Regexp::Grammars::Precursor';
            }
            # Ignore everything else...
            else {
                return $cooked;
            }
        }
    );

    # Deal with 5.18 issues...
    if ($] >= 5.018) {
        # Issue warning...
        if ($] < 5.020) {
            require Carp;
            Carp::croak($PROBLEM_WITH_5_18);
        }

        # Deal with cases where Perl 5.18+ complains about
        # the injection of (??{...}) and (?{...})
        require re;
        re->import('eval');

        # Sanctify the standard Regexp::Grammars pseudo-variables from
        # Perl 5.18's early enforcement of strictures...
        require Lexical::Var;
        for my $magic_var (keys %MAGIC_VARS) {
            Lexical::Var->import($magic_var, $MAGIC_VARS{$magic_var});
        }
    }
}

# Deactivate module's regex effect when it is "anti-imported" with 'no'...
sub unimport {
    # Signal lexical (non-)scoping...
    $^H{'Regexp::Grammars::active'} = 0;
    require re;
    re->unimport('eval');
}

# Encapsulate the hoopy user-defined pragma interface...
sub _module_is_active {
    return (caller 1)[10]->{'Regexp::Grammars::active'};
}

my $RULE_HANDLER;
sub clear_rule_handler { undef $RULE_HANDLER; }

{
    package Regexp;

    sub with_actions {
        my ($self, $handler) = @_;
        $RULE_HANDLER = $handler;
        return $self;
    }
}

#=====[ COMPILE-TIME INTERIM REPRESENTATION OF GRAMMARS ]===================
{
    package Regexp::Grammars::Precursor;

    # Only translate precursors once...
    state %grammar_cache;

    use overload (
        # Concatenation/interpolation just concatenates to the precursor...
        q{.} => sub {
            my ($x, $y, $reversed) = @_;
            if (ref $x) { $x = ${$x} }
            if (ref $y) { $y = ${$y} }
            if ($reversed) { ($y,$x) = ($x,$y); }
            $x .= $y//q{};
            return bless \$x, 'Regexp::Grammars::Precursor';
        },

        # Using as a string (i.e. matching) preprocesses the precursor...
        q{""} => sub {
            my ($obj) = @_;
            return $grammar_cache{ overload::StrVal($$obj) }
                //= Regexp::Grammars::_build_grammar( ${$obj} );
        },

        # Everything else, as usual...
        fallback => 1,
    );
}


#=====[ SUPPORT FOR THE INTEGRATED DEBUGGER ]=========================

# All messages go to STDERR by default...
*Regexp::Grammars::LOGFILE = *STDERR{IO};

# Debugging levels indicate where to stop...
our %DEBUG_LEVEL = (
    same => undef,                           # No change in debugging mode
    off  => 0,                               # No more debugging
    run  => 1,   continue  => 1,             # Run to completion of regex match
                 match     => 2,   on => 2,  # Run to next successful submatch
    step => 3,   try       => 3,             # Run to next reportable event
);

# Debugging levels can be abbreviated to one character during interactions...
@DEBUG_LEVEL{ map {substr($_,0,1)} keys %DEBUG_LEVEL } = values %DEBUG_LEVEL;
$DEBUG_LEVEL{o} = $DEBUG_LEVEL{off};      # Not "on"
$DEBUG_LEVEL{s} = $DEBUG_LEVEL{step};     # Not "same"

# Width of leading context field in debugging messages is constrained...
my $MAX_CONTEXT_WIDTH = 20;
my $MIN_CONTEXT_WIDTH = 6;

sub set_context_width {
    { package Regexp::Grammars::ContextRestorer;
      sub new {
        my ($class, $old_context_width) = @_;
        bless \$old_context_width, $class;
      }
      sub DESTROY {
        my ($old_context_width_ref) = @_;
        $MAX_CONTEXT_WIDTH = ${$old_context_width_ref};
      }
    }

    my ($new_context_width) = @_;
    my $old_context_width = $MAX_CONTEXT_WIDTH;
    $MAX_CONTEXT_WIDTH = $new_context_width;
    if (defined wantarray) {
        return Regexp::Grammars::ContextRestorer->new($old_context_width);
    }
}

# Rewrite a string currently being matched, to make \n and \t visible
sub _show_metas {
    my $context_str = shift // q{};

    # Quote newlines (\n -> \\n, without using a regex)...
    my $index = index($context_str,"\n");
    while ($index >= 0) {
        substr($context_str, $index, 1, '\\n');
        $index = index($context_str,"\n",$index+2);
    }

    # Quote tabs (\t -> \\t, without using a regex)...
    $index = index($context_str,"\t");
    while ($index >= 0) {
        substr($context_str, $index, 1, '\\t');
        $index = index($context_str,"\t",$index+2);
    }

    return $context_str;
}

# Minimize whitespace in a string...
sub _squeeze_ws {
    my ($str) = @_;

    $str =~ tr/\n\t/ /;

    my $index = index($str,q{  });
    while ($index >= 0) {
        substr($str, $index, 2, q{ });
        $index = index($str,q{  },$index);
    }

    return $str;
}

# Prepare for debugging...
sub _init_try_stack {
    our (@try_stack, $last_try_pos, $last_context_str);

    # Start with a representation of the entire grammar match...
    @try_stack = ({
        subrule => '<grammar>',
        height  => 0,
        errmsg  => ' \\FAIL <grammar>',
    });

    # Initialize tracking of location and context...
    $last_try_pos     = -1;
    $last_context_str = q{};

    # Report...
    say {*Regexp::Grammars::LOGFILE} _debug_context('=>')
                . 'Trying <grammar> from position ' . pos();
}

# Create a "context string" showing where the regex is currently matching...
sub _debug_context {
    my ($fill_chars) = @_;

    # Determine minimal sufficient width for context field...
    my $field_width = length(_show_metas($_//q{}));
    if ($field_width > $MAX_CONTEXT_WIDTH) {
        $field_width = $MAX_CONTEXT_WIDTH;
    }
    elsif ($field_width < $MIN_CONTEXT_WIDTH) {
        $field_width = $MIN_CONTEXT_WIDTH;
    }

    # Get current matching position (and some additional trailing context)...
    my $context_str
        = substr(_show_metas(substr(($_//q{}).q{},pos()//0,$field_width)),0,$field_width);

    # Build the context string, handling special cases...
    our $last_context_str;
    if ($fill_chars) {
        # If caller supplied a 1- or 2-char fill sequence, use that instead...
        my $last_fill_char = length($fill_chars) > 1
                                ? substr($fill_chars,-1,1,q{})
                                : $fill_chars
                                ;
        $context_str = $fill_chars x ($field_width-1) . $last_fill_char;
    }
    else {
        # Make end-of-string visible in empty context string...
        if ($context_str eq q{}) {
            $context_str = '[eos]';
        }

        # Don't repeat consecutive identical context strings...
        if ($context_str eq $last_context_str) {
            $context_str = q{ } x $field_width;
        }
        else {
            # If not repeating, remember for next time...
            $last_context_str = $context_str;
        }
    }

    # Left justify and return context string...
    return sprintf("%-*s ",$field_width,$context_str);
}

# Show a debugging message (mainly used for compile-time errors and info)...
sub _debug_notify {
    # Single arg is a line to be printed with a null severity...
    my ($severity, @lines) = @_==1 ? (q{},@_) : @_;
    chomp @lines;

    # Formatting string for all lines...
    my $format = qq{%*s | %s\n};

    # Track previous severity and avoid repeating the same level...
    state $prev_severity = q{};
    if ($severity !~ /\S/) {
        # Do nothing
    }
    elsif ($severity eq 'info' && $prev_severity eq 'info' ) {
        $severity = q{};
    }
    else {
        $prev_severity = $severity;
    }

    # Display first line with severity indicator (unless same as previous)...
    printf {*Regexp::Grammars::LOGFILE} $format, $MIN_CONTEXT_WIDTH, $severity, shift @lines;

    # Display first line without severity indicator
    for my $next_line (@lines) {
        printf {*Regexp::Grammars::LOGFILE} $format, $MIN_CONTEXT_WIDTH, q{}, $next_line;
    }
}

# Handle user interactions during runtime debugging...
sub _debug_interact {
    my ($stack_height, $leader, $curr_frame_ref, $min_debug_level) = @_;

    our $DEBUG; # ...stores current debug level within regex

    # Only interact with terminals, and if debug level is appropriate...
    if (-t *Regexp::Grammars::LOGFILE
    &&  defined $DEBUG
    &&  ($DEBUG_LEVEL{$DEBUG}//0) >= $DEBUG_LEVEL{$min_debug_level}
    ) {
        local $/ = "\n";  # ...in case some caller is being clever
        INPUT:
        while (1) {
            my $cmd = readline // q{};
            chomp $cmd;

            # Input of 'd' means 'display current result frame'...
            if ($cmd eq 'd') {
                print {*Regexp::Grammars::LOGFILE} join "\n",
                    map { $leader . ($stack_height?'|   ':q{})
                        . '       : ' . $_
                        }
                        split "\n", q{ }x8 . substr(Dumper($curr_frame_ref),8);
                print "\t";
            }
            # Any other (valid) input changes debugging level and continues...
            else {
                if (defined $DEBUG_LEVEL{$cmd}) { $DEBUG = $cmd; }
                last INPUT;
            }
        }
    }
    # When interaction not indicated, just complete the debugging line...
    else {
        print {*Regexp::Grammars::LOGFILE} "\n";
    }
}

# Handle reporting of unsuccessful match attempts...
sub _debug_handle_failures {
    my ($stack_height, $subrule, $in_match) = @_;
    our @try_stack;

    # Unsuccessful match attempts leave "leftovers" on the attempt stack...
    CLEANUP:
    while (@try_stack && $try_stack[-1]{height} >= $stack_height) {
        # Grab record of (potentially) unsuccessful attempt...
        my $error_ref = pop @try_stack;

        # If attempt was the one whose match is being reported, go and report...
        last CLEANUP if $in_match
                     && $error_ref->{height} == $stack_height
                     && $error_ref->{subrule} eq $subrule;

        # Otherwise, report the match failure...
        say {*Regexp::Grammars::LOGFILE} _debug_context(q{ }) . $error_ref->{errmsg};
    }
}

# Handle attempts to call non-existent subrules...
sub _debug_fatal {
    my ($naughty_construct) = @_;

    print {*Regexp::Grammars::LOGFILE}
        "_________________________________________________________________\n",
        "Fatal error: Entire parse terminated prematurely while attempting\n",
        "             to call non-existent rule: $naughty_construct\n",
        "_________________________________________________________________\n";
    $@ = "Entire parse terminated prematurely while attempting to call non-existent rule: $naughty_construct";
}

# Handle objrules that don't return hashes...
sub _debug_non_hash {
    my ($obj, $name) = @_;

    # If the object is okay, no further action required...
    return q{} if reftype($obj) eq 'HASH';

    # Generate error messages...
    print {*Regexp::Grammars::LOGFILE}
    "_________________________________________________________________\n",
    "Fatal error: <objrule: $name> returned a non-hash-based object\n",
    "_________________________________________________________________\n";
    $@ = "<objrule: $name> returned a non-hash-based object";

    return '(*COMMIT)(*FAIL)';
}


# Print a <log:...> message in context...
sub _debug_logmsg {
    my ($stack_height, @msg) = @_;

    # Determine indent for messages...
    my $leader = _debug_context() . q{|   } x ($stack_height-1) . '|';

    # Report the attempt...
    print {*Regexp::Grammars::LOGFILE} map { "$leader$_\n" } @msg;
}

# Print a message indicating a (sub)match attempt...
sub _debug_trying {
    my ($stack_height, $curr_frame_ref, $subrule) = @_;

    # Clean up after any preceding unsuccessful attempts...
    _debug_handle_failures($stack_height, $subrule);

    # Determine indent for messages...
    my $leader = _debug_context() . q{|   } x ($stack_height-2);

    # Detect and report any backtracking prior to this attempt...
    our $last_try_pos //= 0;  #...Stores the pos() of the most recent match attempt?
    my $backtrack_distance = $last_try_pos - pos();
    if ($backtrack_distance > 0) {
        say {*Regexp::Grammars::LOGFILE} ' <' . q{~} x (length(_debug_context(q{ }))-3) . q{ }
                    . q{|   } x ($stack_height-2)
                    . qq{|...Backtracking $backtrack_distance char}
                    . ($backtrack_distance > 1 ? q{s} : q{})
                    . q{ and trying new match}
                    ;
    }

    # Report the attempt...
    print {*Regexp::Grammars::LOGFILE} $leader, "|...Trying $subrule\t";

    # Handle user interactions during debugging...
    _debug_interact($stack_height, $leader, $curr_frame_ref, 'step');

    # Record the attempt, for later error handling in _debug_matched()...
    if ($subrule ne 'next alternative') {
        our @try_stack;
        push @try_stack, {
            height  => $stack_height,
            subrule => $subrule,
            # errmsg should align under:              |...Trying $subrule\t
            errmsg  => q{|   } x ($stack_height-2) . "|    \\FAIL $subrule",
        };
    }
    $last_try_pos = pos();
}

# Print a message indicating a successful (sub)match...
sub _debug_matched {
    my ($stack_height, $curr_frame_ref, $subrule, $matched_text) = @_;

    # Clean up any intervening unsuccessful attempts...
    _debug_handle_failures($stack_height, $subrule, 'in match');

    # Build debugging message...
    my $debug_context = _debug_context();
    my $leader  = $debug_context . q{|   } x ($stack_height-2);
    my $message = ($stack_height ? '|   ' : q{})
                . " \\_____$subrule matched ";
    my $filler  = $stack_height
                    ? '|   ' . q{ } x (length($message)-4)
                    :          q{ } x  length($message);

    our $last_try_pos //= 0;  #...Stores the pos() of the most recent match attempt?

    # Report if match required backtracking...
    my $backtrack_distance = $last_try_pos - (pos()//0);
    if ($backtrack_distance > 0) {
        say {*Regexp::Grammars::LOGFILE} ' <' . q{~} x (length(_debug_context(q{ }))-3) . q{ }
                    . q{|   } x ($stack_height-2)
                    . qq{|...Backtracking $backtrack_distance char}
                    . ($backtrack_distance > 1 ? q{s} : q{})
                    . qq{ and rematching $subrule}
                    ;
    }
    $last_try_pos = pos();

    # Format match text (splitting multi-line texts and indent them correctly)...
    $matched_text =  defined($matched_text)
        ? $matched_text = q{'} . join("\n$leader$filler", split "\n", $matched_text) . q{'}
        : q{};

    # Print match message...
    print {*Regexp::Grammars::LOGFILE} $leader . $message . $matched_text . qq{\t};

    # Check for user interaction...
    _debug_interact($stack_height, $leader, $curr_frame_ref, $stack_height ?  'match' : 'run');
}

# Print a message indicating a successful (sub)match...
sub _debug_require {
    my ($stack_height, $condition, $succeeded) = @_;

    # Build debugging message...
    my $debug_context = _debug_context();
    my $leader  = $debug_context . q{|   } x ($stack_height-1);
    my $message1 = ($stack_height ? '|...' : q{})
                 . "Testing condition: $condition"
                 ;
    my $message2 = ($stack_height ? '|   ' : q{})
                 . " \\_____"
                 . ($succeeded ? 'Satisified' : 'FAILED')
                 ;

    # Report if match required backtracking...
    our $last_try_pos;
    my $backtrack_distance = $last_try_pos - pos();
    if ($backtrack_distance > 0) {
        say {*Regexp::Grammars::LOGFILE} ' <' . q{~} x (length(_debug_context(q{ }))-3) . q{ }
                    . q{|   } x ($stack_height-1)
                    . qq{|...Backtracking $backtrack_distance char}
                    . ($backtrack_distance > 1 ? q{s} : q{})
                    . qq{ and rematching}
                    ;
    }

    # Remember where the condition was tried...
    $last_try_pos = pos();

    # Print match message...
    say {*Regexp::Grammars::LOGFILE} $leader . $message1;
    say {*Regexp::Grammars::LOGFILE} $leader . $message2;
}

# Print a message indicating a successful store-result-of-code-block...
sub _debug_executed {
    my ($stack_height, $curr_frame_ref, $subrule, $value) = @_;

    # Build message...
    my $leader   = _debug_context() . q{|   } x ($stack_height-2);
    my $message  = "|...Action $subrule\n";
    my $message2 = "|   saved value: '";
    $message    .= $leader . $message2;
    my $filler   = q{ } x length($message2);

    # Split multiline results over multiple lines (properly indented)...
    $value = join "\n$leader$filler", split "\n", $value;

    # Report the action...
    print {*Regexp::Grammars::LOGFILE} $leader . $message . $value . qq{'\t};

    # Check for user interaction...
    _debug_interact($stack_height, $leader, $curr_frame_ref, 'match');
}

# Create the code to be inserted into the regex to facilitate debugging...
sub _build_debugging_statements {
    my ($debugging_active, $subrule, $extra_pre_indent) = @_;

    return (q{}, q{}) if ! $debugging_active;;

    $extra_pre_indent //= 0;

    $subrule = "q{$subrule}";

    return (
      qq{ Regexp::Grammars::_debug_trying(\@Regexp::Grammars::RESULT_STACK+$extra_pre_indent, \$Regexp::Grammars::RESULT_STACK[-2+$extra_pre_indent], $subrule)
            if \$Regexp::Grammars::DEBUG_LEVEL{\$Regexp::Grammars::DEBUG};
        },
      qq{ Regexp::Grammars::_debug_matched(\@Regexp::Grammars::RESULT_STACK+1, \$Regexp::Grammars::RESULT_STACK[-1], $subrule, \$^N)
            if \$Regexp::Grammars::DEBUG_LEVEL{\$Regexp::Grammars::DEBUG};
        },
    );
}

sub _build_raw_debugging_statements {
    my ($debugging_active, $subpattern, $extra_pre_indent) = @_;

    return (q{}, q{}) if ! $debugging_active;

    $extra_pre_indent //= 0;

    if ($subpattern eq '|') {
        return (
        q{},
        qq{
            (?{;Regexp::Grammars::_debug_trying(\@Regexp::Grammars::RESULT_STACK+$extra_pre_indent,
              \$Regexp::Grammars::RESULT_STACK[-2+$extra_pre_indent], 'next alternative')
                if \$Regexp::Grammars::DEBUG_LEVEL{\$Regexp::Grammars::DEBUG};})
            },
        );
    }
    else {
        return (
        qq{
            (?{;Regexp::Grammars::_debug_trying(\@Regexp::Grammars::RESULT_STACK+$extra_pre_indent,
              \$Regexp::Grammars::RESULT_STACK[-2+$extra_pre_indent], q{subpattern /$subpattern/}, \$^N)
                if \$Regexp::Grammars::DEBUG_LEVEL{\$Regexp::Grammars::DEBUG};})
            },
        qq{
            (?{;Regexp::Grammars::_debug_matched(\@Regexp::Grammars::RESULT_STACK+1,
              \$Regexp::Grammars::RESULT_STACK[-1], q{subpattern /$subpattern/}, \$^N)
                if \$Regexp::Grammars::DEBUG_LEVEL{\$Regexp::Grammars::DEBUG};})
            },
        );
    }
}


#=====[ SUPPORT FOR AUTOMATIC TIMEOUTS ]=========================

sub _test_timeout {
    our ($DEBUG, $TIMEOUT);

    return q{} if time() < $TIMEOUT->{'limit'};

    my $duration = "$TIMEOUT->{duration} second"
                 . ( $TIMEOUT->{duration} == 1 ? q{} : q{s} );

    if (defined($DEBUG) && $DEBUG ne 'off') {
        my $leader   = _debug_context(q{ });
        say {*LOGFILE} $leader . '|';
        say {*LOGFILE} $leader . "|...Invoking <timeout: $TIMEOUT->{duration}>";
        say {*LOGFILE} $leader . "|   \\_____No match after $duration";
        say {*LOGFILE} $leader . '|';
        say {*LOGFILE} $leader . " \\FAIL <grammar>";
    }

    if (! @!) {
        @! = "Internal error: Timed out after $duration (as requested)";
    }
    return q{(*COMMIT)(*FAIL)};
}


#=====[ SUPPORT FOR UPDATING THE RESULT STACK ]=========================

# Create a clone of the current result frame with an new key/value...
sub _extend_current_result_frame_with_scalar {
    my ($stack_ref, $key, $value) = @_;

    # Autovivify null stacks (only occur when grammar invokes no subrules)...
    if (!@{$stack_ref}) {
        $stack_ref = [{}];
    }

    # Copy existing frame, appending new value so it overwrites any old value...
    my $cloned_result_frame = {
        %{$stack_ref->[-1]},
        $key => $value,
    };

    # Make the copy into an object, if the original was one...
    if (my $class = blessed($stack_ref->[-1])) {
        bless $cloned_result_frame, $class;
    }

    return $cloned_result_frame;
}

# Create a clone of the current result frame with an additional key/value
# (As above, but preserving the "listiness" of the key being added to)...
sub _extend_current_result_frame_with_list {
    my ($stack_ref, $key, $value) = @_;

    # Copy existing frame, appending new value to appropriate element's list...
    my $cloned_result_frame = {
        %{$stack_ref->[-1]},
        $key => [
            @{$stack_ref->[-1]{$key}//[]},
            $value,
        ],
    };

    # Make the copy into an object, if the original was one...
    if (my $class = blessed($stack_ref->[-1])) {
        bless $cloned_result_frame, $class;
    }

    return $cloned_result_frame;
}

# Pop current result frame and add it to a clone of previous result frame
# (flattening it if possible, and preserving any blessing)...
sub _pop_current_result_frame {
    my ($stack_ref, $key, $original_name, $value) = @_;

    # Where are we in the stack?
    my $curr_frame   = $stack_ref->[-1];
    my $caller_frame = $stack_ref->[-2];

    # Track which frames are objects...
    my $is_blessed_curr   = blessed($curr_frame);
    my $is_blessed_caller = blessed($caller_frame);

    # Remove "private" captures (i.e. those starting with _)...
    delete @{$curr_frame}{grep {substr($_,0,1) eq '_'} keys %{$curr_frame} };

    # Remove "nocontext" marker...
    my $nocontext = delete $curr_frame->{'~'};

    # Build a clone of the current frame...
    my $cloned_result_frame
        = exists $curr_frame->{'='}                                  ? $curr_frame->{'='}
        : $is_blessed_curr || length(join(q{}, keys %{$curr_frame})) ? { q{} => $value, %{$curr_frame} }
        : keys %{$curr_frame}                                        ? $curr_frame->{q{}}
        :                                                              $value
        ;

    # Apply any appropriate handler...
    if ($RULE_HANDLER) {
        if ($RULE_HANDLER->can($original_name) || $RULE_HANDLER->can('AUTOLOAD')) {
            my $replacement_result_frame
                = $RULE_HANDLER->$original_name($cloned_result_frame);
            if (defined $replacement_result_frame) {
                $cloned_result_frame = $replacement_result_frame;
            }
        }
    }

    # Remove capture if not requested...
    if ($nocontext && ref $cloned_result_frame eq 'HASH' && keys %{$cloned_result_frame} > 1) {
        delete $cloned_result_frame->{q{}};
    }

    # Nest a clone of current frame inside a clone of the caller frame...
    my $cloned_caller_frame = {
        %{$caller_frame//{}},
        $key => $cloned_result_frame,
    };

    # Make the copies into objects, if the originals were...
    if ($is_blessed_curr && !exists $curr_frame->{'='} ) {
        bless $cloned_caller_frame->{$key}, $is_blessed_curr;
    }
    if ($is_blessed_caller) {
        bless $cloned_caller_frame, $is_blessed_caller;
    }

    return $cloned_caller_frame;
}

# Pop current result frame and add it to a clone of previous result frame
# (flattening it if possible, and preserving any blessing)
# (As above, but preserving listiness of key being added to)...
sub _pop_current_result_frame_with_list {
    my ($stack_ref, $key, $original_name, $value) = @_;

    # Where are we in the stack?
    my $curr_frame   = $stack_ref->[-1];
    my $caller_frame = $stack_ref->[-2];

    # Track which frames are objects...
    my $is_blessed_curr = blessed($curr_frame);
    my $is_blessed_caller = blessed($caller_frame);

    # Remove "private" captures (i.e. those starting with _)...
    delete @{$curr_frame}{grep {substr($_,0,1) eq '_'} keys %{$curr_frame} };

    # Remove "nocontext" marker...
    my $nocontext = delete $curr_frame->{'~'};

    # Clone the current frame...
    my $cloned_result_frame
        = exists $curr_frame->{'='}                                  ? $curr_frame->{'='}
        : $is_blessed_curr || length(join(q{}, keys %{$curr_frame})) ? { q{} => $value, %{$curr_frame} }
        : keys %{$curr_frame}                                        ? $curr_frame->{q{}}
        :                                                              $value
        ;

    # Apply any appropriate handler...
    if ($RULE_HANDLER) {
        if ($RULE_HANDLER->can($original_name) || $RULE_HANDLER->can('AUTOLOAD')) {
            my $replacement_result_frame
                = $RULE_HANDLER->$original_name($cloned_result_frame);
            if (defined $replacement_result_frame) {
                $cloned_result_frame = $replacement_result_frame;
            }
        }
    }

    # Remove capture if not requested...
    if ($nocontext && ref $cloned_result_frame eq 'HASH' && keys %{$cloned_result_frame} > 1) {
        delete $cloned_result_frame->{q{}};
    }

    # Append a clone of current frame inside a clone of the caller frame...
    my $cloned_caller_frame = {
            %{$caller_frame},
            $key => [
                @{$caller_frame->{$key}//[]},
                $cloned_result_frame,
            ],
        };

    # Make the copies into objects, if the originals were...
    if ($is_blessed_curr && !exists $curr_frame->{'='} ) {
        bless $cloned_caller_frame->{$key}[-1], $is_blessed_curr;
    }
    if ($is_blessed_caller) {
        bless $cloned_caller_frame, $is_blessed_caller;
    }

    return $cloned_caller_frame;
}


#=====[ MISCELLANEOUS CONSTANTS ]=========================

# Namespace in which grammar inheritance occurs...
my $CACHE = 'Regexp::Grammars::_CACHE_::';
my $CACHE_LEN = length $CACHE;
my %CACHE; #...for subrule tracking

# This code inserted at the start of every grammar regex
#    (initializes the result stack cleanly and backtrackably, via local)...
my $PROLOGUE = q{((?{; @! = () if !pos;
                       local @Regexp::Grammars::RESULT_STACK
                           = (@Regexp::Grammars::RESULT_STACK, {});
                       local $Regexp::Grammars::TIMEOUT = { limit => -1>>1 };
                       local $Regexp::Grammars::DEBUG = 'off' }) };

# This code inserted at the end of every grammar regex
#    (puts final result in %/. Also defines default <ws>, <hk>, etc.)...
my $EPILOGUE = q{)(?{; $Regexp::Grammars::RESULT_STACK[-1]{q{}} //= $^N;;
         local $Regexp::Grammars::match_frame = pop @Regexp::Grammars::RESULT_STACK;
         delete @{$Regexp::Grammars::match_frame}{
                    '~', grep {substr($_,0,1) eq '_'} keys %{$Regexp::Grammars::match_frame}
                };
         if (exists $Regexp::Grammars::match_frame->{'='}) {
            if (ref($Regexp::Grammars::match_frame->{'='}) eq 'HASH') {
                $Regexp::Grammars::match_frame
                    = $Regexp::Grammars::match_frame->{'='};
            }
         }
         if (@Regexp::Grammars::RESULT_STACK) {
            $Regexp::Grammars::RESULT_STACK[-1]{'(?R)'}
                = $Regexp::Grammars::match_frame;
         }
         Regexp::Grammars::clear_rule_handler();
         */ = $Regexp::Grammars::match_frame;
    })(?(DEFINE)
        (?<ws>(?:\\s*))
        (?<hk>(?:\\S+))
        (?<matchpos> (?{; $Regexp::Grammars::RESULT_STACK[-1]{"="} = pos; }) )
        (?<matchline> (?{; $Regexp::Grammars::RESULT_STACK[-1]{"="} = 1 + substr($_,0,pos) =~ tr/\n/\n/; }) )
    )
};
my $EPILOGUE_NC = $EPILOGUE;
   $EPILOGUE_NC =~ s{ ; .* ;;}{;}xms;


#=====[ MISCELLANEOUS PATTERNS THAT MATCH USEFUL THINGS ]========

# Match an identifier...
my $IDENT     = qr{ [^\W\d] \w*+ }xms;
my $QUALIDENT = qr{ (?: $IDENT :: )*+ $IDENT }xms;

# Match balanced parentheses, taking into account \-escapes and []-escapes...
my $PARENS = qr{
    (?&VAR_PARENS)
    (?(DEFINE)
        (?<VAR_PARENS> \( (?: \\. | (?&VAR_PARENS) | (?&CHARSET) | [^][()\\]++)*+ \) )
        (?<CHARSET> \[ \^?+ \]?+ (?: \[:\w+:\] | \\. | [^]])*+ \] )

    )
}xms;

# Match a <ws:...> directive within rules...
my $WS_PATTERN = qr{<ws: ((?: \\. | [^\\()>]++ | $PARENS )*+) >}xms;


#=====[ UTILITY SUBS FOR ERROR AND WARNING MESSAGES ]========

sub _uniq {
    my %seen;
    return grep { defined $_ && !$seen{$_}++ } @_;
}

# Default translator for error messages...
my $ERRORMSG_TRANSLATOR = sub {
    my ($errormsg, $rulename, $context) = @_;

    $rulename   = 'valid input' if $rulename eq q{};
    $context  //= '<end of string>';

    # Unimplemented subrule when rulename starts with '-'...
    if (substr($rulename,0,1) eq '-') {
        $rulename = substr($rulename,1);
        return "Can't match subrule <$rulename> (not implemented)";
    }

    # Empty message converts to a "Expected...but found..." message...
    if ($errormsg eq q{}) {
        $rulename =~ tr/_/ /;
        $rulename = lc($rulename);
        return "Expected $rulename, but found '$context' instead";
    }

    # "Expecting..." messages get "but found" added...
    if (lc(substr($errormsg,0,6)) eq 'expect') {
        return "$errormsg, but found '$context' instead";
    }

    # Everything else stays "as is"...
    return $errormsg;
};

# Allow user to set translation...
sub set_error_translator {
    { package Regexp::Grammars::TranslatorRestorer;
      sub new {
        my ($class, $old_translator) = @_;
        bless \$old_translator, $class;
      }
      sub DESTROY {
        my ($old_translator_ref) = @_;
        $ERRORMSG_TRANSLATOR = ${$old_translator_ref};
      }
    }

    my ($translator_ref) = @_;
    die "Usage: set_error_translator(\$subroutine_reference)\n"
        if ref($translator_ref) ne 'CODE';

    my $old_translator_ref = $ERRORMSG_TRANSLATOR;
    $ERRORMSG_TRANSLATOR = $translator_ref;

    return defined wantarray
        ? Regexp::Grammars::TranslatorRestorer->new($old_translator_ref)
        : ();
}

# Dispatch to current translator for error messages...
sub _translate_errormsg {
    goto &{$ERRORMSG_TRANSLATOR};
}

#=====[ SUPPORT FOR TRANSLATING GRAMMAR-ENHANCED REGEX TO NATIVE REGEX ]====

# Store any specified grammars...
my %user_defined_grammar;

my %REPETITION_DESCRIPTION_FOR = (
    '+'  => 'once or more',
    '*'  => 'any number of times',
    '?'  => 'if possible',
    '+?' => 'as few times as possible',
    '*?' => 'as few times as possible',
    '??' => 'if necessary',
    '++' => 'as many times as possible',
    '*+' => 'as many times as possible',
    '?+' => 'if possible',
);

sub _translate_raw_regex {
    my ($regex, $debug_build, $debug_runtime) = @_;

    my $is_comment =  substr($regex, 0, 1) eq q{#}
                   || substr($regex, 0, 3) eq q{(?#};
    my $visible_regex = _squeeze_ws($regex);

    # Report how regex was interpreted, if requested to...
    if ($debug_build && $visible_regex ne q{} && $visible_regex ne q{ }) {
        _debug_notify( info =>
                           "   |",
                           "   |...Treating '$visible_regex' as:",
            ($is_comment ? "   |       \\ a comment (which will be ignored)"
                         : "   |       \\ normal Perl regex syntax"
            ),
        );
    }

    return q{} if $is_comment;

    # Generate run-time debugging code (if any)...
    my ($debug_pre, $debug_post)
        = _build_raw_debugging_statements($debug_runtime,$visible_regex, +1);

    # Replace negative lookahead with one that works under R::G...
    $regex =~ s{\(\?!}{(?!(?!)|}gxms;
    # ToDo: Also replace positive lookahead with one that works under R::G...
    #       This replacement should be of the form:
    #           $regex =~ s{\(\?!}{(?!(?!)|(?!(?!)|}gxms;
    #       but need to find a way to insert the extra ) at the other end

    return $debug_runtime && $regex eq '|'   ?  $regex . $debug_post
         : $debug_runtime && $regex =~ /\S/  ?  "(?:$debug_pre($regex)$debug_post)"
         :                                      $regex;
}

# Report and convert a debugging directive...
sub _translate_debug_directive {
    my ($construct, $cmd, $debug_build) = @_;

    # Report how directive was interpreted, if requested to...
    if ($debug_build) {
        _debug_notify( info =>
            "   |",
            "   |...Treating $construct as:",
            "   |       \\ Change run-time debugging mode to '$cmd'",
        );
    }

    return qq{(?{; local \$Regexp::Grammars::DEBUG = q{$cmd}; }) };
}

# Report and convert a timeout directive...
sub _translate_timeout_directive {
    my ($construct, $timeout, $debug_build) = @_;

    # Report how directive was interpreted, if requested to...
    if ($debug_build) {
        _debug_notify( info =>
            "   |",
            "   |...Treating $construct as:",
         ($timeout > 0
          ? "   |       \\ Cause the entire parse to fail after $timeout second" .  ($timeout==1 ? q{} : q{s})
          : "   |       \\ Cause the entire parse to fail immediately"
         ),
        );
    }

    return $timeout > 0
            ? qq{(?{; local \$Regexp::Grammars::TIMEOUT = { duration => $timeout, limit => time() + $timeout }; }) }
            : qq{(*COMMIT)(*FAIL)};
}

# Report and convert a <require:...> directive...
sub _translate_require_directive {
    my ($construct, $condition, $debug_build) = @_;

    $condition = substr($condition, 3, -2);

    # Report how directive was interpreted, if requested to...
    if ($debug_build) {
        _debug_notify( info =>
            "   |",
            "   |...Treating $construct as:",
            "   |       \\ Require that {$condition} is true",
        );
    }

    my $quoted_condition = $condition;
    $quoted_condition =~ s{\$}{}xms;

    return qq{(?(?{;$condition})
        (?{;Regexp::Grammars::_debug_require(
            scalar \@Regexp::Grammars::RESULT_STACK, q{$quoted_condition}, 1)
                if \$Regexp::Grammars::DEBUG_LEVEL{\$Regexp::Grammars::DEBUG}})
      | (?{;Regexp::Grammars::_debug_require(
            scalar \@Regexp::Grammars::RESULT_STACK, q{$quoted_condition}, 0)
                if \$Regexp::Grammars::DEBUG_LEVEL{\$Regexp::Grammars::DEBUG}})(?!))
    };
}


# Report and convert a <minimize:> directive...
sub _translate_minimize_directive {
    my ($construct, $debug_build) = @_;

    # Report how directive was interpreted, if requested to...
    if ($debug_build) {
        _debug_notify( info =>
            "   |",
            "   |...Treating $construct as:",
            "   |       \\ Minimize result value if possible",
        );
    }

    return q{(?{;
        if (1 == grep { $_ ne '!' && $_ ne '@' && $_ ne '~' } keys %MATCH) { # ...single alnum key
            local %Regexp::Grammars::matches = %MATCH;
            delete @Regexp::Grammars::matches{'!', '@', '~'};
            local ($Regexp::Grammars::only_key) = keys %Regexp::Grammars::matches;
            local $Regexp::Grammars::array_ref  = $MATCH{$Regexp::Grammars::only_key};
            if (ref($Regexp::Grammars::array_ref) eq 'ARRAY' && 1 == @{$Regexp::Grammars::array_ref}) {
                $MATCH = $Regexp::Grammars::array_ref->[0];
            }
        }
    })};
}

# Report and convert a debugging directive...
sub _translate_error_directive {
    my ($construct, $type, $msg, $debug_build, $subrule_name) = @_;
    $subrule_name //= 'undef';

    # Determine severity...
    my $severity = ($type eq 'error') ? 'fail' : 'non-fail';

    # Determine fatality (and build code to invoke it)...
    my $fatality = ($type eq 'fatal') ? '(*COMMIT)(*FAIL)' : q{};

    # Unpack message...
    if (substr($msg,0,3) eq '(?{') {
        $msg = 'do'. substr($msg,2,-1);
    }
    else {
        $msg = quotemeta $msg;
        $msg = qq{qq{$msg}};
    }

    # Report how directive was interpreted, if requested to...
    if ($debug_build) {
        _debug_notify( info => "   |",
                               "   |...Treating $construct as:",
            ( $type eq 'log' ? "   |       \\ Log a message to the logfile"
                             : "   |       \\ Append a $severity error message to \@!"
            ),
        );
    }

    # Generate the regex...
    return $type eq 'log'
        ? qq{(?{Regexp::Grammars::_debug_logmsg(scalar \@Regexp::Grammars::RESULT_STACK,$msg)
                if \$Regexp::Grammars::DEBUG_LEVEL{\$Regexp::Grammars::DEBUG}
          })}

        : qq{(?:(?{;local \$Regexp::Grammar::_memopos=pos();})
              (?>\\s*+((?-s).{0,$MAX_CONTEXT_WIDTH}+))
              (?{; pos() = \$Regexp::Grammar::_memopos;
              @! = Regexp::Grammars::_uniq(
                @!,
                Regexp::Grammars::_translate_errormsg($msg,q{$subrule_name},\$CONTEXT)
              ) }) (?!)|}
        . ($severity eq 'fail' ? q{(?!)} : $fatality)
        . q{)}
        ;
}

sub _translate_subpattern {
    my ($construct, $alias, $subpattern, $savemode, $postmodifier, $debug_build, $debug_runtime, $timeout, $backref)
        = @_;

    # Determine save behaviour...
    my $is_noncapturing   = $savemode eq 'noncapturing';
    my $is_listifying     = $savemode eq 'list';
    my $is_codeblock      = substr($subpattern,0,3) eq '(?{';
    my $value_saved       = $is_codeblock  ? '$^R'                    : '$^N';
    my $do_something_with = $is_codeblock  ? 'execute the code block' : 'match the pattern';
    my $result            = $is_codeblock  ? 'result'                 : 'matched substring';
    my $description       = $is_codeblock    ? substr($subpattern,2,-1)
                          : defined $backref ? $backref
                          :                    $subpattern;
    my $debug_construct
        = $is_codeblock ?  '<' . substr($alias,1,-1) . '= (?{;' . substr($subpattern,3,-2) . '})>'
        :                  $construct
        ;

    # Report how construct was interpreted, if requested to...
    my $repeatedly = $REPETITION_DESCRIPTION_FOR{$postmodifier} // q{};
    my $results  = $is_listifying && $postmodifier    ? "each $result"
                 : substr($postmodifier,0,1) eq '?'   ? "any $result"
                 : $postmodifier && !$is_noncapturing ? "only the final $result"
                 :                                      "the $result"
                 ;
    if ($debug_build) {
        _debug_notify( info =>
                                 "   |",
                                 "   |...Treating $construct as:",
                                 "   |      |  $do_something_with $description $repeatedly",
            ( $is_noncapturing ? "   |       \\ but don't save $results"
            : $is_listifying   ? "   |       \\ appending $results to \@{\$MATCH{$alias}}"
            :                    "   |       \\ saving $results in \$MATCH{$alias}"
            )
        );
    }

    # Generate run-time debugging code (if any)...
    my ($debug_pre, $debug_post)
        = _build_debugging_statements($debug_runtime,$debug_construct, +1);

    # Generate post-match result-capturing code, if match captures...
    my $post_action = $is_noncapturing
        ? q{}
        : qq{local \@Regexp::Grammars::RESULT_STACK = (
                \@Regexp::Grammars::RESULT_STACK[0..\@Regexp::Grammars::RESULT_STACK-2],
                Regexp::Grammars::_extend_current_result_frame_with_$savemode(
                    \\\@Regexp::Grammars::RESULT_STACK, $alias, $value_saved
                ),
            );}
        ;

    # Generate timeout test...
    my $timeout_test = $timeout ? q{(??{;Regexp::Grammars::_test_timeout()})} : q{};

    # Translate to standard regex code...
    return qq{$timeout_test(?{;local \@Regexp::Grammars::RESULT_STACK
                    = \@Regexp::Grammars::RESULT_STACK;$debug_pre})
                (?:($subpattern)(?{;$post_action$debug_post}))$postmodifier};
}


sub _translate_hashmatch {
    my ($construct, $alias, $hashname, $keypat, $savemode, $postmodifier, $debug_build, $debug_runtime, $timeout)
        = @_;

    # Empty or missing keypattern defaults to <.hk>...
    if (!defined $keypat || $keypat !~ /\S/) {
        $keypat = '(?&hk)'
    }
    else {
        $keypat = substr($keypat, 1, -1);
    }

    # Determine save behaviour...
    my $is_noncapturing   = $savemode eq 'noncapturing';
    my $is_listifying     = $savemode eq 'list';

    # Convert hash to hash lookup...
    my $hash_lookup = '$' . substr($hashname, 1). '{$^N}';

    # Report how construct was interpreted, if requested to...
    my $repeatedly = $REPETITION_DESCRIPTION_FOR{$postmodifier} // q{};
    my $results  = $is_listifying && $postmodifier    ? 'each matched key'
                 : substr($postmodifier,0,1) eq '?'   ? 'any matched key'
                 : $postmodifier && !$is_noncapturing ? 'only the final matched key'
                 :                                      'the matched key'
                 ;
    if ($debug_build) {
        _debug_notify( info =>
                                 "   |",
                                 "   |...Treating $construct as:",
                                 "   |      |  match a key from the hash $hashname $repeatedly",
            ( $is_noncapturing ? "   |       \\ but don't save $results"
            : $is_listifying   ? "   |       \\ appending $results to \$MATCH{$alias}"
            :                    "   |       \\ saving $results in \$MATCH{$alias}"
            )
        );
    }

    # Generate run-time debugging code (if any)...
    my ($debug_pre, $debug_post)
        = _build_debugging_statements($debug_runtime,$construct, +1);

    # Generate post-match result-capturing code, if match captures...
    my $post_action = $is_noncapturing
        ? q{}
        : qq{local \@Regexp::Grammars::RESULT_STACK = (
                \@Regexp::Grammars::RESULT_STACK[0..\@Regexp::Grammars::RESULT_STACK-2],
                Regexp::Grammars::_extend_current_result_frame_with_$savemode(
                    \\\@Regexp::Grammars::RESULT_STACK, $alias, \$^N
                ),
            );}
        ;

    # Generate timeout test...
    my $timeout_test = $timeout ? q{(??{;Regexp::Grammars::_test_timeout()})} : q{};

    # Translate to standard regex code...
    return qq{$timeout_test(?:(?{;local \@Regexp::Grammars::RESULT_STACK
                    = \@Regexp::Grammars::RESULT_STACK;$debug_pre})
                (?:($keypat)(??{exists $hash_lookup ? q{} : q{(?!)}})(?{;$post_action$debug_post})))$postmodifier};
}


# Convert a "<rule><qualifier> % <rule>" construct to pure Perl 5.10...
sub _translate_separated_list {
    my ($term, $op, $separator, $term_trans, $sep_trans,
        $ws, $debug_build, $debug_runtime, $timeout) = @_;

    # This insertion ensures backtracking upwinds the stack correctly...
    state $CHECKPOINT = q{(?{;@Regexp::Grammars::RESULT_STACK = @Regexp::Grammars::RESULT_STACK;})};

    # Translate meaningful whitespace...
    $ws = length($ws) ? q{(?&ws)} : q{};

    # Generate timeout test...
    my $timeout_test = $timeout ? q{(??{;Regexp::Grammars::_test_timeout()})} : q{};

    # Report how construct was interpreted, if requested to...
    if ($debug_build) {
        _debug_notify( info =>
            "   |",
            "   |...Treating $term $op $separator as:",
            "   |      |  repeatedly match the subrule $term",
            "   |       \\ as long as the matches are separated by matches of $separator",
        );
    }

    #  One-or-more...
    return qq{$timeout_test(?:$ws$CHECKPOINT$sep_trans$ws$term_trans)*$+}
        if $op =~ m{ [*][*]() | [+]([+?]?) \s* % | \{ 1, \}([+?]?) \s* % }xms;

    #  Zero-or-more...
    return qq{{0}$timeout_test$ws(?:$term_trans(?:$ws$CHECKPOINT$sep_trans$ws$term_trans)*$+)?$+}
        if $op =~ m{ [*]([+?]?) \s* % | \{ 0, \}([+?]?) \s* % }xms;

    #  One-or-zero...
    return qq{?$+}
        if $op =~ m{ [?]([+?]?) \s* % | \{ 0,1 \}([+?]?) \s* % }xms;

    #  Zero exactly...
    return qq{{0}$ws}
        if $op =~ m{ \{ 0 \}[+?]? \s* % }xms;

    #  N exactly...
    if ($op =~ m{ \{ (\d+) \}([+?]?) \s* % }xms ) {
        my $min = $1-1;
        return qq{{0}$timeout_test$ws(?:$term_trans(?:$ws$CHECKPOINT$sep_trans$ws$term_trans){$min}$+)}
    }

    #  Zero-to-N...
    if ($op =~ m{ \{ 0,(\d+) \}([+?]?) \s* % }xms ) {
        my $max = $1-1;
        return qq{{0}$timeout_test$ws(?:$term_trans(?:$ws$CHECKPOINT$sep_trans$ws$term_trans){0,$max}$+)?$+}
    }

    #  M-to-N and M-to-whatever...
    if ($op =~ m{ \{ (\d+),(\d*) \} ([+?]?) \s* % }xms ) {
        my $min = $1-1;
        my $max = $2 ? $2-1 : q{};
        return qq{{0}$timeout_test$ws(?:$term_trans(?:$ws$CHECKPOINT$sep_trans$ws$term_trans){$min,$max}$+)}
    }

    # Somehow we missed a case (this should never happen)...
    die "Internal error: missing case in separated list handler";
}

sub _translate_subrule_call {
    my ($source_line, $source_file, $rulename, $grammar_name, $construct, $alias,
        $subrule, $args, $savemode, $postmodifier,
        $debug_build, $debug_runtime, $timeout, $valid_subrule_names_ref, $nocontext)
            = @_;

    # Translate arg list, if provided...
    my $arg_desc;
    if ($args eq q{}) {
        $args = q{()};
    }
    elsif (substr($args,0,3) eq '(?{') {
        # Turn parencode into do block...
        $arg_desc = substr($args,3,-2);
        substr($args,1,1) = 'do';
    }
    else {
        # Turn abbreviated format into a key=>value list...
        $args =~ s{ [(,] \s* \K : (\w+) (?= \s* [,)] ) }{$1 => \$MATCH{'$1'}}gxms;
        $arg_desc = substr($args,1,-1);
    }

    # Transform qualified subrule names...
    my $simple_subrule = $subrule;
    my $start_grammar = (($simple_subrule =~ s{(.*)::}{}xms) ? $1 : "");
    if ($start_grammar !~ /^NEXT$|::/) {
        $start_grammar = caller(3).'::'.$start_grammar;
    }

    my @candidates = $start_grammar eq 'NEXT' ? _ancestry_of($grammar_name)
                   :                            _ancestry_of($start_grammar);

    # Rename fully-qualified rule call, if to ancestor grammar...
    RESOLVING:
    for my $parent_class (@candidates) {
        my $inherited_subrule = $parent_class.'::'.$simple_subrule;
        if ($CACHE{$inherited_subrule}) {
            $subrule = $inherited_subrule;
            last RESOLVING;
        }
    }

    # Replace package separators, which regex engine can't handle...
    my $internal_subrule = $subrule;
    $internal_subrule =~ s{::}{_88_}gxms;

    # Shortcircuit if unknown subrule invoked...
    if (!$valid_subrule_names_ref->{$subrule}) {
        _debug_notify( error =>
            qq{Found call to $construct inside definition of $rulename},
            qq{near $source_file line $source_line.},
            qq{But no <rule: $subrule> or <token: $subrule> was defined in the grammar},
            qq{(Did you misspell $construct? Or forget to define the rule?)},
            q{},
        );
        return "(?{Regexp::Grammars::_debug_fatal('$construct')})(*COMMIT)(*FAIL)";
    }

    # Determine save behaviour...
    my $is_noncapturing = $savemode =~ /noncapturing|lookahead/;
    my $is_listifying   = $savemode eq 'list';

    my $save_code =
       $is_noncapturing?
          q{ @Regexp::Grammars::RESULT_STACK[0..@Regexp::Grammars::RESULT_STACK-2] }
     : $is_listifying?
         qq{ \@Regexp::Grammars::RESULT_STACK[0..\@Regexp::Grammars::RESULT_STACK-3],
              Regexp::Grammars::_pop_current_result_frame_with_list(
                  \\\@Regexp::Grammars::RESULT_STACK, $alias, '$simple_subrule', \$^N
              ),
         }
     :
         qq{ \@Regexp::Grammars::RESULT_STACK[0..\@Regexp::Grammars::RESULT_STACK-3],
              Regexp::Grammars::_pop_current_result_frame(
                   \\\@Regexp::Grammars::RESULT_STACK, $alias, '$simple_subrule', \$^N
              ),
        }
     ;

    # Report how construct was interpreted, if requested to...
    my $repeatedly = $REPETITION_DESCRIPTION_FOR{$postmodifier} // q{};
    my $results  = $is_listifying && $postmodifier    ? 'each match'
                 : substr($postmodifier,0,1) eq '?'   ? 'any match'
                 :                                      'the match'
                 ;
    my $do_something_with = $savemode eq 'neglookahead' ? 'lookahead for anything except'
                          : $savemode eq 'poslookahead' ? 'lookahead for'
                          :                               'match'
                          ;
    if ($debug_build) {
        _debug_notify( info =>
                                 "   |",
                                 "   |...Treating $construct as:",
                                 "   |      |  $do_something_with the subrule <$subrule> $repeatedly",
            (defined $arg_desc ? "   |      |  passing the args: ($arg_desc)"
            :                    ()
            ),
            ( $is_noncapturing ? "   |       \\ but don't save anything"
            : $is_listifying   ? "   |       \\ appending $results to \$MATCH{$alias}"
            :                    "   |       \\ saving $results in \$MATCH{$alias}"
            ),
        );
    }

    # Generate post-match result-capturing code, if match captures...
    my ($debug_pre, $debug_post)
        = _build_debugging_statements($debug_runtime, $construct);

    # Generate timeout test...
    my $timeout_test = $timeout ? q{(??{;Regexp::Grammars::_test_timeout()})} : q{};

    # Translate to standard regex code...
    return qq{(?:$timeout_test(?{;
            local \@Regexp::Grammars::RESULT_STACK = (\@Regexp::Grammars::RESULT_STACK, {'\@'=>{$args}});
            \$Regexp::Grammars::RESULT_STACK[-2]{'~'} = $nocontext
                if \@Regexp::Grammars::RESULT_STACK >= 2;
            $debug_pre})((?&$internal_subrule))(?{;
                local \@Regexp::Grammars::RESULT_STACK = (
                    $save_code
                );$debug_post
    }))$postmodifier};
}

sub _translate_rule_def {
    my ($type, $qualifier, $name, $callname, $qualname, $body, $objectify, $local_ws) = @_;
    $qualname =~ s{::}{_88_}gxms;

    # Return object if requested...
    my $objectification =
        $objectify ? qq{(??{; local \@Regexp::Grammars::RESULT_STACK = \@Regexp::Grammars::RESULT_STACK;
                            \$Regexp::Grammars::RESULT_STACK[-1] = '$qualifier$name'->can('new')
                                ? '$qualifier$name'->new(\$Regexp::Grammars::RESULT_STACK[-1])
                                : bless \$Regexp::Grammars::RESULT_STACK[-1], '$qualifier$name';
                            Regexp::Grammars::_debug_non_hash(\$Regexp::Grammars::RESULT_STACK[-1],'$name');
                        })}
                   : q{};

    # Each rule or token becomes a DEFINE'd Perl 5.10 named capture...
    return qq{
        (?(DEFINE) $local_ws
            (?<$qualname>
            (?<$callname>
                (?{\$Regexp::Grammars::RESULT_STACK[-1]{'!'}=\$#{!};})
                (?:$body) $objectification
                (?{;\$#{!}=delete(\$Regexp::Grammars::RESULT_STACK[-1]{'!'})//0;
                           delete(\$Regexp::Grammars::RESULT_STACK[-1]{'\@'});
                })
            ))
        )
    };
}


# Locate any valid <...> sequences and replace with native regex code...
sub _translate_subrule_calls {
    my ($source_file, $source_line,
        $grammar_name,
        $grammar_spec,
        $compiletime_debugging_requested,
        $runtime_debugging_requested,
        $timeout_requested,
        $pre_match_debug,
        $post_match_debug,
        $rule_name,
        $subrule_names_ref,
        $magic_ws,
        $nocontext,
    ) = @_;

    my $pretty_rule_name = $rule_name ? ($magic_ws ? '<rule' : '<token') . ": $rule_name>"
                                      : 'main regex (before first rule)';

    # Remember the preceding construct, so as to implement the +% etc. operators...
    my $prev_construct   = q{};
    my $prev_translation = q{};
    my $curr_line_num = 1;

    # Translate all other calls (MAIN GRAMMAR FOR MODULE)...
    $grammar_spec =~ s{
      (?<list_marker> (?<ws1> \s*+)  (?<op> (?&SEPLIST_OP) ) (?<ws2> \s*+) )?
      (?<construct>
        <
        (?:
            (?<self_subrule_scalar_nocap>
                   \.                            \s* (?<subrule>(?&QUALIDENT)) \s* (?<args>(?&ARGLIST)) \s*
            )
          | (?<self_subrule_lookahead>
                   (?<sign> \? | \! )            \s* (?<subrule>(?&QUALIDENT)) \s* (?<args>(?&ARGLIST)) \s*
            )
          | (?<self_subrule_scalar>
                                                 \s* (?<subrule>(?&QUALIDENT)) \s* (?<args>(?&ARGLIST)) \s*

            )
          | (?<self_subrule_list>
                   \[                            \s* (?<subrule>(?&QUALIDENT)) \s* (?<args>(?&ARGLIST)) \s* \]
            )
          | (?<alias_subrule_scalar>
                       (?<alias>(?&IDENT)) \s* = \s* (?<subrule>(?&QUALIDENT)) \s* (?<args>(?&ARGLIST)) \s*

            )
          | (?<alias_subrule_list>
                   \[  (?<alias>(?&IDENT)) \s* = \s* (?<subrule>(?&QUALIDENT)) \s* (?<args>(?&ARGLIST)) \s* \]
            )

          | (?<self_argrule_scalar>
                                                 \s* : (?<subrule>(?&QUALIDENT)) \s*
            )
          | (?<alias_argrule_scalar>
                       (?<alias>(?&IDENT)) \s* = \s* : (?<subrule>(?&QUALIDENT)) \s*
            )
          | (?<alias_argrule_list>
                   \[  (?<alias>(?&IDENT)) \s* = \s* : (?<subrule>(?&QUALIDENT)) \s*  \]
            )

          | (?<alias_parens_scalar_nocap>
                   \.  (?<alias>(?&IDENT)) \s* = \s* (?<pattern>(?&PARENCODE)|(?&PARENS)|(?&LITERAL)) \s*
            )
          | (?<alias_parens_scalar>
                       (?<alias>(?&IDENT)) \s* = \s* (?<pattern>(?&PARENCODE)|(?&PARENS)|(?&LITERAL)) \s*
            )
          | (?<alias_parens_list>
                   \[  (?<alias>(?&IDENT)) \s* = \s* (?<pattern>(?&PARENCODE)|(?&PARENS)|(?&LITERAL)) \s* \]
            )
          | (?<alias_hash_scalar_nocap>
                                                     (?<varname>(?&HASH)) \s* (?<keypat>(?&BRACES))?  \s*
            )
          | (?<alias_hash_scalar>
                       (?<alias>(?&IDENT)) \s* = \s* (?<varname>(?&HASH)) \s* (?<keypat>(?&BRACES))?  \s*
            )
          | (?<alias_hash_list>
                   \[  (?<alias>(?&IDENT)) \s* = \s* (?<varname>(?&HASH)) \s* (?<keypat>(?&BRACES))?  \s* \]
            )
          | (?<backref>
                                                 \s* (?<slash> \\  | /) (?<subrule> [:] (?&QUALIDENT))  \s*
                |                                \s* (?<slash> \\_ | /) (?<subrule>     (?&QUALIDENT))  \s*
            )
          | (?<alias_backref>
                       (?<alias>(?&IDENT)) \s* = \s* (?<slash> \\  | /) (?<subrule> [:] (?&QUALIDENT))  \s*
                |      (?<alias>(?&IDENT)) \s* = \s* (?<slash> \\_ | /) (?<subrule>     (?&QUALIDENT))  \s*
            )
          | (?<alias_backref_list>
                   \[  (?<alias>(?&IDENT)) \s* = \s* (?<slash> \\  | /) (?<subrule> [:] (?&QUALIDENT))  \s* \]
                |  \[  (?<alias>(?&IDENT)) \s* = \s* (?<slash> \\_ | /) (?<subrule>     (?&QUALIDENT))  \s* \]
            )
          |
            (?<minimize_directive>
                    minimize \s* : \s*
            )
          |
            (?<require_directive>
                    require \s* : \s* (?<condition> (?&PARENCODE) ) \s*
            )
          |
            (?<debug_directive>
                    debug \s* : \s* (?<cmd> run | match | step | try | off | on) \s*
            )
          |
            (?<timeout_directive>
                    timeout \s* : \s* (?<timeout> \d+) \s*
            )
          |
            (?<context_directive>
                    context \s* : \s*
            )
          |
            (?<nocontext_directive>
                    nocontext \s* : \s*
            )
          |
            (?<yadaerror_directive>
                    [.][.][.]
                  | [!][!][!]
                  | [?][?][?]
            )
          |
            (?<autoerror_directive>
                    (?<error_type> error | fatal ) \s*+ : \s*+
            )
          |
            (?<error_directive>
                    (?<error_type> log | error | warning | fatal )
                    \s*+ : \s*+
                    (?<msg> (?&PARENCODE) | .+? )
                    \s*+
            )
        )
        > (?<modifier> \s* (?! (?&SEPLIST_OP) ) [?+*][?+]? | )
      |
        (?<ws_directive>
            $WS_PATTERN
        )
      |
        (?<incomplete_request>
            < [^>\n]* [>\n]
        )
      |
        (?<loose_quantifier>
            (?<! \| ) \s++ (?&QUANTIFIER)
          | (?<! \A ) \s++ (?&QUANTIFIER)
        )
      |
        (?<reportable_raw_regex>
            (?: \\[^shv]
            |   (?! (?&PARENCODE) ) (?&PARENS)
            |   (?&CHARSET)
            |   \w++
            |   \|
            )
            (?&QUANTIFIER)?
        )
      |
        (?<raw_regex>
              \s++
            | \\. (?&QUANTIFIER)?
            | \(\?!
            | \(\?\# [^)]* \)   # (?# -> old style inline comment)
            | (?&PARENCODE)
            | \# [^\n]*+
            | [^][\s()<>#\\]++
        )
    )

    (?(DEFINE)
        (?<SEPLIST_OP> \*\* | [*+?][+?]?\s*% | \{ \d+(,\d*)? \} [+?]?\s*%                                          )
        (?<PARENS>    \( (?:[?]<[=!])? (?: \\. | (?&PARENCODE) | (?&PARENS) | (?&CHARSET) | [^][()\\<>]++ )*+ \)   )
        (?<BRACES>    \{     (?: \\. | (?&BRACES)    | [^{}\\]++   )*+                              \}   )
        (?<PARENCODE> \(\?[{] (?: \\. | (?&BRACES)    | [^{}\\]++   )*+ [}]\)                            )
        (?<HASH>      \% (?&IDENT) (?: :: (?&IDENT) )*                                                   )
        (?<CHARSET>   \[ \^?+ \]?+ (?: \[:\w+:\] | \\. | [^]] )*+                                   \]   )
        (?<IDENT>     [^\W\d]\w*+                                                                        )
        (?<QUALIDENT> (?: [^\W\d]\w*+ :: )*  [^\W\d]\w*+                                                 )
        (?<LITERAL>   (?&NUMBER) | (?&STRING) | (?&VAR)                                                  )
        (?<NUMBER>    [+-]? \d++ (?:\. \d++)? (?:[eE] [+-]? \d++)?                                       )
        (?<STRING>    ' [^\\']++ (?: \\. [^\\']++ )* '                                                   )
        (?<ARGLIST>   (?&PARENCODE) | \( \s* (?&ARGS)? \s* \) | (?# NOTHING )                            )
        (?<ARGS>      (?&ARG) \s* (?: , \s* (?&ARG) \s* )*  ,?                                           )
        (?<ARG>       (?&VAR)  |  (?&KEY) \s* => \s* (?&LITERAL)                                         )
        (?<VAR>       : (?&IDENT)                                                                        )
        (?<KEY>       (?&IDENT) | (?&LITERAL)                                                            )
        (?<QUANTIFIER> [*+?][+?]? | \{ \d+,?\d* \} [+?]?                                                 )
    )
    }{
        my $curr_construct   = $+{construct};
        my $list_marker      = $+{list_marker} // q{};
        my $alias            = ($+{alias}//'MATCH') eq 'MATCH' ? q{'='} : qq{'$+{alias}'};

        # Determine and remember the necessary translation...
        my $curr_translation = do{

        # Translate subrule calls of the form: <ALIAS=(...)>...
            if (defined $+{alias_parens_scalar}) {
                my $pattern = substr($+{pattern},0,1) eq '(' ? $+{pattern} : "(?{$+{pattern}})";
                _translate_subpattern(
                    $curr_construct, $alias, $pattern, 'scalar', $+{modifier},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested, $timeout_requested,
                );
            }
            elsif (defined $+{alias_parens_scalar_nocap}) {
                my $pattern = substr($+{pattern},0,1) eq '(' ? $+{pattern} : "(?{$+{pattern}})";
                _translate_subpattern(
                    $curr_construct, $alias, $pattern, 'noncapturing', $+{modifier},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested, $timeout_requested,
                );
            }
            elsif (defined $+{alias_parens_list}) {
                my $pattern = substr($+{pattern},0,1) eq '(' ? $+{pattern} : "(?{$+{pattern}})";
                _translate_subpattern(
                    $curr_construct, $alias, $pattern, 'list', $+{modifier},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested, $timeout_requested,
                );
            }

        # Translate subrule calls of the form: <ALIAS=%HASH>...
            elsif (defined $+{alias_hash_scalar}) {
                _translate_hashmatch(
                    $curr_construct, $alias, $+{varname}, $+{keypat}, 'scalar', $+{modifier},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested,
                    $timeout_requested,
                );
            }
            elsif (defined $+{alias_hash_scalar_nocap}) {
                _translate_hashmatch(
                    $curr_construct, $alias, $+{varname}, $+{keypat}, 'noncapturing', $+{modifier},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested,
                    $timeout_requested,
                );
            }
            elsif (defined $+{alias_hash_list}) {
                _translate_hashmatch(
                    $curr_construct, $alias, $+{varname}, $+{keypat}, 'list', $+{modifier},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested,
                    $timeout_requested,
                );
            }

        # Translate subrule calls of the form: <ALIAS=RULENAME>...
            elsif (defined $+{alias_subrule_scalar}) {
                _translate_subrule_call(
                    $source_line, $source_file,
                    $pretty_rule_name,
                    $grammar_name,
                    $curr_construct, $alias, $+{subrule}, $+{args}, 'scalar', $+{modifier},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested,
                    $timeout_requested,
                    $subrule_names_ref,
                    $nocontext,
                );
            }
            elsif (defined $+{alias_subrule_list}) {
                _translate_subrule_call(
                    $source_line, $source_file,
                    $pretty_rule_name,
                    $grammar_name,
                    $curr_construct, $alias, $+{subrule}, $+{args}, 'list', $+{modifier},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested,
                    $timeout_requested,
                    $subrule_names_ref,
                    $nocontext,
                );
            }

        # Translate subrule calls of the form: <?RULENAME> and <!RULENAME>...
            elsif (defined $+{self_subrule_lookahead}) {

                # Determine type of lookahead, and work around capture problem...
                my ($type, $pre, $post) = ( 'neglookahead', '(?!(?!)|', ')' );
                if (defined $+{sign} eq '?') {
                    $type = 'poslookahead';
                    $pre  x= 2;
                    $post x= 2;
                }

                $pre . _translate_subrule_call(
                    $source_line, $source_file,
                    $pretty_rule_name,
                    $grammar_name,
                    $curr_construct, qq{'$+{subrule}'}, $+{subrule}, $+{args}, $type, q{},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested,
                    $timeout_requested,
                    $subrule_names_ref,
                    $nocontext,
                  )
                . $post;
            }
            elsif (defined $+{self_subrule_scalar_nocap}) {
                _translate_subrule_call(
                    $source_line, $source_file,
                    $pretty_rule_name,
                    $grammar_name,
                    $curr_construct, qq{'$+{subrule}'}, $+{subrule}, $+{args}, 'noncapturing', $+{modifier},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested,
                    $timeout_requested,
                    $subrule_names_ref,
                    $nocontext,
                );
            }
            elsif (defined $+{self_subrule_scalar}) {
                _translate_subrule_call(
                    $source_line, $source_file,
                    $pretty_rule_name,
                    $grammar_name,
                    $curr_construct, qq{'$+{subrule}'}, $+{subrule}, $+{args}, 'scalar', $+{modifier},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested,
                    $timeout_requested,
                    $subrule_names_ref,
                    $nocontext,
                );
            }
            elsif (defined $+{self_subrule_list}) {
                _translate_subrule_call(
                    $source_line, $source_file,
                    $pretty_rule_name,
                    $grammar_name,
                    $curr_construct, qq{'$+{subrule}'}, $+{subrule}, $+{args}, 'list', $+{modifier},
                    $compiletime_debugging_requested,
                    $runtime_debugging_requested,
                    $timeout_requested,
                    $subrule_names_ref,
                    $nocontext,
                );
            }

        # Translate subrule calls of the form: <ALIAS=:ARGNAME>...
            elsif (defined $+{alias_argrule_scalar}) {
                my $pattern = qq{(??{;\$Regexp::Grammars::RESULT_STACK[-1]{'\@'}{'$+{subrule}'} // '(?!)'})};
                _translate_subpattern(
                    $curr_construct, $alias, $pattern, 'scalar', $+{modifier},
                    $compiletime_debugging_requested, $runtime_debugging_requested, $timeout_requested,
                    "in \$ARG{'$+{subrule}'}"
                );
            }
            elsif (defined $+{alias_argrule_list}) {
                my $pattern = qq{(??{;\$Regexp::Grammars::RESULT_STACK[-1]{'\@'}{'$+{subrule}'} // '(?!)'})};
                _translate_subpattern(
                    $curr_construct, $alias, $pattern, 'list', $+{modifier},
                    $compiletime_debugging_requested, $runtime_debugging_requested, $timeout_requested,
                    "in \$ARG{'$+{subrule}'}"
                );
            }

        # Translate subrule calls of the form: <:ARGNAME>...
            elsif (defined $+{self_argrule_scalar}) {
                my $pattern = qq{(??{;\$Regexp::Grammars::RESULT_STACK[-1]{'\@'}{'$+{subrule}'} // '(?!)'})};
                _translate_subpattern(
                    $curr_construct, qq{'$+{subrule}'}, $pattern, 'noncapturing', $+{modifier},
                    $compiletime_debugging_requested, $runtime_debugging_requested, $timeout_requested,
                    "in \$ARG{'$+{subrule}'}"
                );
            }

        # Translate subrule calls of the form: <\IDENT> or </IDENT>...
            elsif (defined $+{backref} || $+{alias_backref} || $+{alias_backref_list}) {
                # Use "%ARGS" if subrule names starts with a colon...
                my $subrule = $+{subrule};
                if (substr($subrule,0,1) eq ':') {
                    substr($subrule,0,1,"\@'}{'");
                }

                my $backref = qq{\$Regexp::Grammars::RESULT_STACK[-1]{'$subrule'}};
                my $quoter  = $+{slash} eq '\\' || $+{slash} eq '\\_'
                                    ? "quotemeta($backref)"
                                    : "Regexp::Grammars::_invert_delim($backref)"
                                    ;
                my $pattern = qq{ (??{ defined $backref ? $quoter : q{(?!)}})};
                my $type = $+{backref}            ? 'noncapturing'
                         : $+{alias_backref}      ? 'scalar'
                         :                          'list'
                         ;
                _translate_subpattern(
                    $curr_construct, $alias, $pattern, $type, $+{modifier},
                    $compiletime_debugging_requested, $runtime_debugging_requested, $timeout_requested,
                    "in \$MATCH{'$subrule'}"
                );
            }

        # Translate reportable raw regexes (add debugging support)...
            elsif (defined $+{reportable_raw_regex}) {
                _translate_raw_regex( 
                    $+{reportable_raw_regex}, $compiletime_debugging_requested, $runtime_debugging_requested
                );
            }

        # Translate non-reportable raw regexes (leave as is)...
            elsif (defined $+{raw_regex}) {
                _translate_raw_regex(
                    $+{raw_regex}, $compiletime_debugging_requested
                );
            }

        # Translate directives...
            elsif (defined $+{require_directive}) {
                _translate_require_directive(
                    $curr_construct, $+{condition}, $compiletime_debugging_requested
                );
            }
            elsif (defined $+{minimize_directive}) {
                _translate_minimize_directive(
                    $curr_construct, $+{condition}, $compiletime_debugging_requested
                );
            }
            elsif (defined $+{debug_directive}) {
                _translate_debug_directive(
                    $curr_construct, $+{cmd}, $compiletime_debugging_requested
                );
            }
            elsif (defined $+{timeout_directive}) {
                _translate_timeout_directive(
                    $curr_construct, $+{timeout}, $compiletime_debugging_requested
                );
            }
            elsif (defined $+{error_directive}) {
                _translate_error_directive(
                    $curr_construct, $+{error_type}, $+{msg},
                    $compiletime_debugging_requested, $rule_name
                );
            }
            elsif (defined $+{autoerror_directive}) {
                _translate_error_directive(
                    $curr_construct, $+{error_type}, q{},
                    $compiletime_debugging_requested, $rule_name
                );
            }
            elsif (defined $+{yadaerror_directive}) {
                _translate_error_directive(
                    $curr_construct,
                    ($+{yadaerror_directive} eq '???' ?  'warning' : 'error'),
                    q{},
                    $compiletime_debugging_requested, -$rule_name
                );
            }
            elsif (defined $+{context_directive}) {
                $nocontext = 0;
                if ($compiletime_debugging_requested) {
                    _debug_notify( info => "   |",
                                           "   |...Treating $curr_construct as:",
                                           "   |       \\ Turn on context-saving for the current rule"
                    );
                }
                q{};  # Remove the directive
            }
            elsif (defined $+{nocontext_directive}) {
                $nocontext = 1;
                if ($compiletime_debugging_requested) {
                    _debug_notify( info => "   |",
                                           "   |...Treating $curr_construct as:",
                                           "   |       \\ Turn off context-saving for the current rule"
                    );
                }
                q{};  # Remove the directive
            }
            elsif (defined $+{ws_directive}) {
                if ($compiletime_debugging_requested) {
                    _debug_notify( info => "   |",
                                           "   |...Treating $curr_construct as:",
                                           "   |       \\ Change whitespace matching for the current rule"
                    );
                }
                $curr_construct;
            }

        # Something that looks like a rule call or directive, but isn't...
            elsif (defined $+{incomplete_request}) {
                my $request = $+{incomplete_request};
                my $inferred_type = $request =~ /:/ ? 'directive' : 'subrule call';
                    _debug_notify( warn =>
                        qq{Possible failed attempt to specify a $inferred_type:},
                        qq{    $request},
                        qq{near $source_file line $source_line},
                        qq{(If you meant to match literally, use: \\$request)},
                        q{},
                    );
                $request;
            }

        # A quantifier that isn't quantifying anything...
            elsif (defined $+{loose_quantifier}) {
                my $quant = $+{loose_quantifier};
                   $quant =~ s{^\s+}{};
                my $literal = quotemeta($quant);
                _debug_notify( fatal =>
                    qq{Quantifier that doesn't quantify anything: $quant},
                    qq{in declaration of $pretty_rule_name},
                    qq{near $source_file line $source_line},
                    qq{(Did you mean to match literally? If so, try: $literal)},
                    q{},
                );
                exit(1);
            }

        # There shouldn't be any other possibility...
            else {
                die qq{Internal error: this shouldn't happen!\n},
                    qq{Near '$curr_construct' in $pretty_rule_name\n};
            }
        };

        # Handle the **/*%/+%/{n,m}%/etc operators...
        if ($list_marker) {
            my $ws = $magic_ws ? $+{ws1} . $+{ws2} : q{};
            my $op = $+{op};

            $curr_translation = _translate_separated_list(
                $prev_construct,   $op, $curr_construct,
                $prev_translation, $curr_translation, $ws,
                $compiletime_debugging_requested,
                $runtime_debugging_requested, $timeout_requested,
            );
            $curr_construct = qq{$prev_construct $op $curr_construct};
        }

        # Finally, remember this latest translation, and return it...
        $prev_construct   = $curr_construct;
        $prev_translation = $curr_translation;;
    }exmsg;

    # Translate magic hash accesses...
    $grammar_spec =~ s{\$MATCH (?= \s*\{) }
                      {\$Regexp::Grammars::RESULT_STACK[-1]}xmsg;
    $grammar_spec =~ s{\$ARG (?= \s*\{) }
                      {\$Regexp::Grammars::RESULT_STACK[-1]{'\@'}}xmsg;

    # Translate magic scalars and hashes...
    state $translate_scalar = {
        q{%$MATCH}  => q{%{$Regexp::Grammars::RESULT_STACK[-1]{q{=}}}},
        q{@$MATCH}  => q{@{$Regexp::Grammars::RESULT_STACK[-1]{q{=}}}},
        q{$MATCH}   => q{$Regexp::Grammars::RESULT_STACK[-1]{q{=}}},
        q{%MATCH}   => q{%{$Regexp::Grammars::RESULT_STACK[-1]}},
        q{$CAPTURE} => q{$^N},
        q{$CONTEXT} => q{$^N},
        q{$DEBUG}   => q{$Regexp::Grammars::DEBUG},
        q{$INDEX}   => q{${\\pos()}},
        q{%ARG}     => q{%{$Regexp::Grammars::RESULT_STACK[-1]{'@'}}},
    };
    state $translatable_scalar
        = join '|', map {quotemeta $_}
                        sort {length $b <=> length $a}
                             keys %{$translate_scalar};

    $grammar_spec =~ s{ ($translatable_scalar) (?! \s* (?: \[ | \{) ) }
                      {$translate_scalar->{$1}}oxmsg;

    return $grammar_spec;
}

# Generate a "decimal timestamp" and insert in a template...
sub _timestamp {
    my ($template) = @_;

    # Generate and insert any timestamp...
    if ($template =~ /%t/) {
        my ($sec, $min, $hour, $day, $mon,   $year) = localtime;
                                     $mon++; $year+=1900;
        my $timestamp = sprintf("%04d%02d%02d.%02d%02d%02d",
                                $year, $mon, $day, $hour, $min, $sec);
        $template =~ s{%t}{$timestamp}xms;;
    }

    return $template;
}

# Open (or re-open) the requested log file...
sub _autoflush {
    my ($fh) = @_;
    my $originally_selected = select $fh;
    $|=1;
    select $originally_selected;
}

sub _open_log {
    my ($mode, $filename, $from_where) = @_;
    $from_where //= q{};

    # Special case: '-' --> STDERR
    if ($filename eq q{-}) {
        return *STDERR{IO};
    }
    # Otherwise, just open the named file...
    elsif (open my $fh, $mode, $filename) {
        _autoflush($fh);
        return $fh;
    }
    # Otherwise, generate a warning and default to STDERR...
    else {
        local *Regexp::Grammars::LOGFILE = *STDERR{IO};
        _debug_notify( warn =>
            qq{Unable to open log file '$filename'},
            ($from_where ? $from_where : ()),
            qq{($!)},
            qq{Defaulting to STDERR instead.},
            q{},
        );
        return *STDERR{IO};
    }
}

sub _invert_delim {
    my ($delim) = @_;
    $delim = reverse $delim;
    $delim =~ tr/<>[]{}()«»`'/><][}{)(»«'`/;
    return quotemeta $delim;
}

# Regex to detect if other regexes contain a grammar specification...
my $GRAMMAR_DIRECTIVE
    = qr{ < grammar: \s* (?<grammar_name> $QUALIDENT ) \s* > }xms;

# Regex to detect if other regexes contain a grammar inheritance...
my $EXTENDS_DIRECTIVE
    = qr{ < extends: \s* (?<base_grammar_name> $QUALIDENT ) \s* > }xms;

# Cache of rule/token names within defined grammars...
my %subrule_names_for;

# Build list of ancestors for a given grammar...
sub _ancestry_of {
    my ($grammar_name) = @_;

    return () if !$grammar_name;

    use mro;
    return map { substr($_, $CACHE_LEN) } @{mro::get_linear_isa($CACHE.$grammar_name, 'c3')};
}

# Detect and translate any requested grammar inheritances...
sub _extract_inheritances {
    my ($source_line, $source_file, $regex, $compiletime_debugging_requested, $derived_grammar_name) = @_;


    # Detect and remove inheritance requests...
    while ($regex =~ s{$EXTENDS_DIRECTIVE}{}xms) {
        # Normalize grammar name and report...
        my $orig_grammar_name = $+{base_grammar_name};
        my $grammar_name = $orig_grammar_name;
        if ($grammar_name !~ /::/) {
            $grammar_name = caller(2).'::'.$grammar_name;
        }

        if (exists $user_defined_grammar{$grammar_name}) {
            if ($compiletime_debugging_requested) {
                _debug_notify( info =>
                    "Processing inheritance request for $grammar_name...",
                    q{},
                );
            }

            # Specify new relationship...
            no strict 'refs';
            push @{$CACHE.$derived_grammar_name.'::ISA'}, $CACHE.$grammar_name;
        }
        else {
            _debug_notify( fatal =>
                "Inheritance from unknown grammar requested",
                "by <extends: $grammar_name> directive",
                "in regex grammar declared at $source_file line $source_line",
                q{},
            );
            exit(1);
        }
    }

    # Retrieve ancestors (but not self) in C3 dispatch order...
    my (undef, @ancestors) = _ancestry_of($derived_grammar_name);

    # Extract subrule names and implementations for ancestors...
    my %subrule_names = map { %{$subrule_names_for{$_}} } @ancestors;
    $_ = -1 for values %subrule_names;
    my $implementation
        = join "\n", map { $user_defined_grammar{$_} } @ancestors;

    return $implementation, \%subrule_names;
}

# Transform grammar-augmented regex into pure Perl 5.10 regex...
sub _build_grammar {
    my ($grammar_spec) = @_;
    $grammar_spec .= q{};

    # Check for lack of Regexp::Grammar-y constructs and short-circuit...
    if ($grammar_spec !~ m{ < (?: [.?![:%\\/]? [^\W\d]\w* [^>]* | [.?!]{3} ) > }xms) {
        return $grammar_spec;
    }

    # Remember where we parked...
    my ($source_file, $source_line) = (caller 1)[1,2];
    $source_line -= $grammar_spec =~ tr/\n//;

    # Check for dubious repeated <SUBRULE> constructs that throw away captures...
    my $dubious_line = $source_line;
    while ($grammar_spec =~ m{
           (.*?)
           (
            < (?! \[ )                     # not <[SUBRULE]>
                ( $IDENT (?: = [^>]*)? )   # but <SUBRULE> or <SUBRULE=*>
            > \s*
            (                              # followed by a quantifier...
                [+*][?+]?                  #    either symbolic
              | \{\d+(?:,\d*)?\}[?+]?      #    or numeric
            )
           )
        }gxms) {
            my ($prefix, $match, $rule, $qual) = ($1, $2, $3, $4);
            $dubious_line += $prefix =~ tr/\n//;
            _debug_notify( warn =>
                qq{Repeated subrule <$rule>$qual},
                qq{at $source_file line $dubious_line},
                qq{will only capture its final match},
                qq{(Did you mean <[$rule]>$qual instead?)},
                q{},
            );
            $dubious_line += $match =~ tr/\n//;
    }

    # Check for dubious non-backtracking <SUBRULE> constructs...
    $dubious_line = $source_line;
    while (
        $grammar_spec =~ m{
            (.*?)
            (
                <
                    (?! (?:obj)? (?:rule: | token ) )
                    ( [^>]+ )
                >
                \s*
                ( [?+*][+] | \{.*\}[+] )
            )
        }gxms) {
            my ($prefix, $match, $rule, $qual) = ($1, $2, $3, $4);
            $dubious_line += $prefix =~ tr/\n//;
            my $safe_qual = substr($qual,0,-1);
            _debug_notify( warn =>
                qq{Non-backtracking subrule call <$rule>$qual},
                qq{at $source_file line $dubious_line},
                qq{may not revert correctly during backtracking.},
                qq{(If grammar does not work, try <$rule>$safe_qual instead)},
                q{},
            );
            $dubious_line += $match =~ tr/\n//;
    }

    # Check whether a log file was specified...
    my $compiletime_debugging_requested;
    local *Regexp::Grammars::LOGFILE = *Regexp::Grammars::LOGFILE;
    my $logfile = q{-};

    my $log_where = "for regex grammar defined at $source_file line $source_line";
    $grammar_spec =~ s{ ^ [^#]* < logfile: \s* ([^>]+?) \s* > }{
        $logfile = _timestamp($1);

        # Presence of <logfile:...> implies compile-time logging...
        $compiletime_debugging_requested = 1;
        *Regexp::Grammars::LOGFILE = _open_log('>',$logfile, $log_where );

        # Delete <logfile:...> directive...
        q{};
    }gexms;

    # Look ahead for any run-time debugging or timeout requests...
    my $runtime_debugging_requested
        = $grammar_spec =~ m{
              ^ [^#]*
              < debug: \s* (run | match | step | try | on | same ) \s* >
            | \$DEBUG (?! \s* (?: \[ | \{) )
        }xms;

    my $timeout_requested
        = $grammar_spec =~ m{
              ^ [^#]*
              < timeout: \s* \d+ \s* >
        }xms;


    # Standard actions set up and clean up any regex debugging...
    # Before entire match, set up a stack of attempt records and report...
    my $pre_match_debug
        = $runtime_debugging_requested
            ? qq{(?{; *Regexp::Grammars::LOGFILE
                        = Regexp::Grammars::_open_log('>>','$logfile', '$log_where');
                      Regexp::Grammars::_init_try_stack(); })}
            : qq{(?{; *Regexp::Grammars::LOGFILE
                        = Regexp::Grammars::_open_log('>>','$logfile', '$log_where'); })}
            ;

    # After entire match, report whether successful or not...
    my $post_match_debug
        = $runtime_debugging_requested
            ? qq{(?{;Regexp::Grammars::_debug_matched(0,\\%/,'<grammar>',\$^N)})
                |(?>(?{;Regexp::Grammars::_debug_handle_failures(0,'<grammar>'); }) (?!))
                }
            : q{}
            ;

    # Remove comment lines...
    $grammar_spec =~ s{^ ([^#\n]*) \s \# [^\n]* }{$1}gxms;

    # Subdivide into rule and token definitions, preparing to process each...
    # REWRITE THIS, USING (PROBABLY NEED TO REFACTOR ALL GRAMMARS TO REUSe
    # THESE COMPONENTS:
    #   (?<PARAMLIST> \( \s* (?&PARAMS)? \s* \) | (?# NOTHING )                                          )
    #   (?<PARAMS>    (?&PARAM) \s* (?: , \s* (?&PARAM) \s* )*  ,?                                       )
    #   (?<PARAM>     (?&VAR) (?: \s* = \s* (?: (?&LITERAL) | (?&PARENCODE) ) )?                         )
    #   (?<LITERAL>   (?&NUMBER) | (?&STRING) | (?&VAR)                                                  )
    #   (?<VAR>       : (?&IDENT)                                                                        )
    my @defns = split m{
            (< (obj|)(rule|token) \s*+ :
              \s*+ ((?:${IDENT}::)*+) (?: ($IDENT) \s*+ = \s*+ )?+
              ($IDENT)
            \s* >)
        }xms, $grammar_spec;

    # Extract up list of names of defined rules/tokens...
    # (Name is every 6th item out of every seven, skipping the first item)
    my @subrule_names = @defns[ map { $_ * 7 + 6 } 0 .. ((@defns-1)/7-1) ];
    my @defns_copy = @defns[1..$#defns];
    my %subrule_names;

    # Build a look-up table of subrule names, checking for duplicates...
    my $defn_line = $source_line + $defns[0] =~ tr/\n//;
    my %first_decl_explanation;
    for my $subrule_name (@subrule_names) {
        my ($full_decl, $objectify, $type, $qualifier, $name, $callname, $body) = splice(@defns_copy, 0, 7);
        if (++$subrule_names{$subrule_name} > 1) {
            _debug_notify( warn =>
                "Redeclaration of <$objectify$type: $subrule_name>",
                "at $source_file line $defn_line",
                "will be ignored.",
                @{ $first_decl_explanation{$subrule_name} },
                q{},
            );
        }
        else {
            $first_decl_explanation{$subrule_name} = [
                "(Hidden by the earlier declaration of <$objectify$type: $subrule_name>",
                " at $source_file line $defn_line)"
            ];
        }
        $defn_line += ($full_decl.$body) =~ tr/\n//;
    }

    # Add the built-ins...
    @subrule_names{'ws', 'hk', 'matchpos', 'matchline'} = (1) x 4;

    # An empty main rule will never match anything...
    my $main_regex = shift @defns;
    if ($main_regex =~ m{\A (?: \s++ | \(\?\# [^)]* \) | \# [^\n]++ )* \z}xms) {
        _debug_notify( error =>
            "No main regex specified before rule definitions",
            "in regex grammar declared at $source_file line $source_line",
            "Grammar will never match anything.",
            "(Or did you forget a <grammar:...> specification?)",
            q{},
        );
    }

    # Compile the regex or grammar...
    my $regex = q{};
    my $grammar_name;
    my $is_grammar;

    # Is this a grammar specification?
    if ($main_regex =~ $GRAMMAR_DIRECTIVE) {
        # Normalize grammar name and report...
        $grammar_name = $+{grammar_name};
        if ($grammar_name !~ /::/) {
            $grammar_name = caller(1) . "::$grammar_name";
        }
        $is_grammar = 1;

        # Add subrule definitions to namespace...
        for my $subrule_name (@subrule_names) {
            $CACHE{$grammar_name.'::'.$subrule_name} = 1;
        }
    }
    else {
        state $dummy_grammar_index = 0;
        $grammar_name = '______' . $dummy_grammar_index++;
    }

    # Extract any inheritance information...
    my ($inherited_rules, $inherited_subrule_names)
        = _extract_inheritances(
            $source_line, $source_file,
            $main_regex,
            $compiletime_debugging_requested,
            $grammar_name
          );

    # Remove <extends:...> requests...
    $main_regex =~ s{ $EXTENDS_DIRECTIVE }{}gxms;

    # Add inherited subrule names to allowed subrule names;
    @subrule_names{ keys %{$inherited_subrule_names} }
        = values %{$inherited_subrule_names};

    # Remove comments from top-level grammar...
    $main_regex =~ s{
          \(\?\# [^)]* \)
        | (?<! \\ ) [#] [^\n]+
    }{}gxms;

    # Remove any top-level nocontext directive...
                    # 1 2     3     4
    $main_regex =~ s{^( (.*?) (\\*) (\# [^\n]*) )$}{length($3) % 2 ? $1 : $2.substr($3,0,-1)}gexms;
    my $nocontext = ($main_regex =~ s{ < nocontext \s* : \s* > }{}gxms) ? 1
                  : ($main_regex =~ s{ <   context \s* : \s* > }{}gxms) ? 0
                  :                                                       0;

    # If so, set up to save the grammar...
    if ($is_grammar) {
        # Normalize grammar name and report...
        if ($grammar_name !~ /::/) {
            $grammar_name = caller(1) . "::$grammar_name";
        }
        if ($compiletime_debugging_requested) {
            _debug_notify( info =>
                "Processing definition of grammar $grammar_name...",
                q{},
            );
        }

        # Remove the grammar directive...
        $main_regex =~ s{
            ( $GRAMMAR_DIRECTIVE
            | < debug: \s* (run | match | step | try | on | off | same ) \s* >
            )
        }{$source_line += $1 =~ tr/\n//; q{}}gexms;

        # Check for anything else in the main regex...
        if ($main_regex =~ /\A(\s*)\S/) {
            $source_line += $1 =~ tr/\n//;
            _debug_notify( warn =>
                "Unexpected item before first subrule specification",
                "in definition of <grammar: $grammar_name>",
                "at $source_file line $source_line:",
                map({ "    $_"} grep /\S/, split "\n", $main_regex),
                "(this will be ignored when defining the grammar)",
                q{},
            );
        }

        # Remember set of valid subrule names...
        $subrule_names_for{$grammar_name}
            = {
                map({ ($_ => 1) } keys %subrule_names),
                map({ ($grammar_name.'::'.$_ => 1) } grep { !/::/ } keys %subrule_names),
              };
    }
    else { #...not a grammar specification
        # Report how main regex was interpreted, if requested to...
        if ($compiletime_debugging_requested) {
            _debug_notify( info =>
                "Processing the main regex before any rule definitions",
            );
        }

        # Any actual regex is processed first...
        $regex = _translate_subrule_calls(
            $source_file, $source_line,
            $grammar_name,
            $main_regex,
            $compiletime_debugging_requested,
            $runtime_debugging_requested,
            $timeout_requested,
            $pre_match_debug,
            $post_match_debug,
            q{},                        # Expected...what?
            \%subrule_names,
            0,                          # Whitespace isn't magical
            $nocontext,
        );

        # Wrap the main regex (to ensure |'s don't segment pre and # post commands)...
        $regex = "(?:$regex)";

        # Report how construct was interpreted, if requested to...
        if ($compiletime_debugging_requested) {
            _debug_notify( q{} =>
                q{   |},
                q{    \\___End of main regex},
                q{},
            );
        }
    }

    # Update line number...
    $source_line += $main_regex =~ tr/\n//;

    #  Then iterate any following rule definitions...
    while (@defns) {
        # Grab details of each rule defn (as extracted by previous split)...
        my ($full_decl, $objectify, $type, $qualifier, $name, $callname, $body) = splice(@defns, 0, 7);
        $name //= $callname;
        my $qualified_name = $grammar_name.'::'.$callname;

        # Report how construct was interpreted, if requested to...
        if ($compiletime_debugging_requested) {
            _debug_notify( info =>
                "Defining a $type: <$callname>",
                "   |...Returns: " . ($objectify ? "an object of class '$qualifier$name'" : "a hash"),
            );
        }

        # Translate any nested <...> constructs...
        my $trans_body = _translate_subrule_calls(
            $source_file, $source_line,
            $grammar_name,
            $body,
            $compiletime_debugging_requested,
            $runtime_debugging_requested,
            $timeout_requested,
            $pre_match_debug,
            $post_match_debug,
            $callname,                # Expected...what?
            \%subrule_names,
            $type eq 'rule',          # Is whitespace magical?
            $nocontext,               # Start with the global nocontextuality
        );

        # Report how construct was interpreted, if requested to...
        if ($compiletime_debugging_requested) {
            _debug_notify( q{} =>
                q{   |},
                q{    \\___End of rule definition},
                q{},
            );
        }

        # Make allowance for possible local whitespace definitions...
        my $local_ws_defn = q{};
        my $local_ws_call = q{(?&ws)};

        # Rules make non-code literal whitespace match textual whitespace...
        if ($type eq 'rule') {
            # Implement any local whitespace definition...
            my $first_ws = 1;
            WS_DIRECTIVE:
            while ($trans_body =~ s{$WS_PATTERN}{}oxms) {
                my $defn = $1;
                if ($defn !~ m{\S}xms) {
                    _debug_notify( warn =>
                        qq{Ignoring useless empty <ws:> directive},
                        qq{in definition of <rule: $name>},
                        qq{near $source_file line $source_line},
                        qq{(Did you mean <ws> instead?)},
                        q{},
                    );
                    next WS_DIRECTIVE;
                }
                elsif (!$first_ws) {
                    _debug_notify( warn =>
                        qq{Ignoring useless extra <ws:$defn> directive},
                        qq{in definition of <rule: $name>},
                        qq{at $source_file line $source_line},
                        qq{(No more than one is permitted per rule!)},
                        q{},
                    );
                    next WS_DIRECTIVE;
                }
                else {
                    $first_ws = 0;
                }
                state $ws_counter = 0;
                $ws_counter++;
                $local_ws_defn = qq{(?<__RG_ws_$ws_counter> $defn)};
                $local_ws_call = qq{(?&__RG_ws_$ws_counter)};
            }

            # Implement auto-whitespace...
            state $CODE_OR_SPACE = qr{
                (?<ignorable_space>          # These are not magic...
                    \( \?\?? (?&BRACED) \)   #     Embedded code blocks
                  | \s++                     #     Whitespace not followed by...
                    (?= \|                   #         ...an OR
                      | (?: \) \s* )? \z     #         ...the end of the rule
                      | \(\(?\?\&ws\)        #         ...an explicit ws match
                      | \(\?\??\{            #         ...an embedded code block
                      | \\s                  #         ...an explicit space match
                    )
                )
                |
                (?<magic_space> \s++ )       # All other whitespace is magic

                (?(DEFINE) (?<BRACED> \{ (?: \\. | (?&BRACED) | [^{}] )* \} ) )
            }xms;
            $trans_body =~ s{($CODE_OR_SPACE)}{ $+{ignorable_space} // $local_ws_call }exmsg;
        }
        else {
            while ($trans_body =~ s{$WS_PATTERN}{}oxms) {
                _debug_notify( warn =>
                    qq{Ignoring useless <ws:$1> directive},
                    qq{in definition of <token: $name>},
                    qq{at $source_file line $source_line},
                    qq{(Did you need to define <rule: $name> instead of <token: $name>?)},
                    q{},
                );
            }
        }

        $regex
            .= "\n###############[ $source_file line $source_line ]###############\n"
            .  _translate_rule_def(
                 $type, $qualifier, $name, $callname, $qualified_name, $trans_body, $objectify, $local_ws_defn
               );

        # Update line number...
        $source_line += ($full_decl.$body) =~ tr/\n//;
    }

    # Insert checkpoints into any user-defined code block...
    $regex =~ s{ \( \?\?? \{ \K (?!;) }{
        local \@Regexp::Grammars::RESULT_STACK = \@Regexp::Grammars::RESULT_STACK;
    }xmsg;

    # Check for any suspicious left-overs from the start of the regex...
    pos $regex = 0;

    # If a grammar definition, save grammar and return a placeholder...
    if ($is_grammar) {
        $user_defined_grammar{$grammar_name} = $regex;
        return qq{(?{
            warn "Can't match directly against a pure grammar: <grammar: $grammar_name>\n";
        })(*COMMIT)(?!)};
    }
    # Otherwise, aggregrate the final grammar...
    else {
        return _complete_regex($regex.$inherited_rules, $pre_match_debug, $post_match_debug, $nocontext);
    }
}

sub _complete_regex {
    my ($regex, $pre_match_debug, $post_match_debug, $nocontext) = @_;

    return $nocontext ? qq{(?x)$pre_match_debug$PROLOGUE$regex$EPILOGUE_NC$post_match_debug}
                      : qq{(?x)$pre_match_debug$PROLOGUE$regex$EPILOGUE$post_match_debug};
}

1; # Magic true value required at end of module

__END__

=head1 NAME

Regexp::Grammars - Add grammatical parsing features to Perl 5.10 regexes


=head1 VERSION

This document describes Regexp::Grammars version 1.036


=head1 SYNOPSIS

    use Regexp::Grammars;

    my $parser = qr{
        (?:
            <Verb>               # Parse and save a Verb in a scalar
            <.ws>                # Parse but don't save whitespace
            <Noun>               # Parse and save a Noun in a scalar

            <type=(?{ rand > 0.5 ? 'VN' : 'VerbNoun' })>
                                 # Save result of expression in a scalar
        |
            (?:
                <[Noun]>         # Parse a Noun and save result in a list
                                     (saved under the key 'Noun')
                <[PostNoun=ws]>  # Parse whitespace, save it in a list
                                 #   (saved under the key 'PostNoun')
            )+

            <Verb>               # Parse a Verb and save result in a scalar
                                     (saved under the key 'Verb')

            <type=(?{ 'VN' })>   # Save a literal in a scalar
        |
            <debug: match>       # Turn on the integrated debugger here
            <.Cmd= (?: mv? )>    # Parse but don't capture a subpattern
                                     (name it 'Cmd' for debugging purposes)
            <[File]>+            # Parse 1+ Files and save them in a list
                                     (saved under the key 'File')
            <debug: off>         # Turn off the integrated debugger here
            <Dest=File>          # Parse a File and save it in a scalar
                                     (saved under the key 'Dest')
        )

        ################################################################

        <token: File>              # Define a subrule named File
            <.ws>                  #  - Parse but don't capture whitespace
            <MATCH= ([\w-]+) >     #  - Parse the subpattern and capture
                                   #    matched text as the result of the
                                   #    subrule

        <token: Noun>              # Define a subrule named Noun
            cat | dog | fish       #  - Match an alternative (as usual)

        <rule: Verb>               # Define a whitespace-sensitive subrule
            eats                   #  - Match a literal (after any space)
            <Object=Noun>?         #  - Parse optional subrule Noun and
                                   #    save result under the key 'Object'
        |                          #  Or else...
            <AUX>                  #  - Parse subrule AUX and save result
            <part= (eaten|seen) >  #  - Match a literal, save under 'part'

        <token: AUX>               # Define a whitespace-insensitive subrule
            (has | is)             #  - Match an alternative and capture
            (?{ $MATCH = uc $^N }) #  - Use captured text as subrule result

    }x;

    # Match the grammar against some text...
    if ($text =~ $parser) {
        # If successful, the hash %/ will have the hierarchy of results...
        process_data_in( %/ );
    }



=head1 QUICKSTART CHEATSHEET

=head2 In your program...

    use Regexp::Grammars;    Allow enhanced regexes in lexical scope
    %/                       Result-hash for successful grammar match

=head2 Defining and using named grammars...

    <grammar:  GRAMMARNAME>  Define a named grammar that can be inherited
    <extends:  GRAMMARNAME>  Current grammar inherits named grammar's rules

=head2 Defining rules in your grammar...

    <rule:     RULENAME>     Define rule with magic whitespace
    <token:    RULENAME>     Define rule without magic whitespace

    <objrule:  CLASS= NAME>  Define rule that blesses return-hash into class
    <objtoken: CLASS= NAME>  Define token that blesses return-hash into class

    <objrule:  CLASS>        Shortcut for above (rule name derived from class)
    <objtoken: CLASS>        Shortcut for above (token name derived from class)


=head2 Matching rules in your grammar...

    <RULENAME>               Call named subrule (may be fully qualified)
                             save result to $MATCH{RULENAME}

    <RULENAME(...)>          Call named subrule, passing args to it

    <!RULENAME>              Call subrule and fail if it matches
    <!RULENAME(...)>         (shorthand for (?!<.RULENAME>) )

    <:IDENT>                 Match contents of $ARG{IDENT} as a pattern
    <\:IDENT>                Match contents of $ARG{IDENT} as a literal
    </:IDENT>                Match closing delimiter for $ARG{IDENT}

    <%HASH>                  Match longest possible key of hash
    <%HASH {PAT}>            Match any key of hash that also matches PAT

    </IDENT>                 Match closing delimiter for $MATCH{IDENT}
    <\_IDENT>                Match the literal contents of $MATCH{IDENT}

    <ALIAS= RULENAME>        Call subrule, save result in $MATCH{ALIAS}
    <ALIAS= %HASH>           Match a hash key, save key in $MATCH{ALIAS}
    <ALIAS= ( PATTERN )>     Match pattern, save match in $MATCH{ALIAS}
    <ALIAS= (?{ CODE })>     Execute code, save value in $MATCH{ALIAS}
    <ALIAS= 'STR' >          Save specified string in $MATCH{ALIAS}
    <ALIAS= 42 >             Save specified number in $MATCH{ALIAS}
    <ALIAS= /IDENT>          Match closing delim, save as $MATCH{ALIAS}
    <ALIAS= \_IDENT>         Match '$MATCH{IDENT}', save as $MATCH{ALIAS}

    <.SUBRULE>               Call subrule (one of the above forms),
                             but don't save the result in %MATCH


    <[SUBRULE]>              Call subrule (one of the above forms), but
                             append result instead of overwriting it

    <SUBRULE1>+ % <SUBRULE2> Match one or more repetitions of SUBRULE1
                             as long as they're separated by SUBRULE2
    <SUBRULE1> ** <SUBRULE2> Same (only for backwards compatibility)

    <SUBRULE1>* % <SUBRULE2> Match zero or more repetitions of SUBRULE1
                             as long as they're separated by SUBRULE2


=head2 In your grammar's code blocks...

    $CAPTURE    Alias for $^N (the most recent paren capture)
    $CONTEXT    Another alias for $^N
    $INDEX      Current index of next matching position in string
    %MATCH      Current rule's result-hash
    $MATCH      Magic override value (returned instead of result-hash)
    %ARG        Current rule's argument hash
    $DEBUG      Current match-time debugging mode

=head2 Directives...

    <require: (?{ CODE })   >  Fail if code evaluates false
    <timeout: INT           >  Fail after specified number of seconds
    <debug:   COMMAND       >  Change match-time debugging mode
    <logfile: LOGFILE       >  Change debugging log file (default: STDERR)
    <fatal:   TEXT|(?{CODE})>  Queue error message and fail parse
    <error:   TEXT|(?{CODE})>  Queue error message and backtrack
    <warning: TEXT|(?{CODE})>  Queue warning message and continue
    <log:     TEXT|(?{CODE})>  Explicitly add a message to debugging log
    <ws:      PATTERN       >  Override automatic whitespace matching
    <minimize:>                Simplify the result of a subrule match
    <context:>                 Switch on context substring retention
    <nocontext:>               Switch off context substring retention



=head1 DESCRIPTION

This module adds a small number of new regex constructs that can be used
within Perl 5.10 patterns to implement complete recursive-descent parsing.

Perl 5.10 already supports recursive=descent I<matching>, via the new
C<< (?<name>...) >> and C<< (?&name) >> constructs. For example, here is
a simple matcher for a subset of the LaTeX markup language:

    $matcher = qr{
        (?&File)

        (?(DEFINE)
            (?<File>     (?&Element)* )

            (?<Element>  \s* (?&Command)
                      |  \s* (?&Literal)
            )

            (?<Command>  \\ \s* (?&Literal) \s* (?&Options)? \s* (?&Args)? )

            (?<Options>  \[ \s* (?:(?&Option) (?:\s*,\s* (?&Option) )*)? \s* \])

            (?<Args>     \{ \s* (?&Element)* \s* \}  )

            (?<Option>   \s* [^][\$&%#_{}~^\s,]+     )

            (?<Literal>  \s* [^][\$&%#_{}~^\s]+      )
        )
    }xms

This technique makes it possible to use regexes to recognize complex,
hierarchical--and even recursive--textual structures. The problem is
that Perl 5.10 doesn't provide any support for extracting that
hierarchical data into nested data structures. In other words, using
Perl 5.10 you can I<match> complex data, but not I<parse> it into an
internally useful form.

An additional problem when using Perl 5.10 regexes to match complex data
formats is that you have to make sure you remember to insert
whitespace-matching constructs (such as C<\s*>) at every possible position
where the data might contain ignorable whitespace. This reduces the
readability of such patterns, and increases the chance of errors (typically
caused by overlooking a location where whitespace might appear).

The Regexp::Grammars module solves both those problems.

If you import the module into a particular lexical scope, it
preprocesses any regex in that scope, so as to implement a number of
extensions to the standard Perl 5.10 regex syntax. These extensions
simplify the task of defining and calling subrules within a grammar, and
allow those subrule calls to capture and retain the components of they
match in a proper hierarchical manner.

For example, the above LaTeX matcher could be converted to a full LaTeX parser
(and considerably tidied up at the same time), like so:

    use Regexp::Grammars;
    $parser = qr{
        <File>

        <rule: File>       <[Element]>*

        <rule: Element>    <Command> | <Literal>

        <rule: Command>    \\  <Literal>  <Options>?  <Args>?

        <rule: Options>    \[  <[Option]>+ % (,)  \]

        <rule: Args>       \{  <[Element]>*  \}

        <rule: Option>     [^][\$&%#_{}~^\s,]+

        <rule: Literal>    [^][\$&%#_{}~^\s]+
    }xms

Note that there is no need to explicitly place C<\s*> subpatterns throughout
the rules; that is taken care of automatically.

If the Regexp::Grammars version of this regex were successfully matched
against some appropriate LaTeX document, each rule would call the
subrules specified within it, and then return a hash containing whatever
result each of those subrules returned, with each result indexed by the
subrule's name.

That is, if the rule named C<Command> were invoked, it would first try
to match a backslash, then it would call the three subrules
C<< <Literal> >>, C<< <Options> >>, and C<< <Args> >> (in that sequence). If
they all matched successfully, the C<Command> rule would then return a
hash with three keys: C<'Literal'>, C<'Options'>, and C<'Args'>. The value
for each of those hash entries would be whatever result-hash the
subrules themselves had returned when matched.

In this way, each level of the hierarchical regex can generate hashes
recording everything its own subrules matched, so when the entire pattern
matches, it produces a tree of nested hashes that represent the
structured data the pattern matched.

For example, if the previous regex grammar were matched against a string
containing:

    \documentclass[a4paper,11pt]{article}
    \author{D. Conway}

it would automatically extract a data structure equivalent to the
following (but with several extra "empty" keys, which are described in
L<Subrule results>):

    {
        'file' => {
            'element' => [
                {
                    'command' => {
                        'literal' => 'documentclass',
                        'options' => {
                            'option'  => [ 'a4paper', '11pt' ],
                        },
                        'args'    => {
                            'element' => [ 'article' ],
                        }
                    }
                },
                {
                    'command' => {
                        'literal' => 'author',
                        'args' => {
                            'element' => [
                                {
                                    'literal' => 'D.',
                                },
                                {
                                    'literal' => 'Conway',
                                }
                            ]
                        }
                    }
                }
            ]
        }
    }

The data structure that Regexp::Grammars produces from a regex match
is available to the surrounding program in the magic variable C<%/>.

Regexp::Grammars provides many features that simplify the extraction of
hierarchical data via a regex match, and also some features that can
simplify the processing of that data once it has been extracted. The
following sections explain each of those features, and some of the
parsing techniques they support.


=head2 Setting up the module

Just add:

    use Regexp::Grammars;

to any lexical scope. Any regexes within that scope will automatically now
implement the new parsing constructs:

    use Regexp::Grammars;

    my $parser = qr/ regex with $extra <chocolatey> grammar bits /;

Note that you do not to use the C</x> modifier when declaring a regex
grammar (though you certainly may). But even if you don't, the module
quietly adds a C</x> to every regex within the scope of its usage.
Otherwise, the default I<"a whitespace character matches exactly that
whitespace character"> behaviour of Perl regexes would mess up your
grammar's parsing. If you need the non-C</x> behaviour, you can still
use the C<(?-x)> of C<(?-x:...)> directives to switch of C</x> within
one or more of your grammar's components.

Once the grammar has been processed, you can then match text against the
extended regexes, in the usual manner (i.e. via a C<=~> match):

    if ($input_text =~ $parser) {
        ...
    }

After a successful match, the variable C<%/> will contain a series of
nested hashes representing the structured hierarchical data captured
during the parse.

=head2 Structure of a Regexp::Grammars grammar

A Regexp::Grammars specification consists of a I<start-pattern> (which
may include both standard Perl 5.10 regex syntax, as well as special
Regexp::Grammars directives), followed by one or more rule or token
definitions.

For example:

    use Regexp::Grammars;
    my $balanced_brackets = qr{

        # Start-pattern...
        <paren_pair> | <brace_pair>

        # Rule definition...
        <rule: paren_pair>
            \(  (?: <escape> | <paren_pair> | <brace_pair> | [^()] )*  \)

        # Rule definition...
        <rule: brace_pair>
            \{  (?: <escape> | <paren_pair> | <brace_pair> | [^{}] )*  \}

        # Token definition...
        <token: escape>
            \\ .
    }xms;

The start-pattern at the beginning of the grammar acts like the
"top" token of the grammar, and must be matched completely for the
grammar to match.

This pattern is treated like a token for whitespace
matching behaviour (see L<"Tokens vs rules (whitespace handling)">).
That is, whitespace in the start-pattern is treated like whitespace
in any normal Perl regex.

The rules and tokens are declarations only and they are not directly matched.
Instead, they act like subroutines, and are invoked by name from the
initial pattern (or from within a rule or token).

Each rule or token extends from the directive that introduces it up to either
the next rule or token directive, or (in the case of the final rule or token)
to the end of the grammar.


=head2 Tokens vs rules (whitespace handling)

The difference between a token and a rule is that a token treats any
whitespace within it exactly as a normal Perl regular expression would.
That is, a sequence of whitespace in a token is ignored if the C</x>
modifier is in effect, or else matches the same literal sequence of
whitespace characters (if C</x> is not in effect).

In a rule, most sequences of whitespace are treated as matching the
implicit subrule C<< <.ws> >>, which is automatically predefined to
match optional whitespace (i.e. C<\s*>).

Exceptions to this behaviour are whitespaces before a C<|> or a code
block or an explicit space-matcher (such as C<< <ws> >> or C<\s>), 
or at the very end of the rule)

You can explicitly define a C<< <ws> >> token to change that default
behaviour. For example, you could alter the definition of "whitespace" to
include Perlish comments, by adding an explicit C<< <token: ws> >>:

    <token: ws>
        (?: \s+ | #[^\n]* )*

But be careful not to define C<< <ws> >> as a rule, as this will lead to
all kinds of infinitely recursive unpleasantness.


=head3 Per-rule whitespace handling

Redefining the C<< <ws> >> token changes its behaviour throughout the
entire grammar, within every rule definition. Usually that's appropriate,
but sometimes you need finer-grained control over whitespace handling.

So Regexp::Grammars provides the C<< <ws:> >> directive, which allows
you to override the implicit whitespace-matches-whitespace behaviour
only within the current rule.

Note that this directive does I<not> redefined C<< <ws> >> within the
rule; it simply specifies what to replace each whitespace sequence with
(instead of replacign each with a C<< <ws> >> call).

For example, if a language allows one kind of comment between statements
and another within statements, you could parse it with:

    <rule: program>
        # One type of comment between...
        <ws: (\s++ | \# .*? \n)* >

        # ...colon-separated statements...
        <[statement]>+ % ( ; )


    <rule: statement>
        # Another type of comment...
        <ws: (\s*+ | \#{ .*? }\# )* >

        # ...between comma-separated commands...
        <cmd>  <[arg]>+ % ( , )


Note that each directive only applies to the rule in which it is
specified. In every other rule in the grammar, whitespace would still
match the usual C<< <ws> >> subrule.



=head2 Calling subrules

To invoke a rule to match at any point, just enclose the rule's name in angle
brackets (like in Perl 6). There must be no space between the opening bracket
and the rulename. For example::

    qr{
        file:             # Match literal sequence 'f' 'i' 'l' 'e' ':'
        <name>            # Call <rule: name>
        <options>?        # Call <rule: options> (it's okay if it fails)

        <rule: name>
            # etc.
    }x;

If you need to match a literal pattern that would otherwise look like a
subrule call, just backslash-escape the leading angle:

    qr{
        file:             # Match literal sequence 'f' 'i' 'l' 'e' ':'
        \<name>           # Match literal sequence '<' 'n' 'a' 'm' 'e' '>'
        <options>?        # Call <rule: options> (it's okay if it fails)

        <rule: name>
            # etc.
    }x;


=head2 Subrule results

If a subrule call successfully matches, the result of that match is a
reference to a hash. That hash reference is stored in the current rule's
own result-hash, under the name of the subrule that was invoked. The
hash will, in turn, contain the results of any more deeply nested
subrule calls, each stored under the name by which the nested
subrule was invoked.

In other words, if the rule C<sentence> is defined:

    <rule: sentence>
        <noun> <verb> <object>

then successfully calling the rule:

    <sentence>

causes a new hash entry at the current nesting level. That entry's key will be
C<'sentence'> and its value will be a reference to a hash, which in turn will
have keys: C<'noun'>, C<'verb'>, and C<'object'>.

In addition each result-hash has one extra key: the empty string. The
value for this key is whatever substring the entire subrule call matched.
This value is known as the I<context substring>.

So, for example, a successful call to C<< <sentence> >> might add
something like the following to the current result-hash:

    sentence => {
        ""     => 'I saw a dog',
        noun   => 'I',
        verb   => 'saw',
        object => {
            ""      => 'a dog',
            article => 'a',
            noun    => 'dog',
        },
    }

Note, however, that if the result-hash at any level contains I<only>
the empty-string key (i.e. the subrule did not call any sub-subrules or
save any of their nested result-hashes), then the hash is "unpacked"
and just the context substring itself is returned.

For example, if C<< <rule: sentence> >> had been defined:

    <rule: sentence>
        I see dead people

then a successful call to the rule would only add:

    sentence => 'I see dead people'

to the current result-hash.

This is a useful feature because it prevents a series of nested subrule
calls from producing very unwieldy data structures. For example, without
this automatic unpacking, even the simple earlier example:

    <rule: sentence>
        <noun> <verb> <object>

would produce something needlessly complex, such as:

    sentence => {
        ""     => 'I saw a dog',
        noun   => {
            "" => 'I',
        },
        verb   => {
            "" => 'saw',
        },
        object => {
            ""      => 'a dog',
            article => {
                "" => 'a',
            },
            noun    => {
                "" => 'dog',
            },
        },
    }


=head3 Turning off the context substring

The context substring is convenient for debugging and for generating
error messages but, in a large grammar, or when parsing a long string,
the capture and storage of many nested substrings may quickly become
prohibitively expensive.

So Regexp::Grammars provides a directive to prevent context substrings
from being retained. Any rule or token that includes the directive
C<< <nocontext:> >> anywhere in the rule's body will not retain any
context substring it matches...unless that substring would be the only
entry in its result hash (which only happens within objrules and
objtokens).

If a C<< <nocontext:> >> directive appears I<before> the first rule or
token definition (i.e. as part of the main pattern), then the entire grammar
will discard all context substrings from every one of its rules
and tokens.

However, you can override this universal prohibition with a second
directive: C<< <context:> >>. If this directive appears in any rule or
token, that rule or token I<will> save its context substring, even if a
global C<< <nocontext:> >> is in effect.

This means that this grammar:

    qr{
        <Command>

        <rule: Command>
            <nocontext:>
            <Keyword> <arg=(\S+)>+ % <.ws>

        <token: Keyword>
            <Move> | <Copy> | <Delete>

        # etc.
    }x

and this grammar:

    qr{
        <nocontext:>
        <Command>

        <rule: Command>
            <Keyword> <arg=(\S+)>+ % <.ws>

        <token: Keyword>
            <context:>
            <Move> | <Copy> | <Delete>

        # etc.
    }x

will behave identically (saving context substrings for keywords, but not
for commands), except that the first version will also retain the global
context substring (i.e. $/{""}), whereas the second version will not.

Note that C<< <context:> >> and C<< <nocontext:> >> have no effect on,
or even any interaction with, the various
L<result distillation|"Result distillation"> mechanisms,
which continue to work in the usual way when either or both of the
directives is used.


=head2 Renaming subrule results

It is not always convenient to have subrule results stored under the
same name as the rule itself. Rule names should be optimized for
understanding the behaviour of the parser, whereas result names should
be optimized for understanding the structure of the data. Often those
two goals are identical, but not always; sometimes rule names need to
describe what the data looks like, while result names need to describe
what the data means.

For example, sometimes you need to call the same rule twice, to match
two syntactically identical components whose positions give then semantically
distinct meanings:

    <rule: copy_cmd>
        copy <file> <file>

The problem here is that, if the second call to C<< <file> >> succeeds, its
result-hash will be stored under the key C<'file'>, clobbering the data that
was returned from the first call to C<< <file> >>.

To avoid such problems, Regexp::Grammars allows you to I<alias> any subrule
call, so that it is still invoked by the original name, but its result-hash is
stored under a different key. The syntax for that is:
C<<< <I<alias>=I<rulename>> >>>. For example:

    <rule: copy_cmd>
        copy <from=file> <to=file>

Here, C<< <rule: file> >> is called twice, with the first result-hash being
stored under the key C<'from'>, and the second result-hash being stored under
the key C<'to'>.

Note, however, that the alias before the C<=> must be a proper
identifier (i.e. a letter or underscore, followed by letters, digits,
and/or underscores). Aliases that start with an underscore and aliases named
C<MATCH> have special meaning (see L<Private subrule calls> and
L<Result distillation> respectively).

Aliases can also be useful for normalizing data that may appear in different
formats and sequences. For example:

    <rule: copy_cmd>
        copy <from=file>        <to=file>
      | dup    <to=file>  as  <from=file>
      |      <from=file>  ->    <to=file>
      |        <to=file>  <-  <from=file>

Here, regardless of which order the old and new files are specified, the
result-hash always gets:

    copy_cmd => {
        from => 'oldfile',
          to => 'newfile',
    }


=head2 List-like subrule calls

If a subrule call is quantified with a repetition specifier:

    <rule: file_sequence>
        <file>+

then each repeated match overwrites the corresponding entry in the
surrounding rule's result-hash, so only the result of the final
repetition will be retained. That is, if the above example matched
the string C<S<"foo.pl bar.py baz.php">>, then the result-hash would contain:

    file_sequence {
        ""   => 'foo.pl bar.py baz.php',
        file => 'baz.php',
    }

Usually, that's not the desired outcome, so Regexp::Grammars provides
another mechanism by which to call a subrule; one that saves I<all>
repetitions of its results.

A regular subrule call consists of the rule's name surrounded by angle
brackets. If, instead, you surround the rule's name with C<< <[...]> >>
(angle I<and> square brackets) like so:

    <rule: file_sequence>
        <[file]>+

then the rule is invoked in exactly the same way, but the result of that
submatch is pushed onto an array nested inside the appropriate result-hash
entry. In other words, if the above example matched the same
C<S<"foo.pl bar.py baz.php">> string, the result-hash would contain:

    file_sequence {
        ""   => 'foo.pl bar.py baz.php',
        file => [ 'foo.pl', 'bar.py', 'baz.php' ],
    }

This "listifying subrule call" can also be useful for non-repeated subrule
calls, if the same subrule is invoked in several places in a grammar. For
example if a cmdline option could be given either one or two values, you
might parse it:

    <rule: size_option>
        -size <[size]> (?: x <[size]> )?

The result-hash entry for C<'size'> would then always contain an array,
with either one or two elements, depending on the input being parsed.

Listifying subrules can also be given L<aliases|"Renaming subrule results">,
just like ordinary subrules. The alias is always specified inside the square
brackets:

    <rule: size_option>
        -size <[size=pos_integer]> (?: x <[size=pos_integer]> )?

Here, the sizes are parsed using the C<pos_integer> rule, but saved in the
result-hash in an array under the key C<'size'>.


=head2 Parametric subrules

When a subrule is invoked, it can be passed a set of named arguments
(specified as I<key>C<< => >>I<values> pairs). This argument list is
placed in a normal Perl regex code block and must appear immediately
after the subrule name, before the closing angle bracket.

Within the subrule that has been invoked, the arguments can be accessed
via the special hash C<%ARG>. For example:

    <rule: block>
        <tag>
            <[block]>*
        <end_tag(?{ tag=>$MATCH{tag} })>  # ...call subrule with argument

    <token: end_tag>
        end_ (??{ quotemeta $ARG{tag} })

Here the C<block> rule first matches a C<< <tag> >>, and the corresponding
substring is saved in C<$MATCH{tag}>. It then matches any number of nested
blocks. Finally it invokes the C<< <end_tag> >> subrule, passing it an
argument whose name is C<'tag'> and whose value is the current value of
C<$MATCH{tag}> (i.e. the original opening tag).

When it is thus invoked, the C<end_tag> token first matches C<'end_'>,
then interpolates the literal value of the C<'tag'> argument and
attempts to match it.

Any number of named arguments can be passed when a subrule is invoked.
For example, we could generalize the C<end_tag> rule to allow any prefix
(not just C<'end_'>), and also to allow for 'if...fi'-style reversed
tags, like so:

    <rule: block>
        <tag>
            <[block]>*
        <end_tag (?{ prefix=>'end', tag=>$MATCH{tag} })>

    <token: end_tag>
        (??{ $ARG{prefix} // q{(?!)} })      # ...prefix as pattern
        (??{ quotemeta $ARG{tag} })          # ...tag as literal
      |
        (??{ quotemeta reverse $ARG{tag} })  # ...reversed tag


Note that, if you do not need to interpolate values (such as
C<$MATCH{tag}>) into a subrule's argument list, you can
use simple parentheses instead of C<(?{...})>, like so:

        <end_tag( prefix=>'end', tag=>'head' )>

The only types of values you can use in this simplified
syntax are numbers and single-quote-delimited strings.
For anything more complex, put the argument list
in a full C<(?{...})>.

As the earlier examples show, the single most common
type of argument is one of the form:
I<IDENTIFIER> C<< => $MATCH{ >>I<IDENTIFIER>C<}>. That is,
it's a common requirement to pass an element of C<%MATCH>
into a subrule, named with its own key.

Because this is such a common usage, Regexp::Grammars
provides a shortcut. If you use simple parentheses (instead
of C<(?{...})> parentheses) then instead of a pair, you can
specify an argument using a colon followed by an identifier.
This argument is replaced by a named argument whose name
is the identifier and whose value is the corresponding item
from C<%MATCH>. So, for example, instead of:

        <end_tag(?{ prefix=>'end', tag=>$MATCH{tag} })>

you can just write:

        <end_tag( prefix=>'end', :tag )>

Note that, from Perl 5.20 onwards, due to changes in the way that
Perl parses regexes, Regexp::Grammars does not support explicitly passing
elements of C<%MATCH> as argument values within a list subrule
(yeah, it's a very specific and obscure edge-case):

        <[end_tag(?{ prefix=>'end', tag=>$MATCH{tag} })]>   # Does not work

Note, however, that the shortcut:

        <[end_tag( prefix=>'end', :tag )]>

still works correctly.


=head3 Accessing subrule arguments more cleanly

As the preceding examples illustrate, using subrule arguments
effectively generally requires the use of run-time interpolated
subpatterns via the C<(??{...})> construct.

This produces ugly rule bodies such as:

    <token: end_tag>
        (??{ $ARG{prefix} // q{(?!)} })      # ...prefix as pattern
        (??{ quotemeta $ARG{tag} })          # ...tag as literal
      |
        (??{ quotemeta reverse $ARG{tag} })  # ...reversed tag

To simplify these common usages, Regexp::Grammars provides
three convenience constructs.

A subrule call of the form C<< <: >>I<identifier>C<< > >>
is equivalent to:

    (??{ $ARG{'identifier'} // q{(?!)} })

Namely: I<"Match the contents of C<$ARG{'identifier'}>,
treating those contents as a pattern.">

A subrule call of the form C<< <\: >>I<identifier>C<< > >>
(that is: a L<matchref|"Rematching subrule results">
with a colon after the backslash) is equivalent to:

    (??{ defined $ARG{'identifier'}
            ? quotemeta($ARG{'identifier'})
            : '(?!)'
    })

Namely: I<"Match the contents of C<$ARG{'identifier'}>,
treating those contents as a literal.">

A subrule call of the form C<< </: >>I<identifier>C<< > >>
(that is: an L<invertref|"Rematching balanced delimiters">
with a colon after the forward slash) is equivalent to:

    (??{ defined $ARG{'identifier'}
            ? quotemeta(reverse $ARG{'identifier'})
            : '(?!)'
    })

Namely: I<"Match the closing delimiter corresponding to
the contents of C<$ARG{'identifier'}>, as if it were a literal">.

The availability of these three constructs mean that we could rewrite
the above C<< <end_tag> >> token much more cleanly as:

    <token: end_tag>
        <:prefix>      # ...prefix as pattern
        <\:tag>        # ...tag as a literal
      |
        </:tag>        # ...reversed tag

In general these constructs mean that, within a subrule,
if you want to match an argument passed to that subrule,
you use C<< <: >>I<ARGNAME>C<< > >> (to match the argument
as a pattern) or C<< <\: >>I<ARGNAME>C<< > >> (to match
the argument as a literal).

Note the consistent mnemonic in these various subrule-like
interpolations of named arguments: the name is always prefixed by a
colon.

In other words, the C<< <:ARGNAME> >> form works just like
a C<< <RULENAME> >>, except that the leading colon tells
Regexp::Grammars to use the contents of C<$ARG{'ARGNAME'}>
as the subpattern, instead of the contents of C<(?&RULENAME)>

Likewise, the C<< <\:ARGNAME> >> and C<< </:ARGNAME> >> constructs work
exactly like C<< <\_MATCHNAME> >> and C<< </INVERTNAME> >> respectively,
except that the leading colon indicates that the matchref or invertref
should be taken from C<%ARG> instead of from C<%MATCH>.


=head2 Pseudo-subrules

Aliases can also be given to standard Perl subpatterns, as well as to
code blocks within a regex. The syntax for subpatterns is:

    <ALIAS= (SUBPATTERN) >

In other words, the syntax is exactly like an aliased subrule call, except
that the rule name is replaced with a set of parentheses containing the
subpattern. Any parentheses--capturing or non-capturing--will do.

The effect of aliasing a standard subpattern is to cause whatever that
subpattern matches to be saved in the result-hash, using the alias as
its key. For example:

    <rule: file_command>

        <cmd=(mv|cp|ln)>  <from=file>  <to=file>

Here, the C<< <cmd=(mv|cp|ln)> >> is treated exactly like a regular
C<(mv|cp|ln)>, but whatever substring it matches is saved in the result-hash
under the key C<'cmd'>.

The syntax for aliasing code blocks is:

    <ALIAS= (?{ your($code->here) }) >

Note, however, that the code block must be specified in the standard Perl 5.10
regex notation: C<(?{...})>. A common mistake is to write:

    <ALIAS= { your($code->here } >

instead, which will attempt to interpolate C<$code> before
the regex is even compiled, as such variables are only "protected" from
interpolation inside a C<< (?{...}) >>.

When correctly specified, this construct executes the code in the block
and saves the result of that execution in the result-hash, using the
alias as its key. Aliased code blocks are useful for adding semantic
information based on which branch of a rule is executed. For example,
consider the C<copy_cmd> alternatives shown earlier:

    <rule: copy_cmd>
        copy <from=file>        <to=file>
      | dup    <to=file>  as  <from=file>
      |      <from=file>  ->    <to=file>
      |        <to=file>  <-  <from=file>

Using aliased code blocks, you could add an extra field to the result-
hash to describe which form of the command was detected, like so:

    <rule: copy_cmd>
        copy <from=file>        <to=file>  <type=(?{ 'std' })>
      | dup    <to=file>  as  <from=file>  <type=(?{ 'rev' })>
      |      <from=file>  ->    <to=file>  <type=(?{  +1   })>
      |        <to=file>  <-  <from=file>  <type=(?{  -1   })>

Now, if the rule matched, the result-hash would contain something like:

    copy_cmd => {
        from => 'oldfile',
          to => 'newfile',
        type => 'fwd',
    }

Note that, in addition to the semantics described above, aliased
subpatterns and code blocks also become visible to Regexp::Grammars'
integrated debugger (see L<Debugging>).


=head2 Aliased literals

As the previous example illustrates, it is inconveniently verbose to
assign constants via aliased code blocks. So Regexp::Grammars provides a
short-cut. It is possible to directly alias a numeric literal or a
single-quote delimited literal string, without putting either inside a code
block. For example, the previous example could also be written:

    <rule: copy_cmd>
        copy <from=file>        <to=file>  <type='std'>
      | dup    <to=file>  as  <from=file>  <type='rev'>
      |      <from=file>  ->    <to=file>  <type= +1  >
      |        <to=file>  <-  <from=file>  <type= -1  >

Note that only these two forms of literal are supported in this
abbreviated syntax.


=head2 Amnesiac subrule calls

By default, every subrule call saves its result into the result-hash, either
under its own name, or under an alias.

However, sometimes you may want to refactor some literal part of a rule
into one or more subrules, without having those submatches added to the
result-hash. The syntax for calling a subrule, but ignoring its return value
is:

    <.SUBRULE>

(which is stolen directly from Perl 6).

For example, you may prefer to rewrite a rule such as:

    <rule: paren_pair>

        \(
            (?: <escape> | <paren_pair> | <brace_pair> | [^()] )*
        \)

without any literal matching, like so:

    <rule: paren_pair>

        <.left_paren>
            (?: <escape> | <paren_pair> | <brace_pair> | <.non_paren> )*
        <.right_paren>

    <token: left_paren>   \(
    <token: right_paren>  \)
    <token: non_paren>    [^()]

Moreover, as the individual components inside the parentheses probably
aren't being captured for any useful purpose either, you could further
optimize that to:

    <rule: paren_pair>

        <.left_paren>
            (?: <.escape> | <.paren_pair> | <.brace_pair> | <.non_paren> )*
        <.right_paren>


Note that you can also use the dot modifier on an aliased subpattern:

    <.Alias= (SUBPATTERN) >

This seemingly contradictory behaviour (of giving a subpattern a name,
then deliberately ignoring that name) actually does make sense in one
situation. Providing the alias makes the subpattern visible to the
debugger, while using the dot stops it from affecting the result-hash.
See L<"Debugging non-grammars"> for an example of this usage.


=head2 Private subrule calls

If a rule name (or an alias) begins with an underscore:

     <_RULENAME>       <_ALIAS=RULENAME>
    <[_RULENAME]>     <[_ALIAS=RULENAME]>

then matching proceeds as normal, and any result that is returned is
stored in the current result-hash in the usual way.

However, when any rule finishes (and just before it returns) it first
filters its result-hash, removing any entries whose keys begin with an
underscore. This means that any subrule with an underscored name (or
with an underscored alias) remembers its result, but only until the end
of the current rule. Its results are effectively private to the current
rule.

This is especially useful in conjunction with
L<result distillation|"Result distillation">.


=head2 Lookahead (zero-width) subrules

Non-capturing subrule calls can be used in normal lookaheads:

    <rule: qualified_typename>
        # A valid typename and has a :: in it...
        (?= <.typename> )  [^\s:]+ :: \S+

    <rule: identifier>
        # An alpha followed by alnums (but not a valid typename)...
        (?! <.typename> )    [^\W\d]\w*

but the syntax is a little unwieldy. More importantly, an internal
problem with backtracking causes positive lookaheads to mess up
the module's named capturing mechanism.

So Regexp::Grammars provides two shorthands:

    <!typename>        same as: (?! <.typename> )
    <?typename>        same as: (?= <.typename> ) ...but works correctly!

These two constructs can also be called with arguments, if necessary:

    <rule: Command>
        <Keyword>
        (?:
            <!Terminator(:Keyword)>  <Args=(\S+)>
        )?
        <Terminator(:Keyword)>

Note that, as the above equivalences imply, neither of these forms of a
subroutine call ever captures what it matches.


=head2 Matching separated lists

One of the commonest tasks in text parsing is to match a list of unspecified
length, in which items are separated by a fixed token. Things like:

    1, 2, 3 , 4 ,13, 91        # Numbers separated by commas and spaces

    g-c-a-g-t-t-a-c-a          # DNA bases separated by dashes

    /usr/local/bin             # Names separated by directory markers

    /usr:/usr/local:bin        # Directories separated by colons

The usual construct required to parse these kinds of structures is either:

    <rule: list>

        <item> <separator> <list>     # recursive definition
      | <item>                        # base case

or, if you want to allow zero-or-more items instead of requiring one-or-more:

    <rule: list_opt>
        <list>?                       # entire list may be missing

    <rule: list>                      # as before...
        <item> <separator> <list>     #   recursive definition
      | <item>                        #   base case


Or, more efficiently, but less prettily:

    <rule: list>
        <[item]> (?: <separator> <[item]> )*           # one-or-more

    <rule: list_opt>
        (?: <[item]> (?: <separator> <[item]> )* )?    # zero-or-more

Because separated lists are such a common component of grammars,
Regexp::Grammars provides cleaner ways to specify them:

    <rule: list>
        <[item]>+ % <separator>      # one-or-more

    <rule: list_zom>
        <[item]>* % <separator>      # zero-or-more

Note that these are just regular repetition qualifiers (i.e. C<+>
and C<*>) applied to a subriule (C<< <[item]> >>), with a C<%>
modifier after them to specify the required separator between the
repeated matches.

The number of repetitions matched is controlled both by the nature of
the qualifier (C<+> vs C<*>) and by the subrule specified after the C<%>.
The qualified subrule will be repeatedly matched
for as long as its qualifier allows, provided that the second subrule
also matches I<between> those repetitions.

For example, you can match a parenthesized sequence of one-or-more
numbers separated by commas, such as:

    (1, 2, 3, 4, 13, 91)        # Numbers separated by commas (and spaces)

with:

    <rule: number_list>

        \(  <[number]>+ % <comma>  \)

    <token: number>  \d+
    <token: comma>   ,

Note that any spaces round the commas will be ignored because
C<< <number_list> >> is specified as a rule and the C<+%> specifier
has spaces within and around it. To disallow spaces around the commas,
make sure there are no spaces in or around the C<+%>:

    <rule: number_list_no_spaces>

        \( <[number]>+%<comma> \)

(or else specify the rule as a token instead).

Because the C<%> is a modifier applied to a qualifier, you can modify
I<any> other repetition qualifier in the same way. For example:

    <[item]>{2,4} % <sep>   # two-to-four items, separated

    <[item]>{7}   % <sep>   # exactly 7 items, separated

    <[item]>{10,}? % <sep>   # minimum of 10 or more items, separated

You can even do this:

    <[item]>? % <sep>       # one-or-zero items, (theoretically) separated

though the separator specification is, of course, meaningless in that case
as it will never be needed to separate a maximum of one item.

If a C<%> appears anywhere else in a grammar (i.e. I<not> immediately after a
repetition qualifier), it is treated normally (i.e. as a self-matching literal
character):

    <token: perl_hash>
        % <ident>                # match "%foo", "%bar", etc.

    <token: perl_mod>
        <expr> % <expr>          # match "$n % 2", "($n+3) % ($n-1)", etc.

If you need to match a literal C<%> immediately after a repetition, either
quote it:

    <token: percentage>
        \d{1,3} \% solution                  # match "7% solution", etc.

or refactor the C<%> character:

    <token: percentage>
        \d{1,3} <percent_sign> solution      # match "7% solution", etc.

    <token: percent_sign>
        %

Note that it's usually necessary to use the C<< <[...]> >> form for the
repeated items being matched, so that all of them are saved in the
result hash. You can also save all the separators (if they're important)
by specifying them as a list-like subrule too:

    \(  <[number]>* % <[comma]>  \)  # save numbers *and* separators

The repeated item I<must> be specified as a subrule call of some kind
(i.e. in angles), but the separators may be specified either as a
subrule or as a raw bracketed pattern. For example:

    <[number]>* % ( , | : )    # Numbers separated by commas or colons

    <[number]>* % [,:]         # Same, but more efficiently matched

The separator should always be specified within matched delimiters of
some kind: either matching C<< <...> >> or matching C<(...)> or matching
C<[...]>. Simple, non-bracketed separators will sometimes also work:

    <[number]>+ % ,

but not always:

    <[number]>+ % ,\s+     # Oops! Separator is just: ,

This is because of the limited way in which the module internally parses
ordinary regex components (i.e. without full understanding of their
implicit precedence). As a consequence, consistently placing brackets
around any separator is a much safer approach:

    <[number]>+ % (,\s+)


You can also use a simple pattern on the left of the C<%> as the item
matcher, but in this case it I<must always> be aliased into a
list-collecting subrule, like so:

    <[item=(\d+)]>* % [,]


Note that, for backwards compatibility with earlier versions of
Regexp::Grammars, the C<+%> operator can also be written: C<**>.
However, there can be no space between the two asterisks of this
variant. That is:

    <[item]> ** <sep>      # same as <[item]>* % <sep>

    <[item]>* * <sep>      # error (two * qualifiers in a row)


=head2 Matching hash keys

In some situations a grammar may need a rule that matches dozens,
hundreds, or even thousands of one-word alternatives. For example, when
matching command names, or valid userids, or English words. In such
cases it is often impractical (and always inefficient) to list all the
alternatives between C<|> alterators:

    <rule: shell_cmd>
        a2p | ac | apply | ar | automake | awk | ...
        # ...and 400 lines later
        ... | zdiff | zgrep | zip | zmore | zsh

    <rule: valid_word>
        a | aa | aal | aalii | aam | aardvark | aardwolf | aba | ...
        # ...and 40,000 lines later...
        ... | zymotize | zymotoxic | zymurgy | zythem | zythum

To simplify such cases, Regexp::Grammars provides a special construct
that allows you to specify all the alternatives as the keys of a normal
hash. The syntax for that construct is simply to put the hash name
inside angle brackets (with no space between the angles and the hash name).

Which means that the rules in the previous example could also be written:

    <rule: shell_cmd>
        <%cmds>

    <rule: valid_word>
        <%dict>

provided that the two hashes (C<%cmds> and C<%dict>) are visible in the scope
where the grammar is created.

Matching a hash key in this way is typically I<significantly> faster
than matching a large set of alternations. Specifically, it is
I<O(length of longest potential key) ^ 2>, instead of I<O(number of keys)>.

Internally, the construct is converted to something equivalent to:

    <rule: shell_cmd>
        (<.hk>)  <require: (?{ exists $cmds{$CAPTURE} })>

    <rule: valid_word>
        (<.hk>)  <require: (?{ exists $dict{$CAPTURE} })>

The special C<< <hk> >> rule is created automatically, and defaults to
C<\S+>, but you can also define it explicitly to handle other kinds of
keys. For example:

    <rule: hk>
        [^\n]+        # Key may be any number of chars on a single line

    <rule: hk>
        [ACGT]{10,}   # Key is a base sequence of at least 10 pairs

Alternatively, you can specify a different key-matching pattern for
each hash you're matching, by placing the required pattern in braces
immediately after the hash name. For example:

    <rule: client_name>
        # Valid keys match <.hk> (default or explicitly specified)
        <%clients>

    <rule: shell_cmd>
        # Valid keys contain only word chars, hyphen, slash, or dot...
        <%cmds { [\w-/.]+ }>

    <rule: valid_word>
        # Valid keyss contain only alphas or internal hyphen or apostrophe...
        <%dict{ (?i: (?:[a-z]+[-'])* [a-z]+ ) }>

    <rule: DNA_sequence>
        # Valid keys are base sequences of at least 10 pairs...
        <%sequences{[ACGT]{10,}}>

This second approach to key-matching is preferred, because it localizes
any non-standard key-matching behaviour to each individual hash.


=head2 Rematching subrule results

Sometimes it is useful to be able to rematch a string that has previously
been matched by some earlier subrule. For example, consider a rule to
match shell-like control blocks:

    <rule: control_block>
          for   <expr> <[command]>+ endfor
        | while <expr> <[command]>+ endwhile
        | if    <expr> <[command]>+ endif
        | with  <expr> <[command]>+ endwith

This would be much tidier if we could factor out the command names
(which are the only differences between the four alternatives). The
problem is that the obvious solution:

    <rule: control_block>
        <keyword> <expr>
            <[command]>+
        end<keyword>

doesn't work, because it would also match an incorrect input like:

    for 1..10
        echo $n
        ls subdir/$n
    endif

We need some way to ensure that the C<< <keyword> >> matched immediately
after "end" is the same C<< <keyword> >> that was initially matched.

That's not difficult, because the first C<< <keyword> >> will have
captured what it matched into C<$MATCH{keyword}>, so we could just
write:

    <rule: control_block>
        <keyword> <expr>
            <[command]>+
        end(??{quotemeta $MATCH{keyword}})

This is such a useful technique, yet so ugly, scary, and prone to error,
that Regexp::Grammars provides a cleaner equivalent:

    <rule: control_block>
        <keyword> <expr>
            <[command]>+
        end<\_keyword>

A directive of the form C<<< <\_I<IDENTIFIER>> >>> is known as a
"matchref" (an abbreviation of "%MATCH-supplied backreference").
Matchrefs always attempt to match, as a literal, the current value of
C<<< $MATCH{I<IDENTIFIER>} >>>.

By default, a matchref does not capture what it matches, but you
can have it do so by giving it an alias:

    <token: delimited_string>
        <ldelim=str_delim>  .*?  <rdelim=\_ldelim>

    <token: str_delim> ["'`]

At first glance this doesn't seem very useful as, by definition,
C<$MATCH{ldelim}> and C<$MATCH{rdelim}> must necessarily
always end up with identical values. However, it can be useful
if the rule also has other alternatives and you want to create a
consistent internal representation for those alternatives, like so:

    <token: delimited_string>
          <ldelim=str_delim>  .*?  <rdelim=\_ldelim>
        | <ldelim=( \[ )      .*?  <rdelim=( \] )
        | <ldelim=( \{ )      .*?  <rdelim=( \} )
        | <ldelim=( \( )      .*?  <rdelim=( \) )
        | <ldelim=( \< )      .*?  <rdelim=( \> )

You can also force a matchref to save repeated matches
as a nested array, in the usual way:

    <token: marked_text>
        <marker> <text> <[endmarkers=\_marker]>+

Be careful though, as the following will not do as you may expect:

        <[marker]>+ <text> <[endmarkers=\_marker]>+

because the value of C<$MATCH{marker}> will be an array reference, which
the matchref will flatten and concatenate, then match the
resulting string as a literal, which will mean the previous example will
match endmarkers that are exact multiples of the complete start marker,
rather than endmarkers that consist of any number of repetitions of the
individual start marker delimiter. So:

        ""text here""
        ""text here""""
        ""text here""""""

but not:

        ""text here"""
        ""text here"""""

Uneven start and end markers such as these are extremely unusual, so
this problem rarely arises in practice.


I<B<Note:> Prior to Regexp::Grammars version 1.020, the syntax for matchrefs
was C<<< <\I<IDENTIFIER>> >>> instead of C<<< <\_I<IDENTIFIER>> >>>. This
created problems when the identifier started with any of C<l>, C<u>, C<L>,
C<U>, C<Q>, or C<E>, so the syntax has had to be altered in a backwards
incompatible way. It will not be altered again.
>

=head2 Rematching balanced delimiters

Consider the example in the previous section:

    <token: delimited_string>
          <ldelim=str_delim>  .*?  <rdelim=\_ldelim>
        | <ldelim=( \[ )      .*?  <rdelim=( \] )
        | <ldelim=( \{ )      .*?  <rdelim=( \} )
        | <ldelim=( \( )      .*?  <rdelim=( \) )
        | <ldelim=( \< )      .*?  <rdelim=( \> )

The repeated pattern of the last four alternatives is gauling,
but we can't just refactor those delimiters as well:

    <token: delimited_string>
          <ldelim=str_delim>  .*?  <rdelim=\_ldelim>
        | <ldelim=bracket>    .*?  <rdelim=\_ldelim>

because that would incorrectly match:

    { delimited content here {

while failing to match:

    { delimited content here }

To refactor balanced delimiters like those, we need a second
kind of matchref; one that's a little smarter.

Or, preferably, a lot smarter...because there are many other kinds of
balanced delimiters, apart from single brackets. For example:

      {{{ delimited content here }}}
       /* delimited content here */
       (* delimited content here *)
       `` delimited content here ''
       if delimited content here fi

The common characteristic of these delimiter pairs is that the closing
delimiter is the I<inverse> of the opening delimiter: the sequence of
characters is reversed and certain characters (mainly brackets, but also
single-quotes/backticks) are mirror-reflected.

Regexp::Grammars supports the parsing of such delimiters with a
construct known as an I<invertref>, which is specified using the
C<<< </I<IDENT>> >>> directive. An invertref acts very like a
L<matchref|"Rematching subrule results">, except that it does not
convert to:

    (??{ quotemeta( $MATCH{I<IDENT>} ) })

but rather to:

    (??{ quotemeta( inverse( $MATCH{I<IDENT> ))} })

With this directive available, the balanced delimiters of the previous
example can be refactored to:

    <token: delimited_string>
          <ldelim=str_delim>  .*?  <rdelim=\_ldelim>
        | <ldelim=( [[{(<] )  .*?  <rdelim=/ldelim>

Like matchrefs, invertrefs come in the usual range of flavours:

    </ident>            # Match the inverse of $MATCH{ident}
    <ALIAS=/ident>      # Match inverse and capture to $MATCH{ident}
    <[ALIAS=/ident]>    # Match inverse and push on @{$MATCH{ident}}

The character pairs that are reversed during mirroring are: C<{> and C<}>,
C<[> and C<]>, C<(> and C<)>, C<< < >> and C<< > >>, C<«> and C<»>,
C<`> and C<'>.

The following mnemonics may be useful in distinguishing inverserefs from
backrefs: a backref starts with a C<\> (just like the standard Perl
regex backrefs C<\1> and C<\g{-2}> and C<< \k<name> >>), whereas an
inverseref starts with a C</> (like an HTML or XML closing tag). Or
just remember that C<< <\_IDENT> >> is "match the same again", and if you
want "the same again, only mirrored" instead, just mirror the C<\>
to get C<< </IDENT> >>.


=head2 Rematching parametric results and delimiters

The C<< <\I<IDENTIFIER>> >> and C<< </I<IDENTIFIER>> >> mechanisms
normally locate the literal to be matched by looking in
C<$MATCH{I<IDENTIFIER>}>.

However, you can cause them to look in C<$ARG{I<IDENTIFIER>}> instead,
by prefixing the identifier with a single C<:>. This is especially
useful when refactoring subrules. For example, instead of:

    <rule: Command>
        <Keyword>  <CommandBody>  end_ <\_Keyword>

    <rule: Placeholder>
        <Keyword>    \.\.\.   end_ <\_Keyword>

you could parameterize the Terminator rule, like so:

    <rule: Command>
        <Keyword>  <CommandBody>  <Terminator(:Keyword)>

    <rule: Placeholder>
        <Keyword>    \.\.\.   <Terminator(:Keyword)>

    <token: Terminator>
        end_ <\:Keyword>


=head2 Tracking and reporting match positions

Regexp::Grammars automatically predefines a special token that makes it
easy to track exactly where in its input a particular subrule matches.
That token is: C<< <matchpos> >>.

The C<< <matchpos> >> token implements a zero-width match that never
fails. It always returns the current index within the string that the
grammar is matching.

So, for example you could have your C<< <delimited_text> >> subrule
detect and report unterminated text like so:

    <token: delimited_text>
        qq? <delim> <text=(.*?)> </delim>
    |
        <matchpos> qq? <delim>
        <error: (?{"Unterminated string starting at index $MATCH{matchpos}"})>

Matching C<< <matchpos> >> in the second alternative causes
C<$MATCH{matchpos}> to contain the position in the string at which the
C<< <matchpos> >> subrule was matched (in this example: the start of the
unterminated text).

If you want the line number instead of the string index, use the
predefined C<< <matchline> >> subrule instead:

    <token: delimited_text>
              qq? <delim> <text=(.*?)> </delim>
    |   <matchline> qq? <delim>
        <error: (?{"Unterminated string starting at line $MATCH{matchline}"})>

Note that the line numbers returned by C<< <matchline> >> start at 1
(not at zero, as with C<< <matchpos> >>).

The C<< <matchpos> >> and C<< <matchline> >> subrules are just like any
other subrules; you can alias them (C<< <started_at=matchpos> >>) or
match them repeatedly ( C<< (?: <[matchline]> <[item]> )++ >>), etc.


=head1 Autoactions

The module also supports event-based parsing. You can specify a grammar
in the usual way and then, for a particular parse, layer a collection of
call-backs (known as "autoactions") over the grammar to handle the data
as it is parsed.

Normally, a grammar rule returns the result hash it has accumulated
(or whatever else was aliased to C<MATCH=> within the rule). However,
you can specify an autoaction object before the grammar is matched.

Once the autoaction object is specified, every time a rule succeeds
during the parse, its result is passed to the object via one of its
methods; specifically it is passed to the method whose name is the same
as the rule's.

For example, suppose you had a grammar that recognizes simple algebraic
expressions:

    my $expr_parser = do{
        use Regexp::Grammars;
        qr{
            <Expr>

            <rule: Expr>       <[Operand=Mult]>+ % <[Op=(\+|\-)]>

            <rule: Mult>       <[Operand=Pow]>+  % <[Op=(\*|/|%)]>

            <rule: Pow>        <[Operand=Term]>+ % <Op=(\^)>

            <rule: Term>          <MATCH=Literal>
                       |       \( <MATCH=Expr> \)

            <token: Literal>   <MATCH=( [+-]? \d++ (?: \. \d++ )?+ )>
        }xms
    };

You could convert this grammar to a calculator, by installing a set of
autoactions that convert each rule's result hash to the corresponding
value of the sub-expression that the rule just parsed. To do that, you
would create a class with methods whose names match the rules whose
results you want to change. For example:

    package Calculator;
    use List::Util qw< reduce >;

    sub new {
        my ($class) = @_;

        return bless {}, $class
    }

    sub Answer {
        my ($self, $result_hash) = @_;

        my $sum = shift @{$result_hash->{Operand}};

        for my $term (@{$result_hash->{Operand}}) {
            my $op = shift @{$result_hash->{Op}};
            if ($op eq '+') { $sum += $term; }
            else            { $sum -= $term; }
        }

        return $sum;
    }

    sub Mult {
        my ($self, $result_hash) = @_;

        return reduce { eval($a . shift(@{$result_hash->{Op}}) . $b) }
                      @{$result_hash->{Operand}};
    }

    sub Pow {
        my ($self, $result_hash) = @_;

        return reduce { $b ** $a } reverse @{$result_hash->{Operand}};
    }


Objects of this class (and indeed the class itself) now have methods
corresponding to some of the rules in the expression grammar. To
apply those methods to the results of the rules (as they parse) you
simply install an object as the "autoaction" handler, immediately
before you initiate the parse:

    if ($text ~= $expr_parser->with_actions(Calculator->new)) {
        say $/{Answer};   # Now prints the result of the expression
    }

The C<with_actions()> method expects to be passed an object or
classname. This object or class will be installed as the autoaction
handler for the next match against any grammar. After that match, the
handler will be uninstalled. C<with_actions()> returns the grammar it's
called on, making it easy to call it as part of a match (which is the
recommended idiom).

With a C<Calculator> object set as the autoaction handler, whenever
the C<Answer>, C<Mult>, or C<Pow> rule of the grammar matches, the
corresponding C<Answer>, C<Mult>, or C<Pow> method of the
C<Calculator> object will be called (with the rule's result value
passed as its only argument), and the result of the method will be
used as the result of the rule.

Note that nothing new happens when a C<Term> or C<Literal> rule matches,
because the C<Calculator> object doesn't have methods with those names.

The overall effect, then, is to allow you to specify a grammar without
rule-specific bahaviours and then, later, specify a set of final actions
(as methods) for some or all of the rules of the grammar.

Note that, if a particular callback method returns C<undef>, the result
of the corresponding rule will be passed through without modification.


=head1 Named grammars

All the grammars shown so far are confined to a single regex. However,
Regexp::Grammars also provides a mechanism that allows you to defined
named grammars, which can then be imported into other regexes. This
gives the a way of modularizing common grammatical components.

=head2 Defining a named grammar

You can create a named grammar using the C<< <grammar:...> >>
directive. This directive must appear before the first rule definition
in the grammar, and instead of any start-rule. For example:

    qr{
        <grammar: List::Generic>

        <rule: List>
            <MATCH=[Item]>+ % <Separator>

        <rule: Item>
            \S++

        <token: Separator>
            \s* , \s*
    }x;

This creates a grammar named C<List::Generic>, and installs it in the module's
internal caches, for future reference.

Note that there is no need (or reason) to assign the resulting regex to
a variable, as the named grammar cannot itself be matched against.


=head2 Using a named grammar

To make use of a named grammar, you need to incorporate it into another
grammar, by inheritance. To do that, use the C<< <extends:...> >>
directive, like so:

    my $parser = qr{
        <extends: List::Generic>

        <List>
    }x;

The C<< <extends:...> >> directive incorporates the rules defined in the
specified grammar into the current regex. You can then call any of those
rules in the start-pattern.


=head2 Overriding an inherited rule or token

Subrule dispatch within a grammar is always polymorphic. That is, when a
subrule is called, the most-derived rule of the same name within the
grammar's hierarchy is invoked.

So, to replace a particular rule within grammar, you simply need to inherit
that grammar and specify new, more-specific versions of any rules you
want to change. For example:

    my $list_of_integers = qr{
        <List>

        # Inherit rules from base grammar...
        <extends: List::Generic>

        # Replace Item rule from List::Generic...
        <rule: Item>
            [+-]? \d++
    }x;

You can also use C<< <extends:...> >> in other named grammars, to create
hierarchies:

    qr{
        <grammar: List::Integral>
        <extends: List::Generic>

        <token: Item>
            [+-]? <MATCH=(<.Digit>+)>

        <token: Digit>
            \d
    }x;

    qr{
        <grammar: List::ColonSeparated>
        <extends: List::Generic>

        <token: Separator>
            \s* : \s*
    }x;

    qr{
        <grammar: List::Integral::ColonSeparated>
        <extends: List::Integral>
        <extends: List::ColonSeparated>
    }x;

As shown in the previous example, Regexp::Grammars allows you
to multiply inherit two (or more) base grammars. For example, the
C<List::Integral::ColonSeparated> grammar takes the definitions of
C<List> and C<Item> from the C<List::Integral> grammar, and the
definition of C<Separator> from C<List::ColonSeparated>.

Note that grammars dispatch subrule calls using C3 method lookup, rather
than Perl's older DFS lookup. That's why C<List::Integral::ColonSeparated>
correctly gets the more-specific C<Separator> rule defined in
C<List::ColonSeparated>, rather than the more-generic version defined in
C<List::Generic> (via C<List::Integral>). See C<perldoc mro> for more
discussion of the C3 dispatch algorithm.


=head2 Augmenting an inherited rule or token

Instead of replacing an inherited rule, you can augment it.

For example, if you need a grammar for lists of hexademical
numbers, you could inherit the behaviour of C<List::Integral>
and add the hex digits to its C<Digit> token:

    my $list_of_hexadecimal = qr{
        <List>

        <extends: List::Integral>

        <token: Digit>
            <List::Integral::Digit>
          | [A-Fa-f]
    }x;

If you call a subrule using a fully qualified name (such as
C<< <List::Integral::Digit> >>), the grammar calls that
version of the rule, rather than the most-derived version.


=head2 Debugging named grammars

Named grammars are independent of each other, even when inherited. This
means that, if debugging is enabled in a derived grammar, it will not be
active in any rules inherited from a base grammar, unless the base
grammar also included a C<< <debug:...> >> directive.

This is a deliberate design decision, as activating the debugger adds a
significant amount of code to each grammar's implementation, which is
detrimental to the matching performance of the resulting regexes.

If you need to debug a named grammar, the best approach is to include a
C<< <debug: same> >> directive at the start of the grammar. The presence
of this directive will ensure the necessary extra debugging code is
included in the regex implementing the grammar, while setting C<same>
mode will ensure that the debugging mode isn't altered when the matcher
uses the inherited rules.


=head1 Common parsing techniques

=head2 Result distillation

Normally, calls to subrules produce nested result-hashes within the
current result-hash. Those nested hashes always have at least one
automatically supplied key (C<"">), whose value is the entire substring
that the subrule matched.

If there are no other nested captures within the subrule, there will be
no other keys in the result-hash. This would be annoying as a typical
nested grammar would then produce results consisting of hashes of
hashes, with each nested hash having only a single key (C<"">). This in
turn would make postprocessing the result-hash (in C<%/>) far more
complicated than it needs to be.

To avoid this behaviour, if a subrule's result-hash doesn't contain any keys
except C<"">, the module "flattens" the result-hash, by replacing it with
the value of its single key.

So, for example, the grammar:

    mv \s* <from> \s* <to>

    <rule: from>   [\w/.-]+
    <rule: to>     [\w/.-]+

I<doesn't> return a result-hash like this:

    {
        ""     => 'mv /usr/local/lib/libhuh.dylib  /dev/null/badlib',
        'from' => { "" => '/usr/local/lib/libhuh.dylib' },
        'to'   => { "" => '/dev/null/badlib'            },
    }

Instead, it returns:

    {
        ""     => 'mv /usr/local/lib/libhuh.dylib  /dev/null/badlib',
        'from' => '/usr/local/lib/libhuh.dylib',
        'to'   => '/dev/null/badlib',
    }

That is, because the C<'from'> and C<'to'> subhashes each have only a single
entry, they are each "flattened" to the value of that entry.

This flattening also occurs if a result-hash contains only "private" keys
(i.e. keys starting with underscores). For example:

    mv \s* <from> \s* <to>

    <rule: from>   <_dir=path>? <_file=filename>
    <rule: to>     <_dir=path>? <_file=filename>

    <token: path>      [\w/.-]*/
    <token: filename>  [\w.-]+

Here, the C<from> rule produces a result like this:

    from => {
          "" => '/usr/local/bin/perl',
        _dir => '/usr/local/bin/',
       _file => 'perl',
    }

which is automatically stripped of "private" keys, leaving:

    from => {
          "" => '/usr/local/bin/perl',
    }

which is then automatically flattened to:

    from => '/usr/local/bin/perl'


=head3 List result distillation

A special case of result distillation occurs in a separated
list, such as:

    <rule: List>

        <[Item]>+ % <[Sep=(,)]>

If this construct matches just a single item, the result hash will
contain a single entry consisting of a nested array with a single
value, like so:

    { Item => [ 'data' ] }

Instead of returning this annoyingly nested data structure, you can tell
Regexp::Grammars to flatten it to just the inner data with a special
directive:

    <rule: List>

        <[Item]>+ % <[Sep=(,)]>

        <minimize:>

The C<< <minimize:> >> directive examines the result hash (i.e.
C<%MATCH>). If that hash contains only a single entry, which is a
reference to an array with a single value, then the directive assigns
that single value directly to C<$MATCH>, so that it will be returned
instead of the usual result hash.

This means that a normal separated list still results in a hash
containing all elements and separators, but a "degenerate" list of only
one item results in just that single item.


=head3 Manual result distillation

Regexp::Grammars also offers full manual control over the distillation
process. If you use the reserved word C<MATCH> as the alias for
a subrule call:

    <MATCH=filename>

or a subpattern match:

    <MATCH=( \w+ )>

or a code block:

    <MATCH=(?{ 42 })>

then the current rule will treat the return value of that subrule,
pattern, or code block as its complete result, and return that value
instead of the usual result-hash it constructs. This is the case even if
the result has other entries that would normally also be returned.

For example, in a rule like:

    <rule: term>
          <MATCH=literal>
        | <left_paren> <MATCH=expr> <right_paren>

The use of C<MATCH> aliases causes the rule to return either whatever
C<< <literal> >> returns, or whatever C<< <expr> >> returns (provided
it's between left and right parentheses).

Note that, in this second case, even though C<< <left_paren> >> and
C<< <right_paren> >> I<are> captured to the result-hash, they are
not returned, because the C<MATCH> alias overrides the normal "return
the result-hash" semantics and returns only what its associated
subrule (i.e. C<< <expr> >>) produces.


=head3 Programmatic result distillation

It's also possible to control what a rule returns from within a code block.
Regexp::Grammars provides a set of reserved variables that give direct
access to the result-hash.

The result-hash itself can be accessed as C<%MATCH> within any code block
inside a rule. For example:

    <rule: sum>
        <X=product> \+ <Y=product>
            <MATCH=(?{ $MATCH{X} + $MATCH{Y} })>

Here, the rule matches a product (aliased C<'X'> in the result-hash),
then a literal C<'+'>, then another product (aliased to C<'Y'> in the
result-hash). The rule then executes the code block, which accesses the two
saved values (as C<$MATCH{X}> and C<$MATCH{Y}>), adding them together.
Because the block is itself aliased to C<MATCH>, the sum produced by the block
becomes the (only) result of the rule.

It is also possible to set the rule result from within a code block (instead
of aliasing it). The special "override" return value is represented by the
special variable C<$MATCH>. So the previous example could be rewritten:

    <rule: sum>
        <X=product> \+ <Y=product>
            (?{ $MATCH = $MATCH{X} + $MATCH{Y} })

Both forms are identical in effect. Any assignment to C<$MATCH> overrides the
normal "return all subrule results" behaviour.

Assigning to C<$MATCH> directly is particularly handy if the result
may not always be "distillable", for example:

    <rule: sum>
        <X=product> \+ <Y=product>
            (?{ if (!ref $MATCH{X} && !ref $MATCH{Y}) {
                    # Reduce to sum, if both terms are simple scalars...
                    $MATCH = $MATCH{X} + $MATCH{Y};
                }
                else {
                    # Return full syntax tree for non-simple case...
                    $MATCH{op} = '+';
                }
            })

Note that you can also partially override the subrule return behaviour.
Normally, the subrule returns the complete text it matched as its context
substring (i.e. under the "empty key") in its result-hash. That is, of
course, C<$MATCH{""}>, so you can override just that behaviour by
directly assigning to that entry.

For example, if you have a rule that matches key/value pairs from a
configuration file, you might prefer that any trailing comments not be
included in the "matched text" entry of the rule's result-hash. You could
hide such comments like so:

    <rule: config_line>
        <key> : <value>  <comment>?
            (?{
                # Edit trailing comments out of "matched text" entry...
                $MATCH = "$MATCH{key} : $MATCH{value}";
            })

Some more examples of the uses of C<$MATCH>:

    <rule: FuncDecl>
      # Keyword  Name               Keep return the name (as a string)...
        func     <Identifier> ;     (?{ $MATCH = $MATCH{'Identifier'} })


    <rule: NumList>
      # Numbers in square brackets...
        \[
            ( \d+ (?: , \d+)* )
        \]

      # Return only the numbers...
        (?{ $MATCH = $CAPTURE })


    <token: Cmd>
      # Match standard variants then standardize the keyword...
        (?: mv | move | rename )      (?{ $MATCH = 'mv'; })


=head2 Parse-time data processing

Using code blocks in rules, it's often possible to fully process data as
you parse it. For example, the C<< <sum> >> rule shown in the previous section
might be part of a simple calculator, implemented entirely in a single
grammar. Such a calculator might look like this:


    my $calculator = do{
        use Regexp::Grammars;
        qr{
            <Answer>

            <rule: Answer>
                ( <.Mult>+ % <.Op=([+-])> )
                    <MATCH= (?{ eval $CAPTURE })>

            <rule: Mult>
                ( <.Pow>+ % <.Op=([*/%])> )
                    <MATCH= (?{ eval $CAPTURE })>

            <rule: Pow>
                <X=Term> \^ <Y=Pow>
                    <MATCH= (?{ $MATCH{X} ** $MATCH{Y}; })>
              |
                    <MATCH=Term>

            <rule: Term>
                    <MATCH=Literal>
              | \(  <MATCH=Answer>  \)

            <token: Literal>
                    <MATCH= ( [+-]? \d++ (?: \. \d++ )?+ )>
        }xms
    };

    while (my $input = <>) {
        if ($input =~ $calculator) {
            say "--> $/{Answer}";
        }
    }

Because every rule computes a value using the results of the subrules
below it, and aliases that result to its C<MATCH>, each rule returns a
complete evaluation of the subexpression it matches, passing that back
to higher-level rules, which then do the same.

Hence, the result returned to the very top-level rule (i.e. to C<<
<Answer> >>) is the complete evaluation of the entire expression that
was matched. That means that, in the very process of having matched a
valid expression, the calculator has also computed the value of that
expression, which can then simply be printed directly.

It is often possible to have a grammar fully (or sometimes at least
partially) evaluate or transform the data it is parsing, and this
usually leads to very efficient and easy-to-maintain implementations.

The main limitation of this technique is that the data has to be in a
well-structured form, where subsets of the data can be evaluated using
only local information. In cases where the meaning of the data is
distributed through that data non-hierarchically, or relies on global
state, or on external information, it is often better to have the grammar
simply construct a complete syntax tree for the data first, and then evaluate
that syntax tree separately, after parsing is complete. The following section
describes a feature of Regexp::Grammars that can make this second style of
data processing simpler and more maintainable.


=head2 Object-oriented parsing

When a grammar has parsed successfully, the C<%/> variable will contain a
series of nested hashes (and possibly arrays) representing the hierarchical
structure of the parsed data.

Typically, the next step is to walk that tree, extracting or
converting or otherwise processing that information. If the tree has nodes of
many different types, it can be difficult to build a recursive subroutine that
can navigate it easily.

A much cleaner solution is possible if the nodes of the tree are proper
objects.  In that case, you just define a C<process()> or C<traverse()> method
for eah of the classes, and have every node call that method on each of its
children. For example, if the parser were to return a tree of nodes
representing the contents of a LaTeX file, then you could define the following
methods:

    sub Latex::file::explain
    {
        my ($self, $level) = @_;
        for my $element (@{$self->{element}}) {
            $element->explain($level);
        }
    }

    sub Latex::element::explain {
        my ($self, $level) = @_;
        (  $self->{command} || $self->{literal})->explain($level)
    }

    sub Latex::command::explain {
        my ($self, $level) = @_;
        say "\t"x$level, "Command:";
        say "\t"x($level+1), "Name: $self->{name}";
        if ($self->{options}) {
            say "\t"x$level, "\tOptions:";
            $self->{options}->explain($level+2)
        }

        for my $arg (@{$self->{arg}}) {
            say "\t"x$level, "\tArg:";
            $arg->explain($level+2)
        }
    }

    sub Latex::options::explain {
        my ($self, $level) = @_;
        $_->explain($level) foreach @{$self->{option}};
    }

    sub Latex::literal::explain {
        my ($self, $level, $label) = @_;
        $label //= 'Literal';
        say "\t"x$level, "$label: ", $self->{q{}};
    }

and then simply write:

    if ($text =~ $LaTeX_parser) {
        $/{LaTeX_file}->explain();
    }

and the chain of C<explain()> calls would cascade down the nodes of the tree,
each one invoking the appropriate C<explain()> method according to the type of
node encountered.

The only problem is that, by default, Regexp::Grammars returns a tree of
plain-old hashes, not LaTeX::Whatever objects. Fortunately, it's easy to
request that the result hashes be automatically blessed into the appropriate
classes, using the C<< <objrule:...> >> and C<< <objtoken:...> >> directives.

These directives are identical to the C<< <rule:...> >> and C<<
<token:...> >> directives (respectively), except that the rule or token
they create will also convert the hash it normally returns into an
object of a specified class. This conversion is done by passing the result
hash to the class's constructor:

    $class->new(\%result_hash)

if the class has a constructor method named C<new()>, or else (if
the class doesn't provide a constructor) by directly blessing the
result hash:

    bless \%result_hash, $class

Note that, even if object is constructed via its own constructor, the
module still expects the new object to be hash-based, and will fail if
the object is anything but a blessed hash. The module issues an
error in this case.

The generic syntax for these types of rules and tokens is:

    <objrule:  CLASS::NAME = RULENAME  >
    <objtoken: CLASS::NAME = TOKENNAME >

For example:

    <objrule: LaTeX::Element=component>
        # ...Defines a rule that can be called as <component>
        # ...and which returns a hash-based LaTeX::Element object

    <objtoken: LaTex::Literal=atom>
        # ...Defines a token that can be called as <atom>
        # ...and which returns a hash-based LaTeX::Literal object

Note that, just as in L<aliased subrule calls|"Renaming subrule results">,
the name by which something is referred to outside the grammar (in this
case, the class name) comes I<before> the C<=>, whereas the name that it
is referred to inside the grammar comes I<after> the C<=>.

You can freely mix object-returning and plain-old-hash-returning rules
and tokens within a single grammar, though you have to be careful not to
subsequently try to call a method on any of the unblessed nodes.

=head4 An important caveat regarding OO rules

Prior to Perl 5.14.0, Perl's regex engine was not fully re-entrant.
This means that in older versions of Perl, it is not possible to
re-invoke the regex engine when already inside the regex engine.

This means that you need to be careful that the C<new()>
constructors that are called by your object-rules do not themselves
use regexes in any way, unless you're running under Perl 5.14 or later
(in which case you can ignore what follows).

The two ways this is most likely to happen are:

=over

=item 1.

If you're using a class built on Moose, where one or more of the C<has>
uses a type constraint (such as C<'Int'>) that is implemented via regex
matching. For example:

    has 'id' => (is => 'rw', isa => 'Int');

The workaround (for pre-5.14 Perls) is to replace the type
constraint with one that doesn't use a regex. For example:

    has 'id' => (is => 'rw', isa => 'Num');

Alternatively, you could define your own type constraint that
avoids regexes:

    use Moose::Util::TypeConstraints;

    subtype 'Non::Regex::Int',
         as 'Num',
      where { int($_) == $_ };

    no Moose::Util::TypeConstraints;

    # and later...

    has 'id' => (is => 'rw', isa => 'Non::Regex::Int');

=item 2.

If your class uses an C<AUTOLOAD()> method to implement its constructor
and that method uses the typical:

    $AUTOLOAD =~ s/.*://;

technique. The workaround here is to achieve the same effect without a
regex. For example:

    my $last_colon_pos = rindex($AUTOLOAD, ':');
    substr $AUTOLOAD, 0, $last_colon_pos+1, q{};

=back

Note that this caveat against using nested regexes also applies to any
code blocks executed inside a rule or token (whether or not those rules
or tokens are object-oriented).

=head3 A naming shortcut

If an C<< <objrule:...> >> or C<< <objtoken:...> >> is defined with a
class name that is I<not> followed by C<=> and a rule name, then the
rule name is determined automatically from the classname.
Specifically, the final component of the classname (i.e. after the last
C<::>, if any) is used.

For example:

    <objrule: LaTeX::Element>
        # ...Defines a rule that can be called as <Element>
        # ...and which returns a hash-based LaTeX::Element object

    <objtoken: LaTex::Literal>
        # ...Defines a token that can be called as <Literal>
        # ...and which returns a hash-based LaTeX::Literal object

    <objtoken: Comment>
        # ...Defines a token that can be called as <Comment>
        # ...and which returns a hash-based Comment object


=head1 Debugging

Regexp::Grammars provides a number of features specifically designed to help
debug both grammars and the data they parse.

All debugging messages are written to a log file (which, by default, is
just STDERR). However, you can specify a disk file explicitly by placing a
C<< <logfile:...> >> directive at the start of your grammar:

    $grammar = qr{

        <logfile: LaTeX_parser_log >

        \A <LaTeX_file> \Z    # Pattern to match

        <rule: LaTeX_file>
            # etc.
    }x;

You can also explicitly specify that messages go to the terminal:

        <logfile: - >


=head2 Debugging grammar creation with C<< <logfile:...> >>

Whenever a log file has been directly specified,
Regexp::Grammars automatically does verbose static analysis of your grammar.
That is, whenever it compiles a grammar containing an explicit
C<< <logfile:...> >> directive it logs a series of messages explaining how it
has interpreted the various components of that grammar. For example, the
following grammar:

    <logfile: parser_log >

    <cmd>

    <rule: cmd>
        mv <from=file> <to=file>
      | cp <source> <[file]>  <.comment>?

would produce the following analysis in the 'parser_log' file:

    info | Processing the main regex before any rule definitions
         |    |
         |    |...Treating <cmd> as:
         |    |      |  match the subrule <cmd>
         |    |       \ saving the match in $MATCH{'cmd'}
         |    |
         |     \___End of main regex
         |
    info | Defining a rule: <cmd>
         |    |...Returns: a hash
         |    |
         |    |...Treating ' mv ' as:
         |    |       \ normal Perl regex syntax
         |    |
         |    |...Treating <from=file> as:
         |    |      |  match the subrule <file>
         |    |       \ saving the match in $MATCH{'from'}
         |    |
         |    |...Treating <to=file> as:
         |    |      |  match the subrule <file>
         |    |       \ saving the match in $MATCH{'to'}
         |    |
         |    |...Treating ' | cp ' as:
         |    |       \ normal Perl regex syntax
         |    |
         |    |...Treating <source> as:
         |    |      |  match the subrule <source>
         |    |       \ saving the match in $MATCH{'source'}
         |    |
         |    |...Treating <[file]> as:
         |    |      |  match the subrule <file>
         |    |       \ appending the match to $MATCH{'file'}
         |    |
         |    |...Treating <.comment>? as:
         |    |      |  match the subrule <comment> if possible
         |    |       \ but don't save anything
         |    |
         |     \___End of rule definition

This kind of static analysis is a useful starting point in debugging a
miscreant grammar, because it enables you to see what you actually
specified (as opposed to what you I<thought> you'd specified).


=head2 Debugging grammar execution with C<< <debug:...> >>

Regexp::Grammars also provides a simple interactive debugger, with which you
can observe the process of parsing and the data being collected in any
result-hash.

To initiate debugging, place a C<< <debug:...> >> directive anywhere in your
grammar. When parsing reaches that directive the debugger will be activated,
and the command specified in the directive immediately executed. The available
commands are:

    <debug: on>    - Enable debugging, stop when a rule matches
    <debug: match> - Enable debugging, stop when a rule matches
    <debug: try>   - Enable debugging, stop when a rule is tried
    <debug: run>   - Enable debugging, run until the match completes
    <debug: same>  - Continue debugging (or not) as currently
    <debug: off>   - Disable debugging and continue parsing silently

    <debug: continue> - Synonym for <debug: run>
    <debug: step>     - Synonym for <debug: try>

These directives can be placed anywhere within a grammar and take effect
when that point is reached in the parsing. Hence, adding a
C<< <debug:step> >> directive is very much like setting a breakpoint at that
point in the grammar. Indeed, a common debugging strategy is to turn
debugging on and off only around a suspect part of the grammar:

    <rule: tricky>   # This is where we think the problem is...
        <debug:step>
        <preamble> <text> <postscript>
        <debug:off>

Once the debugger is active, it steps through the parse, reporting rules
that are tried, matches and failures, backtracking and restarts, and the
parser's location within both the grammar and the text being matched. That
report looks like this:

    ===============> Trying <grammar> from position 0
    > cp file1 file2 |...Trying <cmd>
                     |   |...Trying <cmd=(cp)>
                     |   |    \FAIL <cmd=(cp)>
                     |    \FAIL <cmd>
                      \FAIL <grammar>
    ===============> Trying <grammar> from position 1
     cp file1 file2  |...Trying <cmd>
                     |   |...Trying <cmd=(cp)>
     file1 file2     |   |    \_____<cmd=(cp)> matched 'cp'
    file1 file2      |   |...Trying <[file]>+
     file2           |   |    \_____<[file]>+ matched 'file1'
                     |   |...Trying <[file]>+
    [eos]            |   |    \_____<[file]>+ matched ' file2'
                     |   |...Trying <[file]>+
                     |   |    \FAIL <[file]>+
                     |   |...Trying <target>
                     |   |   |...Trying <file>
                     |   |   |    \FAIL <file>
                     |   |    \FAIL <target>
     <~~~~~~~~~~~~~~ |   |...Backtracking 5 chars and trying new match
    file2            |   |...Trying <target>
                     |   |   |...Trying <file>
                     |   |   |    \____ <file> matched 'file2'
    [eos]            |   |    \_____<target> matched 'file2'
                     |    \_____<cmd> matched ' cp file1 file2'
                      \_____<grammar> matched ' cp file1 file2'

The first column indicates the point in the input at which the parser is
trying to match, as well as any backtracking or forward searching it may
need to do. The remainder of the columns track the parser's hierarchical
traversal of the grammar, indicating which rules are tried, which
succeed, and what they match.


Provided the logfile is a terminal (as it is by default), the debugger
also pauses at various points in the parsing process--before trying a
rule, after a rule succeeds, or at the end of the parse--according to
the most recent command issued. When it pauses, you can issue a new
command by entering a single letter:

    m       - to continue until the next subrule matches
    t or s  - to continue until the next subrule is tried
    r or c  - to continue to the end of the grammar
    o       - to switch off debugging

Note that these are the first letters of the corresponding
C<< <debug:...> >> commands, listed earlier. Just hitting ENTER while the
debugger is paused repeats the previous command.

While the debugger is paused you can also type a 'd', which will display
the result-hash for the current rule. This can be useful for detecting
which rule isn't returning the data you expected.


=head3 Resizing the context string

By default, the first column of the debugger output (which shows the
current matching position within the string) is limited to a width of
20 columns.

However, you can change that limit calling the
C<Regexp::Grammars::set_context_width()> subroutine. You have to specify
the fully qualified name, however, as Regexp::Grammars does not export
this (or any other) subroutine.

C<set_context_width()> expects a single argument: a positive integer
indicating the maximal allowable width for the context column. It issues
a warning if an invalid value is passed, and ignores it.

If called in a void context, C<set_context_width()> changes the context
width permanently throughout your application. If called in a scalar or
list context, C<set_context_width()> returns an object whose destructor
will cause the context width to revert to its previous value. This means
you can temporarily change the context width within a given block with
something like:

    {
        my $temporary = Regexp::Grammars::set_context_width(50);

        if ($text =~ $parser) {
            do_stuff_with( %/ );
        }

    } # <--- context width automagically reverts at this point

and the context width will change back to its previous value when
C<$temporary> goes out of scope at the end of the block.


=head2 User-defined logging with C<< <log:...> >>

Both static and interactive debugging send a series of predefined log messages
to whatever log file you have specified. It is also possible to send
additional, user-defined messages to the log, using the C<< <log:...> >>
directive.

This directive expects either a simple text or a codeblock as its single
argument. If the argument is a code block, that code is expected to
return the text of the message; if the argument is anything else, that
something else I<is> the literal message. For example:

    <rule: ListElem>

        <Elem=   ( [a-z]\d+) >
            <log: Checking for a suffix, too...>

        <Suffix= ( : \d+   ) >?
            <log: (?{ "ListElem: $MATCH{Elem} and $MATCH{Suffix}" })>

User-defined log messages implemented using a codeblock can also specify
a severity level. If the codeblock of a C<< <log:...> >> directive
returns two or more values, the first is treated as a log message
severity indicator, and the remaining values as separate lines of text
to be logged. For example:

    <rule: ListElem>
        <Elem=   ( [a-z]\d+) >
        <Suffix= ( : \d+   ) >?

            <log: (?{
                warn => "Elem was: $MATCH{Elem}",
                        "Suffix was $MATCH{Suffix}",
            })>

When they are encountered, user-defined log messages are interspersed
between any automatic log messages (i.e. from the debugger), at the correct
level of nesting for the current rule.


=head2 Debugging non-grammars

I<[Note that, with the release in 2012 of the Regexp::Debugger module (on
CPAN) the techniques described below are unnecessary. If you need to
debug plain Perl regexes, use Regexp::Debugger instead.]>

It is possible to use Regexp::Grammars without creating I<any> subrule
definitions, simply to debug a recalcitrant regex. For example, if the
following regex wasn't working as expected:

    my $balanced_brackets = qr{
        \(             # left delim
        (?:
            \\         # escape or
        |   (?R)       # recurse or
        |   .          # whatever
        )*
        \)             # right delim
    }xms;

you could instrument it with aliased subpatterns and then debug it
step-by-step, using Regexp::Grammars:

    use Regexp::Grammars;

    my $balanced_brackets = qr{
        <debug:step>

        <.left_delim=  (  \(  )>
        (?:
            <.escape=  (  \\  )>
        |   <.recurse= ( (?R) )>
        |   <.whatever=(  .   )>
        )*
        <.right_delim= (  \)  )>
    }xms;

    while (<>) {
        say 'matched' if /$balanced_brackets/;
    }

Note the use of L<amnesiac aliased subpatterns|"Amnesiac subrule calls">
to avoid needlessly building a result-hash. Alternatively, you could use
listifying aliases to preserve the matching structure as an additional
debugging aid:

    use Regexp::Grammars;

    my $balanced_brackets = qr{
        <debug:step>

        <[left_delim=  (  \(  )]>
        (?:
            <[escape=  (  \\  )]>
        |   <[recurse= ( (?R) )]>
        |   <[whatever=(  .   )]>
        )*
        <[right_delim= (  \)  )]>
    }xms;

    if ( '(a(bc)d)' =~ /$balanced_brackets/) {
        use Data::Dumper 'Dumper';
        warn Dumper \%/;
    }

=head1 Handling errors when parsing

Assuming you have correctly debugged your grammar, the next source of problems
will probably be invalid input (especially if that input is being provided
interactively). So Regexp::Grammars also provides some support for detecting
when a parse is likely to fail...and informing the user why.

=head2 Requirements

The C<< <require:...> >> directive is useful for testing conditions
that it's not easy (or even possible) to check within the syntax of the
the regex itself. For example:

    <rule: IPV4_Octet_Decimal>
        # Up three digits...
        <MATCH= ( \d{1,3}+ )>

        # ...but less than 256...
        <require: (?{ $MATCH <= 255 })>

A require expects a regex codeblock as its argument and succeeds if the final
value of that codeblock is true. If the final value is false, the directive
fails and the rule starts backtracking.

Note, in this example that the digits are matched with C< \d{1,3}+ >. The
trailing C<+> prevents the C<{1,3}> repetition from backtracking to a smaller
number of digits if the C<< <require:...> >> fails.


=head2 Handling failure

The module has limited support for error reporting from within a grammar,
in the form of the C<< <error:...> >> and C<< <warning:...> >> directives
and their shortcuts: C<< <...> >>, C<< <!!!> >>, and C<< <???> >>

=head3 Error messages

The C<< <error: MSG> >> directive queues a I<conditional> error message
within C<@!> and then fails to match (that is, it is equivalent to a
C<(?!)> when matching). For example:

    <rule: ListElem>
        <SerialNumber>
      | <ClientName>
      | <error: (?{ $errcount++ . ': Missing list element' })>

So a common code pattern when using grammars that do this kind of error
detection is:

    if ($text =~ $grammar) {
        # Do something with the data collected in %/
    }
    else {
        say {*STDERR} $_ for @!;   # i.e. report all errors
    }

Each error message is conditional in the sense that, if any surrounding rule
subsequently matches, the message is automatically removed from C<@!>. This
implies that you can queue up as many error messages as you wish, but they
will only remain in C<@!> if the match ultimately fails. Moreover, only those
error messages originating from rules that actually contributed to the
eventual failure-to-match will remain in C<@!>.

If a code block is specified as the argument, the error message is whatever
final value is produced when the block is executed. Note that this final value
does not have to be a string (though it does have to be a scalar).

    <rule: ListElem>
        <SerialNumber>
      | <ClientName>
      | <error: (?{
            # Return a hash, with the error information...
            { errnum => $errcount++, msg => 'Missing list element' }
        })>

If anything else is specified as the argument, it is treated as a
literal error string (and may not contain an unbalanced C<< '<' >>
or C<< '>' >>, nor any interpolated variables).

However, if the literal error string begins with "Expected " or
"Expecting ", then the error string automatically has the following
"context suffix" appended:

    , but found '$CONTEXT' instead

For example:

    qr{ <Arithmetic_Expression>                # ...Match arithmetic expression
      |                                        # Or else
        <error: Expected a valid expression>   # ...Report error, and fail

        # Rule definitions here...
    }xms;

On an invalid input this example might produce an error message like:

    "Expected a valid expression, but found '(2+3]*7/' instead"

The value of the special $CONTEXT variable is found by looking ahead in
the string being matched against, to locate the next sequence of non-blank
characters after the current parsing position. This variable may also be
explicitly used within the C<< <error: (?{...})> >> form of the directive.

As a special case, if you omit the message entirely from the directive,
it is supplied automatically, derived from the name of the current rule.
For example, if the following rule were to fail to match:

    <rule: Arithmetic_expression>
          <Multiplicative_Expression>+ % ([+-])
        | <error:>

the error message queued would be:

    "Expected arithmetic expression, but found 'one plus two' instead"

Note however, that it is still essential to include the colon in the
directive. A common mistake is to write:

    <rule: Arithmetic_expression>
          <Multiplicative_Expression>+ % ([+-])
        | <error>

which merely attempts to call C<< <rule: error> >> if the first
alternative fails.

=head3 Warning messages

Sometimes, you want to detect problems, but not invalidate the entire
parse as a result. For those occasions, the module provides a "less stringent"
form of error reporting: the C<< <warning:...> >> directive.

This directive is exactly the same as an C<< <error:...> >> in every respect
except that it does not induce a failure to match at the point it appears.

The directive is, therefore, useful for reporting I<non-fatal> problems
in a parse. For example:

    qr{ \A            # ...Match only at start of input
        <ArithExpr>   # ...Match a valid arithmetic expression

        (?:
            # Should be at end of input...
            \s* \Z
          |
            # If not, report the fact but don't fail...
            <warning: Expected end-of-input>
            <warning: (?{ "Extra junk at index $INDEX: $CONTEXT" })>
        )

        # Rule definitions here...
    }xms;

Note that, because they do not induce failure, two or more
C<< <warning:...> >> directives can be "stacked" in sequence,
as in the previous example.

=head3 Stubbing

The module also provides three useful shortcuts, specifically to
make it easy to declare, but not define, rules and tokens.

The C<< <...> >> and C<< <???> >> directives are equivalent to
the directive:

    <error: Cannot match RULENAME (not implemented)>

The C<< <???> >> is equivalent to the directive:

    <warning: Cannot match RULENAME (not implemented)>

For example, in the following grammar:

    <grammar: List::Generic>

    <rule: List>
        <[Item]>+ % (\s*,\s*)

    <rule: Item>
        <...>

the C<Item> rule is declared but not defined. That means the grammar
will compile correctly, (the C<List> rule won't complain about a call to
a non-existent C<Item>), but if the C<Item> rule isn't overridden in
some derived grammar, a match-time error will occur when C<List> tries
to match the C<< <...> >> within C<Item>.


=head3 Localizing the (semi-)automatic error messages

Error directives of any of the following forms:

    <error: Expecting identifier>

    <error: >

    <...>

    <!!!>

or their warning equivalents:

    <warning: Expecting identifier>

    <warning: >

    <???>

each autogenerate part or all of the actual error message they produce.
By default, that autogenerated message is always produced in English.

However, the module provides a mechanism by which you can
intercept I<every> error or warning that is queued to C<@!>
via these directives...and localize those messages.

To do this, you call C<Regexp::Grammars::set_error_translator()>
(with the full qualification, since Regexp::Grammars does not
export it...nor anything else, for that matter).

The C<set_error_translator()> subroutine expect as single
argument, which must be a reference to another subroutine.
This subroutine is then called whenever an error or warning
message is queued to C<@!>.

The subroutine is passed three arguments:

=over

=item *

the message string,

=item *

the name of the rule from which the error or warning was queued, and

=item *

the value of C<$CONTEXT> when the error or warning was encountered

=back

The subroutine is expected to return the final version of the message
that is actually to be appended to C<@!>. To accomplish this it may make
use of one of the many internationalization/localization modules
available in Perl, or it may do the conversion entirely by itself.

The first argument is always exactly what appeared as a message in the
original directive (regardless of whether that message is supposed to
trigger autogeneration, or is just a "regular" error message).
That is:

    Directive                         1st argument

    <error: Expecting identifier>     "Expecting identifier"
    <warning: That's not a moon!>     "That's not a moon!"
    <error: >                         ""
    <warning: >                       ""
    <...>                             ""
    <!!!>                             ""
    <???>                             ""

The second argument always contains the name of the rule in which the
directive was encountered. For example, when invoked from within
C<< <rule: Frinstance> >> the following directives produce:

    Directive                         2nd argument

    <error: Expecting identifier>     "Frinstance"
    <warning: That's not a moon!>     "Frinstance"
    <error: >                         "Frinstance"
    <warning: >                       "Frinstance"
    <...>                             "-Frinstance"
    <!!!>                             "-Frinstance"
    <???>                             "-Frinstance"

Note that the "unimplemented" markers pass the rule name with a
preceding C<'-'>. This allows your translator to distinguish between
"empty" messages (which should then be generated automatically) and the
"unimplemented" markers (which should report that the rule is not yet
properly defined).

If you call C<Regexp::Grammars::set_error_translator()> in a void
context, the error translator is permanently replaced (at least,
until the next call to C<set_error_translator()>).

However, if you call C<Regexp::Grammars::set_error_translator()> in a
scalar or list context, it returns an object whose destructor will
restore the previous translator. This allows you to install a
translator only within a given scope, like so:

    {
        my $temporary
            = Regexp::Grammars::set_error_translator(\&my_translator);

        if ($text =~ $parser) {
            do_stuff_with( %/ );
        }
        else {
            report_errors_in( @! );
        }

    } # <--- error translator automagically reverts at this point


B<Warning>: any error translation subroutine you install will be
called during the grammar's parsing phase (i.e. as the grammar's regex
is matching). You should therefore ensure that your translator does
not itself use regular expressions, as nested evaluations of regexes
inside other regexes are extremely problematical (i.e. almost always
disastrous) in Perl.


=head2 Restricting how long a parse runs

Like the core Perl 5 regex engine on which they are built, the grammars
implemented by Regexp::Grammars are essentially top-down parsers. This
means that they may occasionally require an exponentially long time to
parse a particular input. This usually occurs if a particular grammar
includes a lot of recursion or nested backtracking, especially if the
grammar is then matched against a long string.

The judicious use of non-backtracking repetitions (i.e. C<x*+> and
C<x++>) can significantly improve parsing performance in many such
cases. Likewise, carefully reordering any high-level alternatives
(so as to test simple common cases first) can substantially reduce
parsing times.

However, some languages are just intrinsically slow to parse using
top-down techniques (or, at least, may have slow-to-parse corner cases).

To help cope with this constraint, Regexp::Grammars provides a mechanism
by which you can limit the total effort that a given grammar will expend
in attempting to match. The C<< <timeout:...> >> directive allows you
to specify how long a grammar is allowed to continue trying to match
before giving up. It expects a single argument, which must be an
unsigned integer, and it treats this integer as the number of seconds
to continue attempting to match.

For example:

    <timeout: 10>    # Give up after 10 seconds

indicates that the grammar should keep attempting to match for another
10 seconds from the point where the directive is encountered during a
parse. If the complete grammar has not matched in that time, the entire
match is considered to have failed, the matching process is immediately
terminated, and a standard error message
(C<'Internal error: Timed out after 10 seconds (as requested)'>)
is returned in C<@!>.

A C<< <timeout:...> >> directive can be placed anywhere in a grammar,
but is most usually placed at the very start, so that the entire grammar
is governed by the specified time limit. The second most common alternative
is to place the timeout at the start of a particular subrule that is known
to be potentially very slow.

A common mistake is to put the timeout specification at the top level
of the grammar, but place it I<after> the actual subrule to be matched,
like so:

    my $grammar = qr{

        <Text_Corpus>      # Subrule to be matched
        <timeout: 10>      # Useless use of timeout

        <rule: Text_Corpus>
            # et cetera...
    }xms;

Since the parser will only reach the C<< <timeout: 10> >> directive
I<after> it has completely matched C<< <Text_Corpus> >>, the timeout is
only initiated at the very end of the matching process and so does not
limit that process in any useful way.


=head3 Immediate timeouts

As you might expect, a C<< <timeout: 0> >> directive tells the parser to
keep trying for only zero more seconds, and therefore will immediately
cause the entire surrounding grammar to fail (no matter how deeply
within that grammar the directive is encountered).

This can occasionally be exteremely useful. If you know that detecting a
particular datum means that the grammar will never match, no matter how
many other alternatives may subsequently be tried, you can short-circuit
the parser by injecting a C<< <timeout: 0> >> immediately after the
offending datum is detected.

For example, if your grammar only accepts certain versions of the
language being parsed, you could write:

    <rule: Valid_Language_Version>
            vers = <%AcceptableVersions>
        |
            vers = <bad_version=(\S++)>
            <warning: (?{ "Cannot parse language version $MATCH{bad_version}" })>
            <timeout: 0>

In fact, this C<< <warning: MSG> <timeout: 0> >> sequence
is sufficiently useful, sufficiently complex, and sufficiently easy
to get wrong, that Regexp::Grammars provides a handy shortcut for it:
the C<< <fatal:...> >> directive. A C<< <fatal:...> >> is exactly
equivalent to a C<< <warning:...> >> followed by a zero-timeout,
so the previous example could also be written:

    <rule: Valid_Language_Version>
            vers = <%AcceptableVersions>
        |
            vers = <bad_version=(\S++)>
            <fatal: (?{ "Cannot parse language version $MATCH{bad_version}" })>

Like C<< <error:...> >> and C<< <warning:...> >>, C<< <fatal:...> >> also
provides its own failure context in C<$CONTEXT>, so the previous example
could be further simplified to:

    <rule: Valid_Language_Version>
            vers = <%AcceptableVersions>
        |
            vers = <fatal:(?{ "Cannot parse language version $CONTEXT" })>

Also like C<< <error:...> >>, C<< <fatal:...> >> can autogenerate an
error message if none is provided, so the example could be still further
reduced to:

    <rule: Valid_Language_Version>
            vers = <%AcceptableVersions>
        |
            vers = <fatal:>

In this last case, however, the error message returned in C<@!> would no
longer be:

    Cannot parse language version 0.95

It would now be:

    Expected valid language version, but found '0.95' instead


=head1 Scoping considerations

If you intend to use a grammar as part of a larger program that contains
other (non-grammatical) regexes, it is more efficient--and less
error-prone--to avoid having Regexp::Grammars process those regexes as
well. So it's often a good idea to declare your grammar in a C<do>
block, thereby restricting the scope of the module's effects.

For example:

    my $grammar = do {
        use Regexp::Grammars;
        qr{
            <file>

            <rule: file>
                <prelude>
                <data>
                <postlude>

            <rule: prelude>
                # etc.
        }x;
    };

Because the effects of Regexp::Grammars are lexically scoped, any regexes
defined outside that C<do> block will be unaffected by the module.



=head1 INTERFACE

=head2 Perl API

=over 4

=item C<use Regexp::Grammars;>

Causes all regexes in the current lexical scope to be compile-time processed
for grammar elements.

=item C<$str =~ $grammar>

=item C<$str =~ /$grammar/>

Attempt to match the grammar against the string, building a nested data
structure from it.

=item C<%/>

This hash is assigned the nested data structure created by any successful
match of a grammar regex.

=item C<@!>

This array is assigned the queue of error messages created by any
unsuccessful match attempt of a grammar regex.

=back


=head2 Grammar syntax

=head3 Directives

=over 4

=item C<< <rule: IDENTIFIER> >>

Define a rule whose name is specified by the supplied identifier.

Everything following the C<< <rule:...> >> directive
(up to the next C<< <rule:...> >> or C<< <token:...> >> directive) is
treated as part of the rule being defined.

Any whitespace in the rule is replaced by a call to the C<< <.ws> >>
subrule (which defaults to matching C<\s*>, but may be explicitly redefined).


=item C<< <token: IDENTIFIER> >>

Define a rule whose name is specified by the supplied identifier.

Everything following the C<< <token:...> >> directive (up to the next
C<< <rule:...> >> or C<< <token:...> >> directive) is treated as part
of the rule being defined.

Any whitespace in the rule is ignored (under the C</x> modifier), or
explicitly matched (if C</x> is not used).

=item C<< <objrule:  IDENTIFIER> >>

=item C<< <objtoken: IDENTIFIER> >>

Identical to a C<< <rule: IDENTIFIER> >> or C<< <token: IDENTIFIER> >>
declaration, except that the rule or token will also bless the hash it
normally returns, converting it to an object of a class whose name is
the same as the rule or token itself.


=item C<< <require: (?{ CODE }) > >>

The code block is executed and if its final value is true, matching continues
from the same position. If the block's final value is false, the match fails at
that point and starts backtracking.


=item C<< <error: (?{ CODE })  > >>

=item C<< <error: LITERAL TEXT > >>

=item C<< <error: > >>

This directive queues a I<conditional> error message within the global
special variable C<@!> and then fails to match at that point (that is,
it is equivalent to a C<(?!)> or C<(*FAIL)> when matching).

=item C<< <fatal: (?{ CODE })  > >>

=item C<< <fatal: LITERAL TEXT > >>

=item C<< <fatal: > >>

This directive is exactly the same as an C<< <error:...> >> in every
respect except that it immediately causes the entire surrounding
grammar to fail, and parsing to immediate cease.

=item C<< <warning: (?{ CODE })  > >>

=item C<< <warning: LITERAL TEXT > >>

This directive is exactly the same as an C<< <error:...> >> in every
respect except that it does not induce a failure to match at the point
it appears. That is, it is equivalent to a C<(?=)> ["succeed and
continue matching"], rather than a C<(?!)> ["fail and backtrack"].



=item C<< <debug: COMMAND > >>

During the matching of grammar regexes send debugging and warning
information to the specified log file (see C<< <logfile: LOGFILE> >>).

The available C<COMMAND>'s are:

    <debug: continue>    ___ Debug until end of complete parse
    <debug: run>         _/

    <debug: on>          ___ Debug until next subrule match
    <debug: match>       _/

    <debug: try>         ___ Debug until next subrule call or match
    <debug: step>        _/

    <debug: same>        ___ Maintain current debugging mode

    <debug: off>         ___ No debugging

See also the C<$DEBUG> special variable.


=item C<< <logfile: LOGFILE> >>

=item C<< <logfile:    -   > >>

During the compilation of grammar regexes, send debugging and warning
information to the specified LOGFILE (or to C<*STDERR> if C<-> is
specified).

If the specified LOGFILE name contains a C<%t>, it is replaced with a
(sortable) "YYYYMMDD.HHMMSS" timestamp. For example:

    <logfile: test-run-%t >

executed at around 9.30pm on the 21st of March 2009, would generate a
log file named: C<test-run-20090321.213056>


=item C<< <log: (?{ CODE })  > >>

=item C<< <log: LITERAL TEXT > >>

Append a message to the log file. If the argument is a code block,
that code is expected to return the text of the message; if the
argument is anything else, that something else I<is> the literal
message.

If the block returns two or more values, the first is treated as a log
message severity indicator, and the remaining values as separate lines
of text to be logged.

=item C<< <timeout: INT > >>

Restrict the match-time of the parse to the specified number of seconds.
Queues a error message and terminates the entire match process
if the parse does not complete within the nominated time limit.

=back


=head3 Subrule calls

=over 4

=item C<< <IDENTIFIER> >>

Call the subrule whose name is IDENTIFIER.

If it matches successfully, save the hash it returns in the current
scope's result-hash, under the key C<'IDENTIFIER'>.


=item C<< <IDENTIFIER_1=IDENTIFIER_2> >>

Call the subrule whose name is IDENTIFIER_1.

If it matches successfully, save the hash it returns in the current
scope's result-hash, under the key C<'IDENTIFIER_2'>.

In other words, the C<IDENTIFIER_1=> prefix changes the key under which the
result of calling a subrule is stored.


=item C<< <.IDENTIFIER> >>

Call the subrule whose name is IDENTIFIER.
Don't save the hash it returns.

In other words, the "dot" prefix disables saving of subrule results.


=item C<< <IDENTIFIER= ( PATTERN )> >>

Match the subpattern PATTERN.

If it matches successfully, capture the substring it matched and save
that substring in the current scope's result-hash, under the key
'IDENTIFIER'.


=item C<< <.IDENTIFIER= ( PATTERN )> >>

Match the subpattern PATTERN.
Don't save the substring it matched.


=item C<< <IDENTIFIER= %HASH> >>

Match a sequence of non-whitespace then verify that the sequence is a
key in the specified hash

If it matches successfully, capture the sequence it matched and save
that substring in the current scope's result-hash, under the key
'IDENTIFIER'.


=item C<< <%HASH> >>

Match a key from the hash.
Don't save the substring it matched.


=item C<< <IDENTIFIER= (?{ CODE })> >>

Execute the specified CODE.

Save the result (of the final expression that the CODE evaluates) in the
current scope's result-hash, under the key C<'IDENTIFIER'>.


=item C<< <[IDENTIFIER]> >>

Call the subrule whose name is IDENTIFIER.

If it matches successfully, append the hash it returns to a nested array
within the current scope's result-hash, under the key <'IDENTIFIER'>.


=item C<< <[IDENTIFIER_1=IDENTIFIER_2]> >>

Call the subrule whose name is IDENTIFIER_1.

If it matches successfully, append the hash it returns to a nested array
within the current scope's result-hash, under the key C<'IDENTIFIER_2'>.


=item C<< <ANY_SUBRULE>+ % <ANY_OTHER_SUBRULE> >>

=item C<< <ANY_SUBRULE>* % <ANY_OTHER_SUBRULE> >>

=item C<< <ANY_SUBRULE>+ % (PATTERN) >>

=item C<< <ANY_SUBRULE>* % (PATTERN) >>

Repeatedly call the first subrule.
Keep matching as long as the subrule matches, provided successive
matches are separated by matches of the second subrule or the pattern.

In other words, match a list of ANY_SUBRULE's separated by
ANY_OTHER_SUBRULE's or PATTERN's.

Note that, if a pattern is used to specify the separator, it must be
specified in some kind of matched parentheses. These may be capturing
[C<(...)>], non-capturing [C<(?:...)>], non-backtracking [C<< (?>...) >>],
or any other construct enclosed by an opening and closing paren.

=back

=head2 Special variables within grammar actions

=over 4

=item C<$CAPTURE>

=item C<$CONTEXT>

These are both aliases for the built-in read-only C<$^N> variable, which
always contains the substring matched by the nearest preceding C<(...)>
capture. C<$^N> still works perfectly well, but these are provided to
improve the readability of code blocks and error messages respectively.

=item C<$INDEX>

This variable contains the index at which the next match will be attempted
within the string being parsed. It is most commonly used in C<< <error:...> >>
or C<< <log:...> >> directives:

    <rule: ListElem>
        <log: (?{ "Trying words at index $INDEX" })>
        <MATCH=( \w++ )>
      |
        <log: (?{ "Trying digits at index $INDEX" })>
        <MATCH=( \d++ )>
      |
        <error: (?{ "Missing ListElem near index $INDEX" })>



=item C<%MATCH>

This variable contains all the saved results of any subrules called from the
current rule. In other words, subrule calls like:

    <ListElem>  <Separator= (,)>

stores their respective match results in C<$MATCH{'ListElem'}> and
C<$MATCH{'Separator'}>.


=item C<$MATCH>

This variable is an alias for C<$MATCH{"="}>. This is the C<%MATCH>
entry for the special "override value". If this entry is defined, its
value overrides the usual "return \%MATCH" semantics of a successful
rule.


=item C<%ARG>

This variable contains all the key/value pairs that were passed into
a particular subrule call.

    <Keyword>  <Command>  <Terminator(:Keyword)>

the C<Terminator> rule could get access to the text matched by
C<< <Keyword> >> like so:

    <token: Terminator>
        end_ (??{ $ARG{'Keyword'} })

Note that to match against the calling subrules 'Keyword' value, it's
necessary to use either a deferred interpolation (C<(??{...})>) or
a qualified matchref:

    <token: Terminator>
        end_ <\:Keyword>

A common mistake is to attempt to directly interpolate the argument:

    <token: Terminator>
        end_ $ARG{'Keyword'}

This evaluates C<$ARG{'Keyword'}> when the grammar is
compiled, rather than when the rule is matched.


=item C<$_>

At the start of any code blocks inside any regex, the variable C<$_> contains
the complete string being matched against. The current matching position
within that string is given by: C<pos($_)>.

=item C<$DEBUG>

This variable stores the current debugging mode (which may be any of:
C<'off'>, C<'on'>, C<'run'>, C<'continue'>, C<'match'>, C<'step'>, or
C<'try'>). It is set automatically by the C<< <debug:...> >> command, but may
also be set manually in a code block (which can be useful for conditional
debugging). For example:

    <rule: ListElem>
        <Identifier>

        # Conditionally debug if 'foobar' encountered...
        (?{ $DEBUG = $MATCH{Identifier} eq 'foobar' ? 'step' : 'off' })

        <Modifier>?

See also: the C<< <log: LOGFILE> >> and C<< <debug: DEBUG_CMD> >> directives.

=back


=head1 IMPORTANT CONSTRAINTS AND LIMITATIONS

=over 4

=item *

Prior to Perl 5.14, the Perl 5 regex engine as not reentrant. So any
attempt to perform a regex match inside a C<(?{ ... })> or C<(??{
... })> under Perl 5.12 or earlier will almost certainly lead to either
weird data corruption or a segfault.

The same calamities can also occur in any constructor called by
C<< <objrule:> >>. If the constructor invokes another regex in any
way, it will most likely fail catastrophically. In particular, this
means that Moose constructors will frequently crash and burn within
a Regex::Grammars grammar (for example, if the Moose-based class
declares an attribute type constraint such as 'Int', which Moose
checks using a regex).


=item *

The additional regex constructs this module provides are implemented by
rewriting regular expressions. This is a (safer) form of source
filtering, but still subject to all the same limitations and
fallibilities of any other macro-based solution.

=item *

In particular, rewriting the macros involves the insertion of (a lot of)
extra capturing parentheses. This means you can no longer assume that
particular capturing parens correspond to particular numeric variables:
i.e. to C<$1>, C<$2>, C<$3> etc. If you want to capture directly use
Perl 5.10's named capture construct:

    (?<name> [^\W\d]\w* )

Better still, capture the data in its correct hierarchical context
using the module's "named subpattern" construct:

    <name= ([^\W\d]\w*) >


=item *

No recursive descent parser--including those created with
Regexp::Grammars--can directly handle left-recursive grammars with rules
of the form:

    <rule: List>
        <List> , <ListElem>

If you find yourself attempting to write a left-recursive grammar (which
Perl 5.10 may or may not complain about, but will never successfully
parse with), then you probably need to use the "separated list"
construct instead:

    <rule: List>
        <[ListElem]>+ % (,)

=item *

Grammatical parsing with Regexp::Grammars can fail if your grammar
places "non-backtracking" directives (i.e. the C<< (?>...) >> block or
the C<?+>, C<*+>, or C<++> repetition specifiers) around a subrule call.
The problem appears to be that preventing the regex from backtracking
through the in-regex actions that Regexp::Grammars adds causes the
module's internal stack to fall out of sync with the regex match.

For the time being, you need to make sure that grammar rules don't appear
inside a "non-backtracking" directive.

=item *

Similarly, parsing with Regexp::Grammars will fail if your grammar
places a subrule call within a positive look-ahead, since
these don't play nicely with the data stack.

This seems to be an internal problem with perl itself.
Investigations, and attempts at a workaround, are proceeding.

For the time being, you need to make sure that grammar rules don't appear
inside a positive lookahead or use the
L<<< C<< <?RULENAME> >> construct | "Lookahead (zero-width) subrules" >>>
instead

=back

=head1 DIAGNOSTICS

Note that (because the author cannot find a way to throw exceptions from
within a regex) none of the following diagnostics actually throws an
exception.

Instead, these messages are simply written to the specified parser logfile
(or to C<*STDERR>, if no logfile is specified).

However, any fatal match-time message will immediately terminate the
parser matching and will still set C<$@> (as if an exception had been
thrown and caught at that point in the code). You then have the option
to check C<$@> immediately after matching with the grammar, and rethrow if
necessary:

    if ($input =~ $grammar) {
        process_data_in(\%/);
    }
    else {
        die if $@;
    }

=over

=item C<< Found call to %s, but no %s was defined in the grammar >>

You specified a call to a subrule for which there was no definition in
the grammar. Typically that's either because you forget to define the
rule, or because you misspelled either the definition or the subrule
call. For example:

    <file>

    <rule: fiel>            <---- misspelled rule
        <lines>             <---- used but never defined

Regexp::Grammars converts any such subrule call attempt to an instant
catastrophic failure of the entire parse, so if your parser ever
actually tries to perform that call, Very Bad Things will happen.


=item C<< Entire parse terminated prematurely while attempting to call non-existent rule: %s >>

You ignored the previous error and actually tried to call to a subrule
for which there was no definition in the grammar. Very Bad Things are
now happening. The parser got very upset, took its ball, and went home.
See the preceding diagnostic for remedies.

This diagnostic should throw an exception, but can't. So it sets C<$@>
instead, allowing you to trap the error manually if you wish.


=item C<< Fatal error: <objrule: %s> returned a non-hash-based object >>

An <objrule:> was specified and returned a blessed object that wasn't
a hash. This will break the behaviour of the grammar, so the module
immediately reports the problem and gives up.

The solution is to use only hash-based classes with <objrule:>


=item C<< Can't match against <grammar: %s> >>

The regex you attempted to match against defined a pure grammar, using
the C<< <grammar:...> >> directive. Pure grammars have no start-pattern
and hence cannot be matched against directly.

You need to define a matchable grammar that inherits from your pure
grammar and then calls one of its rules. For example, instead of:

    my $greeting = qr{
        <grammar: Greeting>

        <rule: greet>
            Hi there
            | Hello
            | Yo!
    }xms;

you need:

    qr{
        <grammar: Greeting>

        <rule: greet>
            Hi there
          | Hello
          | Yo!
    }xms;

    my $greeting = qr{
        <extends: Greeting>
        <greet>
    }xms;


=item C<< Inheritance from unknown grammar requested by <%s> >>

You used an C<< <extends:...> >> directive to request that your
grammar inherit from another, but the grammar you asked to
inherit from doesn't exist.

Check the spelling of the grammar name, and that it's already been
defined somewhere earlier in your program.


=item C<< Redeclaration of <%s> will be ignored >>

You defined two or more rules or tokens with the same name.
The first one defined in the grammar will be used;
the rest will be ignored.

To get rid of the warning, get rid of the extra definitions
(or, at least, comment them out or rename the rules).


=item C<< Possible invalid subrule call %s >>

Your grammar contained something of the form:

    <identifier
    <.identifier
    <[identifier

which you might have intended to be a subrule call, but which didn't
correctly parse as one. If it was supposed to be a Regexp::Grammars
subrule call, you need to check the syntax you used. If it wasn't
supposed to be a subrule call, you can silence the warning by rewriting
it and quoting the leading angle:

    \<identifier
    \<.identifier
    \<[identifier


=item C<< Possible failed attempt to specify a directive: %s >>

Your grammar contained something of the form:

    <identifier:...

but which wasn't a known directive like C<< <rule:...> >>
or C<< <debug:...> >>. If it was supposed to be a Regexp::Grammars
directive, check the spelling of the directive name. If it wasn't
supposed to be a directive, you can silence the warning by rewriting it
and quoting the leading angle:

    \<identifier:

=item C<< Possible failed attempt to specify a subrule call %s >>

Your grammar contained something of the form:

    <identifier...

but which wasn't a call to a known subrule like C<< <ident> >> or C<<
<name> >>. If it was supposed to be a Regexp::Grammars subrule call,
check the spelling of the rule name in the angles. If it wasn't supposed
to be a subrule call, you can silence the warning by rewriting it and
quoting the leading angle:

    \<identifier...


=item C<< Repeated subrule %s will only capture its final match >>

You specified a subrule call with a repetition qualifier, such as:

    <ListElem>*

or:

    <ListElem>+

Because each subrule call saves its result in a hash entry of the same name,
each repeated match will overwrite the previous ones, so only the last match
will ultimately be saved. If you want to save all the matches, you need to
tell Regexp::Grammars to save the sequence of results as a nested array within
the hash entry, like so:

    <[ListElem]>*

or:

    <[ListElem]>+

If you really did intend to throw away every result but the final one, you can
silence the warning by placing the subrule call inside any kind of
parentheses. For example:

    (<ListElem>)*

or:

    (?: <ListElem> )+


=item C<< Unable to open log file '$filename' (%s) >>

You specified a C<< <logfile:...> >> directive but the
file whose name you specified could not be opened for
writing (for the reason given in the parens).

Did you misspell the filename, or get the permissions wrong
somewhere in the filepath?


=item C<< Non-backtracking subrule %s may not revert correctly during backtracking >>

Because of inherent limitations in the Perl regex engine,
non-backtracking constructs like C<++>, C<*+>, C<?+>,
and C<< (?>...) >> do not always work correctly when applied to
subrule calls, especially in earlier versions of Perl.

If the grammar doesn't work properly, replace the offending constructs
with regular backtracking versions instead. If the grammar does work,
you can silence the warning by enclosing the subrule call in any
kind of parentheses. For example, change:

    <[ListElem]>++

to:

    (?: <[ListElem]> )++


=item C<< Unexpected item before first subrule specification in definition of <grammar: %s> >>

Named grammar definitions must consist only of rule and token definitions.
They cannot have patterns before the first definitions.
You had some kind of pattern before the first definition, which will be
completely ignored within the grammar.

To silence the warning, either comment out or delete whatever is before
the first rule/token definition.


=item C<< No main regex specified before rule definitions >>

You specified an unnamed grammar (i.e. no C<< <grammar:...> >> directive),
but didn't specify anything for it to actually match, just some rules
that you don't actually call. For example:

    my $grammar = qr{

        <rule: list>    \( <item> +% [,] \)

        <token: item>   <list> | \d+
    }x;

You have to provide something before the first rule to start the matching
off. For example:

    my $grammar = qr{

        <list>   # <--- This tells the grammar how to start matching

        <rule: list>    \( <item> +% [,] \)

        <token: item>   <list> | \d+
    }x;


=item C<< Ignoring useless empty <ws:> directive >>

The C<< <ws:...> >> directive specifies what whitespace matches within the
current rule. An empty C<< <ws:> >> directive would cause whitespace
to match nothing at all, which is what happens in a token definition,
not in a rule definition.

Either put some subpattern inside the empty C<< <ws:...> >> or, if you
really do want whitespace to match nothing at all, remove the directive
completely and change the rule definition to a token definition.


=item C<< Ignoring useless <ws: %s > directive in a token definition >>

The C<< <ws:...> >> directive is used to specify what whitespace matches
within a rule. Since whitespace never matches anything inside tokens,
putting a C<< <ws:...> >> directive in a token is a waste of time.

Either remove the useless directive, or else change the surrounding
token definition to a rule definition.

=item C<< Quantifier that doesn't quantify anything: <%s> >>

You specified a rule or token something like:

    <token: star>  *

or:

    <rule: add_op>  plus | add | +

but the C<*> and C<+> in those examples are both regex meta-operators:
quantifiers that usually cause what precedes them to match repeatedly.
In these cases however, nothing is preceding the quantifier, so it's a
Perl syntax error.

You almost certainly need to escape the meta-characters in some way.
For example:

    <token: star>  \*

    <rule: add_op>  plus | add | [+]

=back


=head1 CONFIGURATION AND ENVIRONMENT

Regexp::Grammars requires no configuration files or environment variables.


=head1 DEPENDENCIES

This module only works under Perl 5.10 or later.


=head1 INCOMPATIBILITIES

This module is likely to be incompatible with any other module that
automagically rewrites regexes. For example it may conflict with
Regexp::DefaultFlags, Regexp::DeferredExecution, or Regexp::Extended.


=head1 BUGS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-regexp-grammars@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Damian Conway  C<< <DCONWAY@CPAN.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2009, Damian Conway C<< <DCONWAY@CPAN.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


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
