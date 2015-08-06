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
                bandwidth \s+
                (\d+)
                $
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

