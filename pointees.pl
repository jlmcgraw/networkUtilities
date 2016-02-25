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
                                (?: (?: standard | extended) \s+)?
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
    'policy_map' => {
    1 => qr/ (?<unique_id>
                                ^ \s*
                                policy-map \s+
                                (?<pointed_at>
                                    (?: $valid_cisco_name)
                                )
                    )
                    \s* $
                    /ixsm,

    #NXOS & ASA
    2 => qr/ (?<unique_id>
                                ^ \s*
                                policy-map \s+
                                type \s+
                                (?: queuing | qos | inspect | control-plane | management | network-qos | loadbalance) \s+
                                (?: (?: http|generic) \s+)?
                                (?: first-match \s+)?
                                (?<pointed_at>
                                    (?: $valid_cisco_name)
                                )
                    )
                    \s* $
                    /ixsm,
    3 => qr/ (?<unique_id>
                                ^ \s*
                                policy-map \s+
                                multi-match \s+
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
    2 => qr/(?<unique_id> ^ \s*
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
    #Put this longer match first so we can match on just the #
    1 => qr/(?<unique_id> ^ \s*
                        interface \s+
                        port-channel
                        (?<pointed_at> $valid_cisco_name)
        )/ixsm,

    2 => qr/(?<unique_id> ^ \s*
                            interface \s+
                            (?<pointed_at> $valid_cisco_name)
            )/ixsm,

    #     #BUG TODO Change .*? back to $valid_cisco_name if we have problems
    #     #Testing working with "pointed_at" that has spaces in it
    #     2 => qr/(?<unique_id> ^ \s*
    #                             interface \s+
    #                             (?<pointed_at> .*?)
    #                             $
    #             )/ixsm,
    },
    'track' => {
    1 => qr/(?<unique_id>^ \s*
                        (?<pointed_at> track \s+ $valid_cisco_name )
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
                        (?!responder)
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
                    (?: control-plane | qos | management | network-qos | queuing ) \s+
                    (?: (?: match-any | match-all) \s+)?
                    (?<pointed_at> $valid_cisco_name) )
                    /ixsm,

    #ASA
    4 => qr/(?<unique_id>
                    ^ \s*
                    class-map \s+
                    type \s+
                    (?: inspect | urlfilter ) \s+
                    (?: $valid_cisco_name \s+)?
                    (?: match-any | match-all) \s+
                    (?<pointed_at> $valid_cisco_name) )
                    /ixsm,
    5 => qr/(?<unique_id>
                    ^ \s*
                    class-map \s+
                    type \s+
                    (?: http ) \s+
                    (?: loadbalance ) \s+
                    (?: (?: match-any | match-all) \s+)?
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
                        (?<pointed_at> (?:ospf | eigrp | bgp  ) \s+ $valid_cisco_name)
            )
            (\s+|$)
            /ixsm,
    2 => qr/(?<unique_id>
                        ^ \s*
                        router \s+
                        (?<pointed_at> (?: isis | rip) )
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

    'parameter_map' => {

    #ASA or ACE?
    1 => qr/(?<unique_id>
                        ^ \s*
                        parameter-map \s+
                        type \s+
                        (?: (urlfpolicy \s+ local) | ( urlfpolicy \s+ trend) | urlf-glob  | protocol-info | regex) \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            (\s+|$)
            /ixsm,
    },
    'crypto_pki' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        crypto \s+
                        pki \s+
                        certificate \s+
                        chain \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            (\s+|$)
            /ixsm,
    },
    'dhcp_pool' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        ip \s+
                        dhcp \s+
                        pool \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            (\s+|$)
            /ixsm,
    },
    'ip_inspect' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        ip \s+
                        inspect \s+
                        name \s+
                        (?<pointed_at> $valid_cisco_name) \s+
                        (?:tcp | udp)
            )
            (\s+|$)
            /ixsm,
    },
    'pix_nameif' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        nameif \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,
    },
    'ace_context' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        context \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,
    },
    'ace_resource_class' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        resource-class \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,
    },
    'ace_probe' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        probe \s+
                        (?:dns|ftp|pop|tcp|http|icmp|imap|https|rtsp|smtp|snmp|udp|vm) \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,
    },
    'ace_rserver' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        rserver \s+
                        (?:host|redirect) \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,
    },
    'ace_serverfarm' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        serverfarm \s+
                        (?: (?:host|redirect) \s+)?
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,
    },
    'ace_crypto_chaingroup' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        crypto \s+
                        chaingroup \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,
    },
    'ace_ssl_proxy' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        ssl-proxy \s+
                        (?:service) \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,
    },
    'ace_parameter_map' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        parameter-map \s+
                        type \s+
                        (?:ssl|http|connection|generic) \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,
    },
    'ace_sticky' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        sticky \s+
                        http-cookie \s+
                        (?:$valid_cisco_name) \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,
    2 => qr/(?<unique_id>
                        ^ \s*
                        sticky \s+
                        ip-netmask \s+
                        \d+ \. \d+ \. \d+ \. \d+ \s+
                        address \s+
                        source \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,
    3 => qr/(?<unique_id>
                        ^ \s*
                        sticky \s+
                        layer4-payload \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            $
            /ixsm,

    },

    #   'ace_access_list' => {
    #     1 => qr/(?<unique_id>
    #                         ^ \s*
    #                         access-list \s+
    #                         (?<pointed_at> $valid_cisco_name ) \s+
    #                         )
    #                         line \s+
    #                         \d+
    #             /ixsm,
    #   },
    'ace_ft_peer' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        ft \s+
                        peer \s+
                        (?<pointed_at> $valid_cisco_name )
                        )
                        $
            /ixsm,
    },

    #     'ace_ft_group' => {
    #     1 => qr/(?<unique_id>
    #                         ^ \s*
    #                         ft \s+
    #                         group \s+
    #                         (?<pointed_at> $valid_cisco_name )
    #                         )
    #                         $
    #             /ixsm,
    #   },
    'ace_action_list' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        action-list \s+
                        type \s+
                        (?:modify|optimization) \s+
                        http \s+
                        (?<pointed_at> $valid_cisco_name )
                        )
            /ixsm,
    },
    'nxos_zoneset' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        zoneset \s+
                        name \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            /ixsm,
    },
    'nxos_zoneset_member' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        zone \s+
                        name \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            /ixsm,
    },
    'nxos_role' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        role \s+
                        name \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            /ixsm,
    },
    'ipsec_profile' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        crypto \s+
                        ipsec \s+
                        profile \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            /ixsm,
    },
    'ipsec_transform_set' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        crypto \s+
                        ipsec \s+
                        transform-set \s+
                        (?<pointed_at> $valid_cisco_name )
            )
            /ixsm,
    },
    'crypto_map' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        crypto \s+
                        map \s+
                        (?<pointed_at> $valid_cisco_name) \s+
                        \d+ \s+
            )
            /ixsm,
    },
    'aaa_list' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        aaa \s+
                        authorization \s+
                        (?: auth-proxy | network | exec | (?: commands \s+ \d+) | reverse-access | configuration | ipmobile) \s+
                        (?!default)
                        (?<pointed_at> $valid_cisco_name)
            )
            /ixsm,
    2 => qr/(?<unique_id>
                    ^ \s*
                    aaa \s+
                    authentication \s+
                    (?: ppp | login | arap | dot1x | enable | sgbp ) \s+
                    (?!default)
                    (?<pointed_at> $valid_cisco_name)
        )
        /ixsm,
    3 => qr/(?<unique_id>
                    ^ \s*
                    aaa \s+
                    accounting \s+
                    (?: auth-proxy | (?: commands \s+ \d+) | connection | dot1x | exec |  multicast | network | resource | system ) \s+
                    (?!default)
                    (?<pointed_at> $valid_cisco_name)
        )
        /ixsm,
    },
    'voice_translation_profile' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        voice \s+
                        translation-profile \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            /ixsm,

    },
    'voice_translation_rule' => {
    1 => qr/(?<unique_id>
                        ^ \s*
                        voice \s+
                        translation-rule \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            /ixsm,

    },
    'voice_class_sip_profiles' => {

    #BUG TODO: Get ID's with spaces working right and consolidate these classes
    1 => qr/(?<unique_id>
                        ^ \s*
                        voice \s+
                        class \s+
                        sip-profiles \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            /ixsm,

    },
    'voice_class_codec' => {

    #BUG TODO: Get ID's with spaces working right and consolidate these classes
    1 => qr/(?<unique_id>
                        ^ \s*
                        voice \s+
                        class \s+
                        codec \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            /ixsm,

    },
    'trunk_group' => {

    #BUG TODO: Get ID's with spaces working right and consolidate these classes
    1 => qr/(?<unique_id>
                        ^ \s*
                        trunk \s+
                        group \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            /ixsm,

    },
    'dspfarm_profile' => {

    #BUG TODO: Get ID's with spaces working right and consolidate these classes
    1 => qr/(?<unique_id>
                        ^ \s*
                        dspfarm \s+
                        profile \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            /ixsm,

    },
    'sccp_ccm' => {

    #BUG TODO: Get ID's with spaces working right and consolidate these classes
    1 => qr/(?<unique_id>
                        ^ \s*
                        sccp \s+
                        ccm \s+
                        .*?
                        identifier \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            /ixsm,

    },
    'ip_port_map' => {

    #BUG TODO: Get ID's with spaces working right and consolidate these classes
    1 => qr/(?<unique_id>
                        ^ \s*
                        ip \s+
                        port-map \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            /ixsm,

    },
    'crypto_keyring' => {

    #BUG TODO: Get ID's with spaces working right and consolidate these classes
    1 => qr/(?<unique_id>
                        ^ \s*
                        crypto \s+
                        keyring \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            /ixsm,

    },
    'isakmp_profile' => {

    #BUG TODO: Get ID's with spaces working right and consolidate these classes
    1 => qr/(?<unique_id>
                        ^ \s*
                        crypto \s+
                        isakmp \s+
                        profile \s+
                        (?<pointed_at> $valid_cisco_name)
            )
            /ixsm,

    },
