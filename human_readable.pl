#Numbers we'd like to format to make more readable (renders the config invalid, though)
#TODO: I'd like to stick a unit (bits, bytes) on there too, somehow

1 => qr/^ \s* 
        shape \s+ 
        average \s+
        (\d+) \s+ 
        (\d+) \s+ 
        (\d+)
        /ixsm,

    2 => qr/^ \s*
            (?:dsu \s+)?
            bandwidth \s+
            (\d+)
            /ixsm,

    3 => qr/^ \s* 
            police \s+
            cir \s+ 
            (\d+) \s+ 
            bc \s+ 
            (\d+) \s+ 
            be \s+ 
            (\d+)
            /ixsm,

    4 => qr/^ \s* 
            timeout \s+
            (\d+)
            $
            /ixsm,

    5 => qr/^ \s* 
            shape \s+
            average \s+
            (\d+)
            $
            /ixsm,

    6 => qr/^ \s* 
            police \s+
            (\d+) \s+
            (\d+) \s+
            /ixsm,

    7 => qr/^ \s* 
            shape \s+ 
            average \s+
            (\d+) \s+ 
            /ixsm,

    8 => qr/^ \s* 
            police \s+
            cir \s+ 
            (\d+) \s+ 
            kbps \s+
            bc \s+ 
            (\d+) \s+ 
            (?: bytes)?
            /ixsm,

    9 => qr/^ \s* 
            speed \s+
            (\d+)
            /ixsm,

    10 => qr/^ \s* 
            priority \s+
            (\d+) \s+
            (\d+) \s+
            /ixsm,

    11 => qr/
            metric \s+
            (\d+) \s+
            (\d+) \s+
            (\d+) \s+
            (\d+) \s+
            (\d+)
            /ixsm, 12 => qr/^ \s*
            timeout \s+
            (\d+)
            \s*  $
            /ixsm,

    13 => qr/^ \s*
            set \s+
            timeout \s+
            inactivity \s+
            (\d+)
            \s*  $
            /ixsm,
