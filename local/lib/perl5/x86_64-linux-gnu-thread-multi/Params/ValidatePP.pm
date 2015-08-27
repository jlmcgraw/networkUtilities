package    # hide from PAUSE
    Params::Validate;

our $VERSION = '1.21';

BEGIN { $ENV{PARAMS_VALIDATE_IMPLEMENTATION} = 'PP' }
use Params::Validate;

1;
