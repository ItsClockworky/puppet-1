# class base::syslog
class base::syslog (
        String  $syslog_daemon              = lookup('base::syslog::syslog_daemon', {'default_value' => 'syslog_ng'}),
        String  $graylog_hostname           = lookup('base::syslog::graylog_hostname', {'default_value' => 'graylog121.miraheze.org'}),
        Integer $graylog_resolve_ip_version = lookup('base::syslog::graylog_resolve_ip_version', {'default_value' => 6}),
        Array[String] $syslog_host          = lookup('base::syslog::syslog_host', {'default_value' => []}),
        Integer $syslog_queue_size          = lookup('base::syslog::syslog_queue_size', {'default_value' => 10000}),
        Boolean $rsyslog_udp_localhost      = lookup('base::syslog::rsyslog_udp_localhost', {'default_value' => false}),
) {
        # We don't need persistant journals, all this did was cause slowness.
        file { '/var/log/journal' :
                ensure  => absent,
                recurse => true,
                force   => true,
                notify  => Service['systemd-journald'],
        }

        # Have to define this in order to restart it
        service { 'systemd-journald':
                ensure  => 'running',
        }

        if $syslog_daemon == 'rsyslog' {
                include ::rsyslog

                file { '/etc/rsyslog.conf':
                        ensure => present,
                        source => 'puppet:///modules/base/rsyslog/rsyslog.conf',
                        notify => Service['rsyslog'],
                }

                logrotate::conf { 'rsyslog':
                        ensure  => present,
                        source  => 'puppet:///modules/base/rsyslog/rsyslog.logrotate.conf',
                        require => Class['rsyslog'],
                }

                if !empty( $syslog_host ) {
                        ensure_packages('rsyslog-gnutls')

                        ssl::wildcard { 'rsyslog wildcard': }

                        rsyslog::conf { 'remote_syslog_rule':
                                content  => template('base/rsyslog/remote_syslog_rule.conf.erb'),
                                priority => 10,
                                require  => Ssl::Wildcard['rsyslog wildcard']
                        }

                        rsyslog::conf { 'remote_syslog_rule_parse_json':
                                content  => template('base/rsyslog/remote_syslog_rule_parse_json.conf.erb'),
                                priority => 10,
                                require  => Ssl::Wildcard['rsyslog wildcard']
                        }

                        rsyslog::conf { 'remote_syslog':
                                content  => template('base/rsyslog/remote_syslog.conf.erb'),
                                priority => 30,
                                require  => Ssl::Wildcard['rsyslog wildcard']
                        }

                        $ensure_enabled = $rsyslog_udp_localhost ? {
                                true    => present,
                                default => absent,
                        }

                        rsyslog::conf { 'rsyslog_udp_localhost':
                                ensure   => $ensure_enabled,
                                content  => template('base/rsyslog/rsyslog_udp_localhost.conf.erb'),
                                priority => 50,
                        }

                        if !defined(Rsyslog::Conf['mmjsonparse']) {
                                rsyslog::conf { 'mmjsonparse':
                                        content  => 'module(load="mmjsonparse")',
                                        priority => 00,
                                }
                        }
                }
        } elsif $syslog_daemon == 'syslog_ng' {
                package { 'rsyslog':
                    ensure  => purged,
                } ->
                class { '::syslog_ng':
                        config_file_header      => "# This file was generated by Puppet's ccin2p3-syslog_ng module\n@version: 3.19",
                        manage_init_defaults    => false,
                        manage_repo             => false, # Is the default, but explicitly defined now
                } ->
                syslog_ng::options { 'global_options':
                        options     => {
                                'chain_hostnames'       => 'off',
                                'flush_lines'           => 0,
                                'stats_freq'            => 0,
                                'use_dns'               => 'no',
                                'use_fqdn'              => 'yes',
                                'dns_cache'             => 'no',
                        },
                } ->
                syslog_ng::rewrite { 'r_hostname':
                        params => {
                                'type'      => 'set',
                                'options'   => [
                                        $::fqdn,
                                        { 'value' => 'HOST' }
                                ],
                        },
                } ->
                syslog_ng::source { 's_src_system':
                        params => {
                                'type'          => 'system',
                                'options'       => [],
                        },
                } ->
                syslog_ng::source { 's_src_internal':
                        params => {
                                'type'          => 'internal',
                                'options'       => [],
                        },
                } ->
                syslog_ng::source { 's_src_udp_local':
                        params => {
                                'type'          => 'syslog',
                                'options'       => [
                                        { 'transport'   => 'udp' },
                                        { 'port'        => 10514 },
                                ],
                        }
                } ->
                syslog_ng::destination { 'd_graylog_syslog_tls':
                        params => {
                                type    => 'syslog',
                                options => [
                                        $graylog_hostname,
                                        {
                                                'ip-protocol' => $graylog_resolve_ip_version,
                                        },
                                        { 
                                                'port' => [ 12210 ] 
                                        },
                                        { 
                                                'transport' => 'tls' 
                                        },
                                        {
                                                'tls' => [
                                                        { 
                                                                'peer-verify' => 'required-trusted' 
                                                        },
                                                        { 
                                                                'ca-dir' => '/etc/ssl/certs' 
                                                        },
                                                        {       
                                                                'ssl-options' => [ 'no-sslv2', 'no-sslv3', 'no-tlsv1', 'no-tlsv11' ] 
                                                        }
                                                ]
                                        },
                                        {
                                                'disk-buffer' => [
                                                        { 
                                                                'dir' => '/var/tmp' 
                                                        },
                                                        { 
                                                                'disk-buf-size' => '1073741824' 
                                                        },
                                                        { 
                                                                'mem-buf-size' => '33554432' 
                                                        },
                                                        { 
                                                                'reliable' => 'yes' 
                                                        }
                                                ]
                                        },
                                ],
                        },
                } ->
                syslog_ng::log { 's_src_system to d_graylog_syslog_tls':
                        params => [
                                { 
                                        'source' => 's_src_system' 
                                },
                                { 
                                        'destination' => 'd_graylog_syslog_tls' 
                                },
                        ],
                } ->
                syslog_ng::log { 's_src_internal to d_graylog_syslog_tls':
                        params => [
                                { 
                                        'source' => 's_src_internal' 
                                },
                                { 
                                        'destination' => 'd_graylog_syslog_tls' 
                                },
                        ],
                } ->
                syslog_ng::log { 's_src_udp_local to d_graylog_syslog_tls':
                    params => [
                        {
                            'source' => 's_src_udp_local',
                        },
                        {
                            'rewrite' => 'r_hostname',
                        },
                        {
                            'destination' => 'd_graylog_syslog_tls',
                        },
                    ],
                }
        } else {
                warning('Invalid syslog_daemon selected for base::syslog.')
        }
}
