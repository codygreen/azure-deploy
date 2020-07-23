{
    "schemaVersion": "1.0.0",
    "class": "Device",
    "async": true,
    "label": "Onboard BIG-IP",
    "Common": {
        "class": "Tenant",
        "hostname": "${hostname}",
    },
    "myDns": {
        "class": "DNS",
        "nameServers": [
                ${name_servers}
        ],
        "search": [
            "f5.com"
        ]
    },
    "myNtp": {
        "class": "NTP",
        "servers": [
                ${ntp_servers}
        ],
        "timezone": "UTC"
    } 
 
    "${vlan-name}: {
            "class": "VLAN",
    "tag": 4093,
    "mtu": 1500,
    "interfaces": [
        {
            "name": "1.1",
            "tagged": true
        }
    ],
    "cmpHash": "dst-ip"
},
"${vlan-name}-self": {
    "class": "SelfIp",
    "address": "${self-ip}",
    "vlan": "{vlan-name}",
    "allowService": "default",
    "trafficGroup": "traffic-group-local-only"
}
}