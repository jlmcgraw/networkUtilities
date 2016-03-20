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
            (?:any|host \s+ \d+.\d+.\d+.\d+ ) \s+
            (?:any|host \s+ \d+.\d+.\d+.\d+ ) \s+
        )
        /ixsm,