#regexes for the lists that are referred to
#
#Note that the keys/categories in pointers and pointees match (acl, route_map etc)
#This is so we can linkify properly
#You must keep pointers/pointees categories in sync

#Named capture "unique_id" is the unique beginning of the pointed to thingy
#Named capture "pointed_at" is what to match with %pointers{$points_to} hash

'acl' => {
    1 => qr/(?<unique_id>
                                ^ \s*
                                ip \s+
                                access-list \s+
                                extended \s+
                                (?<pointed_at>
                                    (?: $valid_cisco_name)
                                )
                    )
                    /ixsm,
    2 => qr/(?<unique_id> 
                                ^ \s*
                                access-list \s+
                                (?<pointed_at>
                                    (?: $valid_cisco_name)
                                )
                    )/ixsm,
    },
'service_policy' => {
    1 => qr/ (?<unique_id> 
                                ^ \s* 
                                policy-map \s+ 
                                (?<pointed_at> 
                                    (?: $valid_cisco_name) 
                                ) 
                    )
                    /ixsm
    },
'route_map' => {
    1 => qr/ (?<unique_id> 
                                ^ \s*
                                route-map \s+ 
                                (?<pointed_at> 
                                    (?: $valid_cisco_name) 
                                ) 
                    )
                    /ixsm
    },
'prefix_list' => {
    1 =>
        qr/(?<unique_id> ^ \s* ip \s+ prefix-list \s+ (?<pointed_at> $valid_cisco_name) )/ixsm,

    },
'community_list' => { 1 =>
        qr/(?<unique_id> ^ \s* ip \s+ community-list \s+ (?:standard|extended) (?<pointed_at> $valid_cisco_name) )/ixsm,
    },
'as_path_access_list' => {
    1 =>
        qr/(?<unique_id> ^ \s* ip \s+ as-path \s+ access-list \s (?<pointed_at> $valid_cisco_name) )/ixsm,

    },
'interface' => {
    1 =>
        qr/(?<unique_id> ^ \s* interface \s+ (?<pointed_at> $valid_cisco_name) )/ixsm,

    },

'track' => {
    1 =>
        qr/(?<unique_id>^ \s* track \s+ (?<pointed_at> $valid_cisco_name))/ixsm,

    },

'vrf' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        ip \s+
                        vrf \s+
                        (?<pointed_at> $valid_cisco_name)
                    )
                    $
                    /ixsm,
    2 => qr/(?<unique_id>
                        ^ \s*
                        vrf \s+
                        definition \s+
                        (?<pointed_at> $valid_cisco_name)
                    )
                    $
                    /ixsm,

    },
'key_chain' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        key \s+ 
                        chain \s+
                        (?<pointed_at> $valid_cisco_name)
                    )
                    $
                    /ixsm,

    },
'ip_sla' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        ip \s+
                        sla \s+
                        (?<pointed_at> $valid_cisco_name)
                    )
                    $
                    /ixsm,
    },
'class' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        class-map \s+
                        (?: match-all | match-any) \s+
                        (?<pointed_at> $valid_cisco_name)
                    )
                    $
                    /ixsm,
    },
