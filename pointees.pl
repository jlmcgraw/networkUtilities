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

'acl' => {
    1 => qr/(?<unique_id>
                                ^ \s*
                                ip \s+
                                access-list \s+
                                (?: extended \s+)?
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

    #NXOS
    3 => qr/(?<unique_id>
                ^ \s*
                mac \s+
                access-list \s+
                (?<pointed_at>
                    (?: $valid_cisco_name)
                )
    )
    /ixsm,
    4 => qr/(?<unique_id>
                ^ \s*
                ipv6 \s+
                access-list \s+
                (?<pointed_at>
                    (?: $valid_cisco_name)
                )
    )
    /ixsm,
    },

'service_policy' => {
    1 => qr/ (?<unique_id> 
                                ^ \s* 
                                policy-map \s+ 
                                (?<pointed_at> 
                                    (?: $valid_cisco_name) 
                                ) 
                    )
                    \s* $
                    /ixsm,

    #NXOS
    2 => qr/ (?<unique_id> 
                                ^ \s* 
                                policy-map \s+
                                type \s+
                                (?: queuing | qos) \s+
                                (?<pointed_at> 
                                    (?: $valid_cisco_name) 
                                ) 
                    )
                    \s* $
                    /ixsm,
    },

'route_map' => {
    1 => qr/ (?<unique_id> 
                                ^ \s*
                                route-map \s+ 
                                (?<pointed_at> 
                                    (?: $valid_cisco_name) 
                                )
                                (?: deny | permit) \s+
                                \d+
                                \s* 
                                $
                    )
                    /ixsm,

    #NXOS
    2 => qr/ (?<unique_id> 
                                ^ \s*
                                route-map \s+
                                (?<pointed_at> 
                                    (?: $valid_cisco_name) 
                                )
                                )
                                \s+
                                (?: permit | deny) \s+
                    /ixsm,
    },
    
'prefix_list' => {
    1 =>
        qr/(?<unique_id> ^ \s* ip \s+ prefix-list \s+ (?<pointed_at> $valid_cisco_name) )/ixsm,

    },
    
'community_list' => { 
    1 =>
        qr/(?<unique_id> ^ \s* ip \s+ community-list \s+ (?:standard|extended) \s+ (?<pointed_at> $valid_cisco_name) )/ixsm,
    2 =>
        qr/(?<unique_id> ^ \s*
                        ip \s+ 
                        extcommunity-list \s+ 
                        (?:standard|extended) \s+
                        (?<pointed_at> $valid_cisco_name) )/ixsm,
    },
    
'as_path_access_list' => {
    1 => qr/(?<unique_id> ^ \s*
                        ip \s+
                        as-path \s+ 
                        access-list \s 
                        (?<pointed_at> $valid_cisco_name) )/ixsm,

    },

'interface' => {
        #NXOS,
    1 => qr/(?<unique_id> ^ \s* 
                            interface \s+ 
                            port-channel
                            (?<pointed_at> $valid_cisco_name) 
            )/ixsm,
   
    2 =>
        qr/(?<unique_id> ^ \s* 
                            interface \s+ 
                            (?<pointed_at> $valid_cisco_name) 
            )/ixsm,
    },

'track' => {
    1 => qr/(?<unique_id>^ \s*
                         track \s+
                        (?<pointed_at> $valid_cisco_name )
            )/ixsm,

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

    #NXOS
    3 => qr/(?<unique_id>
                        ^ \s*
                        vrf \s+
                        context \s+
                        (?<pointed_at> $valid_cisco_name)
                    )
                    ( \s* | $)
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

    #NXOS
    2 => qr/(?<unique_id> 
                    ^ \s*
                    class-map \s+
                    type \s+
                    (?: control-plane | qos) \s+
                    (?: match-any | match-all) \s+
                    (?<pointed_at> $valid_cisco_name) )
                    /ixsm,

    #NXOS
    3 => qr/(?<unique_id> 
                    ^ \s*
                    class-map \s+
                    type \s+
                    (?: network-qos | queuing ) \s+
                    (?<pointed_at> $valid_cisco_name) )
                    /ixsm,

    },
    'aaa_group' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        aaa \s+
                        group \s+
                        server \s+
                        (?: tacacs\+ ) \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            (\s+|$)
            /ixsm,
    },
    'routing_process' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        router \s+
                        (?<pointed_at> (?:ospf | eigrp | bgp | isis | rip) \s+ $valid_cisco_name)
            )
            (\s+|$)
            /ixsm,
    },
    'object_group' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        object-group \s+
                        (?: network | service | protocol | icmp-type )\s+
                        (?<pointed_at> $valid_cisco_name)
            )
            (\s+|$)
            /ixsm,
    },
    'snmp_view' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        snmp-server \s+
                        view \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            (\s+|$)
            /ixsm,
    },
     'template_peer_policy' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        template \s+
                        peer-policy \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            (\s+|$)
            /ixsm,
    }, 
     'template_peer_session' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        template \s+
                        peer-session \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            (\s+|$)
            /ixsm,
    }, 