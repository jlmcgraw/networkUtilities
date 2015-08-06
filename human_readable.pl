#Numbers we'd like to format to make more readable
#TODO: I'd like to stick a unit on there too, somehow
#Renders the config invalid, though
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

