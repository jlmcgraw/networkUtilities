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
    9 =>
        qr /^ \s* match (?: \s+ not )? access-group \s+ (?<points_to> $list_of_pointees_ref->{"acl"}) $/ixsm,

    },
'service_policy' => {
    1 =>
        qr/^ \s* service-policy \s+ (?: input|output) \s+ (?<points_to> $list_of_pointees_ref->{"service_policy"})/ixsm,
    2 =>
        qr/^ \s* service-policy \s+ (?<points_to> $list_of_pointees_ref->{"service_policy"})$/ixsm,
    },
'route_map' => {
    1 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ route-map \s+ (?<points_to> $list_of_pointees_ref->{"route_map"})/ixsm,
    2 =>
        qr/^ \s* redistribute \s+ (?:static|bgp|ospf|eigrp|isis|rip) (?: \s+ \d+)? \s+ route-map \s+ (?<points_to> $list_of_pointees_ref->{"route_map"})/ixsm,
    3 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ default-originate \s+ route-map \s+ (?<points_to> $list_of_pointees_ref->{"route_map"})/ixsm,
    },
'prefix_list' => {
    1 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ prefix-list \s+ (?<points_to> $list_of_pointees_ref->{"prefix_list"}) \s+ (?:in|out)$/ixsm,
    2 =>
        qr/^ \s* 
            match \s+ 
            ip \s+ 
            address \s+ 
            prefix-list \s+ 
            (?<points_to> (?: $list_of_pointees_ref->{"prefix_list"} | \s )+ )           #This can be a list of things
                                                                                         #separated by whitespace
           /ixsm,
    },
'community_list'      => {},
'as_path_access_list' => {
    1 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ filter-list \s+ (?<points_to> $list_of_pointees_ref->{"as_path_access_list"}) \s+ (?:in|out)$/ixsm,
    2 =>
        qr/^ \s* match \s+ as-path \s+ (?<points_to> $list_of_pointees_ref->{"as_path_access_list"}) $/ixsm,

    },
'interface' => {
    1 => qr/source-interface \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) /ixsm,
    2 => qr/ntp \s+ source \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) /ixsm,
    3 =>
        qr/^ \s* no \s+ passive-interface \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) /ixsm,
    4 =>
        qr/snmp-server \s+ trap-source \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) /ixsm,
    5 =>
        qr/^ \s* ip \s+ flow-export \s+ source \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) /ixsm,
    6 =>
        qr/^ \s* neighbor \s+ $RE{net}{IPv4} \s+ update-source \s+ (?<points_to> $list_of_pointees_ref->{"interface"}) $/ixsm,

    },
    
'track' => {    
    1 => qr/^ \s*
                    (?: standby | vrrp ) \s+
                    \d+ \s+
                    track \s+
                    (?<points_to> $list_of_pointees_ref->{"track"} )
        /isxm,
    },
    
'vrf' => {
    1 => qr/^ \s*
                    ip \s+
                    vrf \s+
                    forwarding \s+
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

    },

'class' => {
    1 => qr/ ^ \s*
        class \s+
        (?<points_to> (?: $list_of_pointees_ref->{"class"}) )
        $
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
