    #regexes for commands that refer to other lists of some sort
    #
    #NOTE THAT THESE ARE DYNAMICALLY CONSTRUCTED FOR EACH FILE BASED ON THE
    #POINTEES WE FOUND IN IT (via $list_of_pointees_ref->{"acl"} for example)
    #
    #Note that the keys/categories in pointers and pointees match (acl, route_map etc)
    #This is so we can linkify properly
    #You must keep pointers/pointees categories in sync
    #
    #Each first level key/category is the type of item referenced in the command

    #Named capture "points_to" is what to match with %pointees{$pointed_at} hash

    'ip_address' => {
        1 => qr/^ \s+ 
                (?: permit | deny ) \s+ 
                .*? 
                host \s+ 
                (?<external_ipv4> $RE{net}{IPv4})
                /ixsm,
        2 => qr/^ \s+ 
                neighbor \s+ 
                (?<external_ipv4> $RE{net}{IPv4})
                /ixsm,
        3 => qr/\w+ \s+
                source-ip \s+ 
                (?<external_ipv4> $RE{net}{IPv4})
                /ixsm,
        4 => qr/^ \s*
                ip \s+
                route \s+
                (?: vrf \S+ \s+)?
                $RE{net}{IPv4} \s+
                $RE{net}{IPv4} \s+
                (?<external_ipv4> $RE{net}{IPv4})
                /ixsm,
        5 => qr/^ \s*
                ip \s+
                route \s+
                (?: vrf \S+ \s+)?
                $RE{net}{IPv4} \/ \d+
                (?<external_ipv4> $RE{net}{IPv4})
                /ixsm,
        6 => qr/^ \s*
                ip \s+
                default-gateway \s+
                (?<external_ipv4> $RE{net}{IPv4})
                /ixsm,
        7 => qr/^ \s*
                peer \s+
                ip \s+
                address \s+
                (?<external_ipv4> $RE{net}{IPv4})
                /ixsm,
        },
