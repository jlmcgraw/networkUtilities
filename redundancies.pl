1 => qr/
        ^ \s*
        (?<match>
            access-list \s+
            \d+ 
            )
        /ixsm,
            
2 => qr/
        ^ \s*
        (?<match>
            snmp-server \s+
            community \s+
            $valid_cisco_name
            )
        /ixsm,

3 => qr/
        ^ \s*
        (?<match>
        neighbor \s+
        $ipv4AddressRegex
        )
        /ixsm,
4 => qr/
        ^ \s*
        (?<match>
            snmp-server \s+
            view \s+
            $valid_cisco_name
        )
        /ixsm,
5 => qr/
        ^ \s*
        (?<match>
            random-detect \s+
            dscp
        )
        /ixsm,        
6 => qr/
        ^ \s*
        (?<match>
            aaa \s+
            (?:authentication|authorization|accounting)
        )
        /ixsm,
7 => qr/
        ^ \s*
        (?<match>
            snmp-server \s+
            enable \s+
            traps
        )
        /ixsm,
8 => qr/
        ^ \s*
        (?<match>
            ip \s+
            prefix-list \s+
            $valid_cisco_name
        )
        /ixsm,
9 => qr/
        ^ \s*
        (?<match>
           ip \s+
           as-path \s+
           access-list \s+
            \d+ 
            )
        /ixsm,
10 => qr/
        ^ \s*
        (?<match>
            (?:permit|deny) \s+
            (?:ip|udp|tcp) \s+
            (?:any | host \s+ $RE{net}{IPv4} | $RE{net}{IPv4} \s+ $RE{net}{IPv4} ) \s+
        )
        /ixsm,
11 => qr/
        ^ \s*
        (?<match>
            (?:ip) \s+
            (?:route) \s+
            (?:$RE{net}{IPv4} \s+ $RE{net}{IPv4} ) \s+
        )
        /ixsm,
12 => qr/
        ^ \s*
        (?<match>
            (?:standby) \s+
            (?:\d+) \s+
        )
        /ixsm,
13 => qr/
        ^ \s*
        (?<match>
            (?:service) \s+
        )
        /ixsm,
14 => qr/
        ^ \s*
        (?<match>
            (?:mls \s+ 
            qos \s+ 
            srr-queue \s+ 
            output \s+ 
            (?:dscp|cos)-map \s+ 
             queue) \s+
        )
        /ixsm,
15 => qr/
        ^ \s*
        (?<match>
            (?:spanning-tree) \s+
        )
        /ixsm,
16 => qr/
        ^ \s*
        (?<match>
            (?:switchport) \s+
        )
        /ixsm,
17 => qr/
        ^ \s*
        (?<match>
            (?: srr-queue \s+ bandwidth) \s+
        )
        /ixsm,         