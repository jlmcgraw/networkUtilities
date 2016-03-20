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

#Any key with _list in it will be treated as a space separated list
#otherwise identifiers can have spaces in them (eg 'track 1', 'ospf 10')

'acl' => {
    1 =>
        qr /^ \s* match \s+ access-group \s+ name \s+ (?<points_to> $list_of_pointees_ref->{"acl"})/ixsm,
    2 =>
        qr /^ \s* snmp-server \s+ community \s+ (?: $valid_cisco_name) \s+ view \s+ (?: $valid_cisco_name) \s+ (?: RO|RW) \s+ (?<points_to> $list_of_pointees_ref->{"acl"})/ixsm,
    3 =>
        qr /^ \s* snmp-server \s+ community \s+ (?: $valid_cisco_name) \s+ (?: RO|RW) \s+ (?<points_to> $list_of_pointees_ref->{"acl"})/ixsm,
    4 =>
        qr /^ \s* snmp-server \s+ file-transfer \s+ access-group \s+ (?<points_to> $list_of_pointees_ref->{"acl"}) \s+ protocol/ixsm,
    5 =>
        qr /^ \s* access-class \s+ (?<points_to> $list_of_pointees_ref->{"acl"}) \s+ (?: in|out)/ixsm,
    6 =>
        qr /^ \s* snmp-server \s+ tftp-server-list \s+ (?<points_to> $list_of_pointees_ref->{"acl"})/ixsm,
    7 =>
        qr /^ \s* ip \s+ directed-broadcast \s+ (?<points_to> $list_of_pointees_ref->{"acl"}) $/ixsm,
    8 =>
        qr /^ \s* ntp \s+ access-group \s+ (?: peer | serve | serve-only | query-only) (?<points_to> $list_of_pointees_ref->{"acl"}) $/ixsm,
    9 => qr /^ \s*
                match (?: \s+ not )? \s+
                access-group \s+
                name \s+
                (?<points_to> $list_of_pointees_ref->{"acl"})
                $
                /ixsm,

    #nxos
    10 => qr /^ \s*
                snmp-server \s+
                community \s+
                $valid_cisco_name \s+
                use-acl \s+
                (?<points_to> $list_of_pointees_ref->{"acl"})
                $
                /ixsm,

    #IOS: ip access-group
    11 => qr /^ \s*
                ip \s+
                access-group  \s+
                (?<points_to> $list_of_pointees_ref->{"acl"})
                (?: \s+ in|out)?
                (?: \s+ | $)
                /ixsm,
    #BUG TODO Make ACL a list since BGP can match multiple ACLs
    12 => qr /^ \s*
                match \s+
                ip \s+
                address \s+
                (?<points_to> $list_of_pointees_ref->{"acl"})
                (?: \s+ | $)
                /ixsm,
    13 => qr /^ \s*
                match (?: \s+ not )? \s+
                access-group \s+
                (?<points_to> $list_of_pointees_ref->{"acl"})
                $
                /ixsm,
    14 => qr /^ \s*
                ip \s+
                nat \s+
                (?: (inside | outside) \s+)?
                source \s+
                list \s+
                (?<points_to> $list_of_pointees_ref->{"acl"})
                (\s*|$)
                /ixsm,
    15 => qr /^ \s*
                access-group \s+
                (?: input | output) \s+
                (?<points_to> $list_of_pointees_ref->{"acl"})
                $
                /ixsm,
    16 => qr /^ \s*
                access-group \s+
                (?<points_to> $list_of_pointees_ref->{"acl"})  \s+
                (?: in | out ) \s+
                /ixsm,
    17 => qr /^ \s*
                crypto \s+
                .*?
                address \s+
                (?<points_to> $list_of_pointees_ref->{"acl"})
                /ixsm,
    18 => qr /^ \s*
            match \s+
            address \s+
            (?<points_to> $list_of_pointees_ref->{"acl"})
            /ixsm,
    19 => qr /^ \s*
            distribute-list \s+
            (?<points_to> $list_of_pointees_ref->{"acl"})
            /ixsm,
    20 => qr /^ \s*                                           #ACE
            \d+ \s+
            match \s+
            access-list \s+
            (?<points_to> $list_of_pointees_ref->{"acl"})
            /ixsm,
    },

    'policy_map' => {
    1 => qr/^ \s*
            service-policy \s+
            (?: input|output) \s+
            (?<points_to> $list_of_pointees_ref->{"policy_map"})
            /ixsm,
    2 =>
        qr/^ \s* service-policy \s+ (?<points_to> $list_of_pointees_ref->{"policy_map"})$/ixsm,

    #NXOS
    3 => qr/^ \s*
            service-policy \s+
            type \s+
            (?: queuing | qos  | network-qos ) \s+
            (?: (?:input | output) \s+ )?
            (?<points_to> $list_of_pointees_ref->{"policy_map"})
            $
            /ixsm,
    4 => qr/^ \s*
            loadbalance \s+
            policy \s+
            (?<points_to> $list_of_pointees_ref->{"policy_map"})
            $
            /ixsm,
    },

    'route_map' => {
    1 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ route-map \s+ (?<points_to> $list_of_pointees_ref->{"route_map"})/ixsm,
    2 => qr/^ \s*
            redistribute \s+
            (?:static|bgp|ospf|eigrp|isis|rip)
            (?: \s+ \d+ \s+)?
            (?: subnets \s+)?
            route-map \s+
            (?<points_to> $list_of_pointees_ref->{"route_map"})
            /ixsm,
    3 => qr/^ \s*
            redistribute \s+
            (?:static|bgp|ospf|eigrp|isis|rip)
            (?: .*?)
            route-map \s+
            (?<points_to> $list_of_pointees_ref->{"route_map"})
            /ixsm,

    #NXOS
    4 => qr/^ \s*
            route-map \s+
            (?<points_to> $list_of_pointees_ref->{"route_map"} )
            \s+
            (?: in | out)
            \s* $
            /ixsm,

    #NXOS
    5 => qr/^ \s*
            network \s+
            $RE{net}{IPv4} \/ \d+ \s+
            route-map \s+
            (?<points_to> $list_of_pointees_ref->{"route_map"} )
            /ixsm,

    #IOS
    6 => qr/^ \s*
            network \s+
            (?: $RE{net}{IPv4} | SCRUBBED ) \s+
            mask \s+
            $RE{net}{IPv4} \s+
            route-map \s+
            (?<points_to> $list_of_pointees_ref->{"route_map"} )
            /ixsm,
    7 => qr/^ \s*
            ip \s+
            policy \s+
            route-map \s+
            (?<points_to> $list_of_pointees_ref->{"route_map"} )
            /ixsm,

    8 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ default-originate \s+ route-map \s+ (?<points_to> $list_of_pointees_ref->{"route_map"})/ixsm,

    9 => qr/^ \s*
            import \s+
            ipv4 \s+
            unicast \s+
            map \s+
            (?<points_to> $list_of_pointees_ref->{"route_map"})/ixsm,
    10 => qr/\s+
            advertise-map \s+
            (?<points_to> $list_of_pointees_ref->{"route_map"})/ixsm,
    11 => qr/^ \s*
            distribute-list \s+
            route-map \s+
            (?<points_to> $list_of_pointees_ref->{"route_map"})/ixsm,
    },

    'prefix_list' => {
    1 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ prefix-list \s+ (?<points_to> $list_of_pointees_ref->{"prefix_list"}) \s+ (?:in|out)$/ixsm,
    '2_list' => qr/^ \s*
            match \s+
            ip \s+
            address \s+
            prefix-list \s+
            (?<points_to> (?: $list_of_pointees_ref->{"prefix_list"} | \s )+ )           #This can be a list of things
                                                                                         #separated by whitespace
           /ixsm,
    '3_list' => qr/^ \s*
            distribute-list \s+
            prefix \s+
            (?<points_to> (?: $list_of_pointees_ref->{"prefix_list"} | \s )+ )           #This can be a list of things
                                                                                         #separated by whitespace
           /ixsm,
    },
    'community_list' => {
    1 => qr/^ \s*
            match \s+
            extcommunity \s+
            (?<points_to> $list_of_pointees_ref->{"community_list"})
            \s* $
            /ixsm,
    2 => qr/^ \s*
            match \s+
            community \s+
            (?<points_to> $list_of_pointees_ref->{"community_list"})
            \s* $
            /ixsm,
    },
    'as_path_access_list' => {
    1 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ filter-list \s+ (?<points_to> $list_of_pointees_ref->{"as_path_access_list"}) \s+ (?:in|out)$/ixsm,

    '2_list' => qr/^ \s*
            match \s+
            as-path \s+
            (?<points_to> (?: $list_of_pointees_ref->{"as_path_access_list"} | \s )+ )                #This can be a list of things
                                                                                         #separated by whitespace
            \s* $/ixsm,

    },
    'interface' => {

    #     1 =>
    #         qr/source-interface \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) /ixsm,
    #     2 =>
    #         qr/ntp \s+ source \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) /ixsm,
    #     3 =>
    #         qr/^ \s* no \s+ passive-interface \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) /ixsm,
    3 =>
        qr/^ \s* (?:no \s+)? passive-interface \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) /ixsm,

    #     4 =>
    #         qr/snmp-server \s+ trap-source \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) /ixsm,
    #     5 =>
    #         qr/^ \s* ip \s+ flow-export \s+ source \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) /ixsm,
    #     6 =>
    #         qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ update-source \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) $/ixsm,
    #     7 =>
    #         qr/^ \s* update-source \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) $/ixsm,
    #     8 => qr/^ \s*
    #                 (?: source | destination ) \s+
    #                 interface \s+
    #                 (?<points_to> $list_of_pointees_ref->{"interface"})
    #                 /ixsm,
    #BUG This points to a number, not the proper "Port-Channel#" name of the interface
    9 => qr/^ \s*
                    channel-group \s+
                    (?<points_to> $list_of_pointees_ref->{"interface"})
                    /ixsm,

    #Should I do these meta ones that match so much? Or use the more specific ones above
    10 => qr/[\S]+
            \s+
            (?:source|interface) \s+
            (?<points_to> $list_of_pointees_ref->{"interface"})
            /ixsm,

    11 => qr/[\S]+
            (?:source|interface) \s+
            (?<points_to> $list_of_pointees_ref->{"interface"})
            /ixsm,
    12 => qr/\s+
            (?: in | out ) \s+
            (?<points_to> $list_of_pointees_ref->{"interface"})
            /ixsm,
    13 => qr/^ \s*
            tunnel \s+
            source \s+
            (?<points_to> $list_of_pointees_ref->{"interface"})
            /ixsm,
    14 => qr/^ \s*                                                  #ACE
            ft-interface \s+
            vlan \s+
            (?<points_to> $list_of_pointees_ref->{"interface"})
            /ixsm,
    15 => qr/^ \s*                                                  #ACE
            allocate-interface \s+
            vlan \s+
            (?<points_to> $list_of_pointees_ref->{"interface"})
            /ixsm,

    #     #BUG TODO Testing working with "points_to" that has spaces in it
    #     #Remove the (?-x:.....) modifier
    #
    #     11 => qr/[\S]+
    #             (?:source|interface) \s+
    #             (?<points_to> (?-x:$list_of_pointees_ref->{"interface"}))
    #             /ixsm,
    },
    'track' => {
    1 => qr/    \s+
                (?<points_to> $list_of_pointees_ref->{"track"} )
        /isxm,

    },
    'vrf' => {
    1 => qr/^ \s*
                    ip \s+
                    vrf \s+
                    (?: forwarding | receive) \s+
                    (?<points_to> (?: $list_of_pointees_ref->{"vrf"}) )
                    (\s+|$)
        /ixsm,

    2 => qr/^ \s*
                    vrf \s+
                    forwarding \s+
                    (?<points_to> (?: $list_of_pointees_ref->{"vrf"}) )
                    (\s+|$)
        /ixsm,

    3 => qr/^ \s*
                    ip \s+
                    route \s+
                    vrf \s+
                    (?<points_to> (?: $list_of_pointees_ref->{"vrf"}) )
                    (\s+|$)
        /ixsm,

    #NXOS
    4 => qr/        \s+
                    use-vrf \s+
                    (?<points_to> (?: $list_of_pointees_ref->{"vrf"}) )
                    (\s+|$)
        /ixsm,
    5 => qr/        \s+
                    address-family \s+
                    (?:ipv4 | ipv6 | CLNS | VPNv4 | L2VPN ) \s+
                    vrf \s+
                    (?<points_to> (?: $list_of_pointees_ref->{"vrf"}) )
                    (\s+|$)
        /ixsm,

    #Match any mention of "vrf" except for the definition of one
    6 => qr/(?<!^ ip)
                \s+
                vrf \s+
                (?<points_to> (?: $list_of_pointees_ref->{"vrf"}) )
                (\s+|$)
        /ixsm,
    },
    'key_chain' => {

    #Make this guy have to have some alphanumeric in front of him
    1 => qr/ \w+ \s+
        key-chain \s+
        (?<points_to> (?: $list_of_pointees_ref->{"key_chain"}) )
        (\s+|$)
        /ixsm,
    },
    'ip_sla' => {
    1 => qr/ ^ \s*
        ip \s+
        sla \s+
        schedule \s+
        (?<points_to> (?: $list_of_pointees_ref->{"ip_sla"}) )
        /ixsm,

    #     2 => qr/ ip \s+
    #         sla \s+
    #         (?<points_to> (?: $list_of_pointees_ref->{"ip_sla"}) )
    #         /ixsm,
    },
    'class' => {

    #NXOS
    1 => qr/ ^ \s*
        class \s+
        (?<points_to> (?: $list_of_pointees_ref->{"class"}))
        (\s*|$)
        /ixsm,

    #NXOS
    2 => qr/ ^ \s*
        class \s+
        type \s+
        (?: queuing | network-qos ) \s+
        (?<points_to> (?: $list_of_pointees_ref->{"class"}) )
        (\s*|$)
        /ixsm,

    #ASA
    3 => qr/ ^ \s*
        match \s+
        class-map \s+
        (?<points_to> (?: $list_of_pointees_ref->{"class"}) )
        (\s*|$)
        /ixsm,

    #ASA
    4 => qr/ ^ \s*
        class \s+
        type \s+
        (?: inspect ) \s+
        (?: $valid_cisco_name \s+ )?
        (?<points_to> (?: $list_of_pointees_ref->{"class"}) )
        (\s*|$)
        /ixsm,

    },
    'aaa_group' => {
    1 => qr/ ^ \s*
        aaa \s+
        (?: authentication | authorization | accounting ) \s+
        .*?
        group \s+
        (?<points_to> (?: $list_of_pointees_ref->{"aaa_group"}) )
        /ixsm,

    },
    'routing_process' => {

    #     1 => qr/^ \s*
    #             router \s+
    #             (?<points_to> (?: $list_of_pointees_ref->{"routing_process"}) )
    #             /ixsm,
    2 => qr/^ \s*
            ip \s+
            router \s+
            (?<points_to> (?: $list_of_pointees_ref->{"routing_process"}) )
            /ixsm,
    3 => qr/^ \s*
            ip \s+
            summary-address \s+
            (?<points_to> (?: $list_of_pointees_ref->{"routing_process"}) )
            /ixsm,
    4 => qr/^ \s*
            redistribute \s+
            (?<points_to> (?: $list_of_pointees_ref->{"routing_process"}) )
            /ixsm,
    5 => qr/^ \s*
            ip \s+
            hello-interval \s+
            (?<points_to> (?: $list_of_pointees_ref->{"routing_process"}) )
            /ixsm,
    5 => qr/^ \s*
            ip \s+
            hold-time \s+
            (?<points_to> (?: $list_of_pointees_ref->{"routing_process"}) )
            /ixsm,                
    },
    'object_group' => {

    #BUG TODO: Catch both
    #access-list outside_access_in extended permit tcp object-group Support_Network any object-group Support_Ports
    1 =>
        qr/ \S+ \s*             #Make this guy have to have some alphanumeric in front of him
        object-group \s+
        (?<points_to> (?: $list_of_pointees_ref->{"object_group"}) )
        /ixsm,

    },
    'snmp_view' => {
    1 => qr/ ^ \s*
        snmp-server \s+
        community \s+
        $valid_cisco_name \s+
        view \s+
        (?<points_to> (?: $list_of_pointees_ref->{"snmp_view"}) )
        /ixsm,

    },
    'template_peer_policy' => {
    1 => qr/
        inherit \s+
        peer-policy \s+
        (?<points_to> (?: $list_of_pointees_ref->{"template_peer_policy"}) )
        /ixsm,

    },
    'template_peer_session' => {
    1 => qr/
        inherit \s+
        peer-session \s+
        (?<points_to> (?: $list_of_pointees_ref->{"template_peer_session"}) )
        /ixsm,

    },
    'parameter_map' => {
    1 => qr/^ \s*
        match \s+
        (?: url-keyword | server-domain ) \s+
        urlf-glob \s+
        (?<points_to> (?: $list_of_pointees_ref->{"parameter_map"}) )
        /ixsm,
    2 => qr/^ \s*
        match \s+
        protocol \s+
        (?: ymsgr | msnmsgr | aol ) \s+
        (?<points_to> (?: $list_of_pointees_ref->{"parameter_map"}  ))
        /ixsm,
    },
    'crypto_pki' => {
    1 => qr/^ \s*
                        crypto \s+
                        pki \s+
                        trustpoint \s+
        (?<points_to> (?: $list_of_pointees_ref->{"crypto_pki"}) )
        /ixsm,
    },
    'dhcp_pool' => {
    1 => qr/^ \s*
                        crypto \s+
                        pki \s+
                        trustpoint \s+
        (?<points_to> (?: $list_of_pointees_ref->{"dhcp_pool"}) )
        /ixsm,
    },
    'ip_inspect' => {
    1 => qr/^ \s*
                        ip \s+
                        inspect \s+
                        (?<points_to> (?: $list_of_pointees_ref->{"ip_inspect"}) ) \s+
                        (?: in | out)
        /ixsm,
    },
    'pix_nameif' => {

    #BUG is matching lines with whitespace when run against non-pix config
    #BUG if some other group name matches an interface name
    #   Incomplete workaround by making interface name case-sensitive (?-i)
    1 => qr/            [\S]+
                        (?<!nameif)
                        (?: \s+ )
                        (?<points_to> (?-i: $list_of_pointees_ref->{"pix_nameif"}) )
                        (?: \s+ | $ )
        /ixsm,
    },
    'ace_context' => {
    1 => qr/
            ^ \s*
            associate-context \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_context"}) )
            \s* $
            /ixsm,
    },
    'ace_resource_class' => {
    1 => qr/
            ^ \s*
            member \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_resource_class"}) )
            \s* $
            /ixsm,
    },
    'ace_probe' => {
    1 => qr/
            ^ \s*
            probe \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_probe"}) )
            \s* $
            /ixsm,
    },
    'ace_rserver' => {
    1 => qr/
            ^ \s*
            rserver \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_rserver"}) )
            (?: \s* (?:\d+))?
            \s* $
            /ixsm,
    2 => qr/
            \" \s+
            rserver \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_rserver"}) )
            (?:\s \d+)?
            \s* $
            /ixsm,
    },
    'ace_serverfarm' => {
    1 => qr/
            ^ \s*
            serverfarm \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_serverfarm"}) )
            \s*
            /ixsm,
    2 => qr/
            \s+
            backup \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_serverfarm"}) )
            \s* $
            /ixsm,
    },
    'ace_crypto_chaingroup' => {
    1 => qr/
            ^ \s*
            chaingroup \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_crypto_chaingroup"}) )
            \s* $
            /ixsm,
    },
    'ace_ssl_proxy' => {
    1 => qr/
            ^ \s*
            ssl-proxy \s+
            (?:server|client) \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_ssl_proxy"}) )
            \s* $
            /ixsm,
    },
    'ace_parameter_map' => {
    1 => qr/
            ^ \s*
            (?:ssl|connection) \s+
            advanced-options \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_parameter_map"}) )
            \s* $
            /ixsm,
    2 => qr/
            ^ \s*
            appl-parameter \s+
            (?:dns|generic|http|rtsp|sip|skinny) \s+
            advanced-options \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_parameter_map"}) )
            \s* $
            /ixsm,
    },
    'ace_sticky' => {
    1 => qr/
            ^ \s*
            sticky-serverfarm \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_sticky"}) )
            \s* $
            /ixsm,
    },

    #   'ace_access_list' => {
    #     1 => qr/
    #             ^ \s*
    #             \d+ \s+
    #             match \s+
    #             access-list \s+
    #             (?<points_to> (?: $list_of_pointees_ref->{"ace_access_list"}) )
    #             \s* $
    #             /ixsm,
    #   },
    'ace_ft_peer' => {
    1 => qr/
            ^ \s*            
            peer \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_ft_peer"}) )
            \s* $
            /ixsm,
    },
    'ace_action_list' => {
    1 => qr/
            ^ \s*            
            action \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ace_action_list"}) )
            /ixsm,
    },
    'nxos_zoneset' => {
    1 => qr/
            ^ \s*
            zoneset \s+
            activate \s+
            name \s+
            (?<points_to> (?: $list_of_pointees_ref->{"nxos_zoneset"}) )
            /ixsm,
    },
    'nxos_zoneset_member' => {
    1 => qr/
            ^ \s*
            member \s+
            (?<points_to> (?: $list_of_pointees_ref->{"nxos_zoneset_member"}) )
            \s* $
            /ixsm,
    },
    'nxos_role' => {
    1 => qr/
            ^ \s*
            username \s+
            .*?
            role \s+
            (?<points_to> (?: $list_of_pointees_ref->{"nxos_role"}) )
            /ixsm,
    },
    'ipsec_profile' => {
    1 => qr/^ \s*
            tunnel \s+
            protection \s+
            ipsec \s+
            profile \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ipsec_profile"}) )
            /ixsm,
    },
    'ipsec_transform_set' => {
    1 => qr/^ \s*
            set \s+
            transform-set \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ipsec_transform_set"}) )
            /ixsm,
    },
    'crypto_map' => {
    1 => qr/^ \s*
                        crypto \s+
                        map \s+
        (?<points_to> (?: $list_of_pointees_ref->{"crypto_map"}) )
        $
        /ixsm,
    },
    'aaa_list' => {
    1 => qr/ ^ \s*
        authorization \s+
        (?: auth-proxy | network | exec | (?: commands \s+ \d+) | reverse-access | configuration | ipmobile) \s+
        (?<points_to> (?: $list_of_pointees_ref->{"aaa_list"}) )
        /ixsm,
    2 => qr/ ^ \s*
        login \s+
        authentication \s+
        (?<points_to> (?: $list_of_pointees_ref->{"aaa_list"}) )
        /ixsm,

    },
    'voice_translation_profile' => {
    1 => qr/ ^ \s*
            translation-profile \s+
            (?: outgoing | incoming) \s+
            (?<points_to> (?: $list_of_pointees_ref->{"voice_translation_profile"}) )
            /ixsm,
    },
    'voice_translation_rule' => {
    1 => qr/ ^ \s*
            translate \s+
            (?: calling | called) \s+
            (?<points_to> (?: $list_of_pointees_ref->{"voice_translation_rule"}) )
            /ixsm,
    },
    'voice_class_sip_profiles' => {
    1 => qr/ ^ \s*
            sip-profiles \s+
            (?<points_to> (?: $list_of_pointees_ref->{"voice_class_sip_profiles"}) )
            /ixsm,
    },
    'voice_class_codec' => {
    1 => qr/ ^ \s*
            voice-class \s+
            codec \s+
            (?<points_to> (?: $list_of_pointees_ref->{"voice_class_codec"}) )
            /ixsm,
    },
    'trunk_group' => {
    1 => qr/ ^ \s*
            trunk-group \s+
            (?<points_to> (?: $list_of_pointees_ref->{"trunk_group"}) )
            /ixsm,
    2 => qr/ ^ \s*
            trunkgroup \s+
            (?<points_to> (?: $list_of_pointees_ref->{"trunk_group"}) )
            /ixsm,
    },
    'dspfarm_profile' => {
    1 => qr/ ^ \s*
            associate \s+
            profile \s+
            (?<points_to> (?: $list_of_pointees_ref->{"dspfarm_profile"}) )
            /ixsm,
    },
    'sccp_ccm' => {
    1 => qr/ ^ \s*
            associate \s+
            ccm \s+
            (?<points_to> (?: $list_of_pointees_ref->{"dspfarm_profile"}) )
            /ixsm,
    },
    'ip_port_map' => {
    1 => qr/ ^ \s*
            match \s+
            protocol \s+
            (?<points_to> (?: $list_of_pointees_ref->{"ip_port_map"}) )
            /ixsm,
    },
    'crypto_keyring' => {
    1 => qr/ ^ \s*
            keyring \s+
            (?<points_to> (?: $list_of_pointees_ref->{"crypto_keyring"}) )
            /ixsm,
    },
    'isakmp_profile' => {
    1 => qr/ ^ \s*
            set \s+
            isakmp-profile \s+
            (?<points_to> (?: $list_of_pointees_ref->{"isakmp_profile"}) )
            /ixsm,
    },
