'acl' => {
    1 =>
        qr /^ \s* match \s+ access-group \s+ name \s+ (?<points_to> $validPointeeNameRegex)/ixsm,
    2 =>
        qr /^ \s* snmp-server \s+ community \s+ (?: $valid_cisco_name) \s+ view \s+ (?: $valid_cisco_name) \s+ (?: RO|RW) \s+ (?<points_to> $validPointeeNameRegex)/ixsm,
    3 =>
        qr /^ \s* snmp-server \s+ community \s+ (?: $valid_cisco_name) \s+ (?: RO|RW) \s+ (?<points_to> $validPointeeNameRegex)/ixsm,
    4 =>
        qr /^ \s* snmp-server \s+ file-transfer \s+ access-group \s+ (?<points_to> $validPointeeNameRegex) \s+ protocol/ixsm,
    5 =>
        qr /^ \s* access-class \s+ (?<points_to> $validPointeeNameRegex) \s+ (?: in|out)/ixsm,
    6 =>
        qr /^ \s* snmp-server \s+ tftp-server-list \s+ (?<points_to> $validPointeeNameRegex)/ixsm,
    7 =>
        qr /^ \s* ip \s+ directed-broadcast \s+ (?<points_to> $validPointeeNameRegex) $/ixsm,

    },
'service_policy' => {
    1 =>
        qr/^ \s* service-policy \s+ (?: input|output) \s+ (?<points_to> $validPointeeNameRegex)/ixsm,
    2 =>
        qr/^ \s* service-policy \s+ (?<points_to> $validPointeeNameRegex)$/ixsm,
    },
'route_map' => {
    1 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ route-map \s+ (?<points_to> $valid_cisco_name)/ixsm,
    2 =>
        qr/^ \s* redistribute \s+ (?:static|bgp|ospf|eigrp|isis|rip) (?: \s+ \d+)? \s+ route-map \s+ (?<points_to> $valid_cisco_name)/ixsm,
    3 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ default-originate \s+ route-map \s+ (?<points_to> $valid_cisco_name)/ixsm,
    },
'prefix_list' => {
    1 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ prefix-list \s+ (?<points_to> $valid_cisco_name) \s+ (?:in|out)$/ixsm,
    2 =>
        qr/^ \s* match \s+ ip \s+ address \s+ prefix-list \s+ (?<points_to> $valid_cisco_name) $/ixsm,
    },
'community_list'      => {},
'as_path_access_list' => {
    1 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ filter-list \s+ (?<points_to> $valid_cisco_name) \s+ (?:in|out)$/ixsm,
    2 =>
        qr/^ \s* match \s+ as-path \s+ (?<points_to> $valid_cisco_name) $/ixsm,

    },
'interface' => {
    1 => qr/source-interface \s+ (?<points_to> $valid_cisco_name) /ixsm,
    2 => qr/ntp \s+ source \s+ (?<points_to> $valid_cisco_name) /ixsm,
    3 =>
        qr/^ \s* no \s+ passive-interface \s+ (?<points_to> $valid_cisco_name) /ixsm,
    4 =>
        qr/snmp-server \s+ trap-source \s+ (?<points_to> $valid_cisco_name) /ixsm,
    5 =>
        qr/^ \s* ip \s+ flow-export \s+ source \s+ (?<points_to> $valid_cisco_name) /ixsm,

    },
'track' => {
    1 => qr/^ \s*
                    standby \s+
                    \d+ \s+                                
                    track \s+
                    (?<points_to> \d+ )
                    (\s+|$)
        
        /ixsm,
    2 => qr/^ \s*
                    vrrp \s+
                    \d+ \s+                                
                    track \s+
                    (?<points_to> \d+ )
                    (\s+|$)
        
        /ixsm,
    },
'vrf' => {
    1 => qr/^ \s*
                    ip \s+
                    vrf \s+
                    forwarding \s+
                    (?<points_to> (?: $valid_cisco_name) )
                    (\s+|$)
        /ixsm,
    2 => qr/^ \s*
                    vrf \s+
                    forwarding \s+
                    (?<points_to> (?: $valid_cisco_name) )
                    (\s+|$)
        /ixsm,
    3 => qr/^ \s*
                    ip \s+
                    route \s+
                    vrf \s+
                    (?<points_to> (?: $valid_cisco_name) )
                    (\s+|$)
        /ixsm,
    },
'key_chain' => {

    #Make this guy have to have some alphanumeric in front of him
    1 => qr/ \w+ \s+
        key-chain \s+
        (?<points_to> (?: $valid_cisco_name) )
        (\s+|$)
        /ixsm,

    },
'ip_sla' => {
    1 => qr/ ^ \s*
        ip \s+
        sla \s+
        schedule \s+
        (?<points_to> (?: $valid_cisco_name) )
        /ixsm,

    },
'class' => {
    1 => qr/ ^ \s*
        class \s+
        (?<points_to> (?: $valid_cisco_name) )
        $
        /ixsm,

    },
