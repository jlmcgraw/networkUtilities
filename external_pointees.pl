    #regexes for the lists that are referred to
    #
    #Note that the keys/categories in pointers and pointees match (acl, route_map etc)
    #This is so we can linkify properly
    #You must keep pointers/pointees categories in sync
    #
    #Each first level key/category is the type of item its regexes match
    #
    #Named capture "unique_id" is the unique beginning of the pointed to thingy
    #Named capture "pointed_at" is what to match with %pointers{$points_to} hash

    'ip_address' => {
        1 => qr/(?<unique_id> ^ \s* 
                            ip \s+
                            address \s+
                            (?<pointed_at>
                                $RE{net}{IPv4} \s+
                                $RE{net}{IPv4})
                            (?: \s+ secondary)?
                            (\s+|$)
                            )/ixsm,
        2 => qr/(?<unique_id> ^ \s* 
                            ipv6 \s+
                            address \s+
                            (?<pointed_at>
                                $RE{net}{IPv6} \s+)
                            (?: \s+ secondary)?
                            (\s+|$)
                            )/ixsm,

        #NXOS: ip address 10.240.6.33/29
        3 => qr/(?<unique_id> ^ \s* 
                            ip \s+
                            address \s+
                            (?<pointed_at>
                                $RE{net}{IPv4}
                                \/ \d+)
                            (\s+|$)
                            )/ixsm,

        #RIOS: interface inpath0_0 ip address 10.74.2.107 /29
        #Note the space between address and mask, which we remove elsewhere
        4 => qr/(?<unique_id> ^ \s*
                            interface \s+
                            $valid_cisco_name \s+
                            ip \s+
                            address \s+
                            (?<pointed_at>
                                $RE{net}{IPv4}
                                \s \/ \d+)
                            (\s+|$)
                            )/ixsm,

        #NXOS HSRP
        5 => qr/(?<unique_id> ^ \s*
                    ip \s+
                    (?<pointed_at>
                        $RE{net}{IPv4}
                        )
                    \s*
                    $
                    )/ixsm,

        #IOS HSRP
        6 => qr/(?<unique_id> ^ \s*
                    standby \s+
                    \d+ \s+
                    ip \s+
                    (?<pointed_at>
                        $RE{net}{IPv4}
                        )
                    \s*
                    $
                    )/ixsm,
        },
        'hostname' => {
        1 => qr/(?<unique_id> ^ \s* 
                            hostname \s+
                            (?<pointed_at>
                                $valid_cisco_name
                                )
                            (\s+|$)
                            )/ixsm,
        },

