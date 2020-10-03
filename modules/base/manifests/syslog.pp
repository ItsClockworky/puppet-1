# class base::syslog
class base::syslog (
        String $syslog_daemon   = 'rsyslog',
    ) {
        if $syslog_daemon == 'rsyslog' {
                include ::rsyslog

                file { '/etc/rsyslog.conf':
                    ensure => present,
                    source => 'puppet:///modules/base/rsyslog/rsyslog.conf',
                    notify => Service['rsyslog'],
                }
        } elsif $syslog_daemon == 'syslog_ng' {
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
                syslog_ng::destination { 'd_graylog_syslog_tls':
                        params => {
                                type => 'syslog',
                                options => [
                                        "graylog1.miraheze.org",
                                        { 'port' => [12210] },
                                        { 'transport' => 'tls' },
                                        {
                                                'tls' => [
                                                        { 'peer-verify' => 'required-trusted' },
                                                        { 'ca-dir' => '/etc/ssl/certs' },
                                                        { 'cert-file' => '/etc/ssl/certs/wildcard.miraheze.org-2020.crt' },
                                                        { 'key-file' => '/etc/ssl/private/wildcard.miraheze.org-2020.key' },
                                                ]
                                        },
                                ],
                        },
                } ->
                syslog_ng::log { 's_src_system to d_graylog_syslog_tls':
                        params => [
                                { 'source' => 's_src_system' },
                                { 'destination' => 'd_graylog_syslog_tls' },
                        ],
                } ->
                syslog_ng::log { 's_src_internal to d_graylog_syslog_tls':
                        params => [
                                { 'source' => 's_src_internal' },
                                { 'destination' => 'd_graylog_syslog_tls' },
                        ],
                }
        } else {
                warning('Invalid syslog_daemon selected for base::syslog.')
        }
}
