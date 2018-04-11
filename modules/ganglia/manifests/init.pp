# class: ganglia
class ganglia(
    $modules = ['rewrite', 'ssl', 'php5']
) {
    include ::httpd

    include ssl::wildcard

    $packages = [
        'rrdtool',
        'gmetad',
        'ganglia-webfrontend',
    ]

    package { $packages:
        ensure => present,
    }

    require_package('libapache2-mod-php5')

    file { '/etc/ganglia/gmetad.conf':
        ensure => present,
        source => 'puppet:///modules/ganglia/gmetad.conf',
    }

    file { '/etc/apache2/sites-enabled/apache.conf':
        ensure => absent,
    }

    httpd::site { 'ganglia.miraheze.org':
        ensure  => present,
        source  => 'puppet:///modules/ganglia/apache/apache.conf',
        require => File['/etc/apache2/sites-enabled/apache.conf'],
        monitor => true,
    }

    file { '/etc/php5/apache2/php.ini':
        ensure  => present,
        mode    => '0755',
        source  => 'puppet:///modules/ganglia/apache/php.ini',
        require => Package['libapache2-mod-php5']
    }

    httpd::mod { 'ganglia_apache':
        modules => $modules
        require => Package['libapache2-mod-php5'],
    }
}
