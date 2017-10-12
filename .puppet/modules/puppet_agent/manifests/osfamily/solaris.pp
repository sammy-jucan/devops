class puppet_agent::osfamily::solaris(
  $package_file_name = undef,
) {
  assert_private()

  if $::operatingsystem != 'Solaris' {
    fail("${::operatingsystem} not supported")
  }

  if $::puppet_agent::is_pe == false {
    fail('Solaris upgrades are only supported on Puppet Enterprise')
  }

  case $::operatingsystemmajrelease {
    '10': {
      class { 'puppet_agent::prepare::package':
        package_file_name => $package_file_name,
      }
      contain puppet_agent::prepare::package

      $_unzipped_package_name = regsubst($package_file_name, '\.gz$', '')
      exec { "unzip ${package_file_name}":
        path      => '/bin:/usr/bin:/sbin:/usr/sbin',
        command   => "gzip -d /opt/puppetlabs/packages/${package_file_name}",
        creates   => "/opt/puppetlabs/packages/${_unzipped_package_name}",
        require   => Class['puppet_agent::prepare::package'],
        logoutput => 'on_failure',
      }

      $pe_server_version = pe_build_version()
      file { '/opt/puppetlabs/packages/solaris-noask':
        ensure => present,
        owner  => 0,
        group  => 0,
        mode   => '0644',
        source => "puppet:///pe_packages/${pe_server_version}/${::platform_tag}/solaris-noask",
      }
    }
    '11': {
      if $::puppet_agent::manage_repo {
        class { 'puppet_agent::prepare::package':
          package_file_name => $package_file_name,
        }
        contain puppet_agent::prepare::package

        $pkgrepo_dir = '/etc/puppetlabs/installer/solaris.repo'
        $publisher = 'puppetlabs.com'
        $arch = $::architecture ? {
          /^sun4[uv]$/ => 'sparc',
          default      => 'i386',
        }
        $pkg_name = basename($package_file_name, ".${arch}.p5p")

        exec { 'puppet_agent remove existing repo':
          command   => "rm -rf '${pkgrepo_dir}'",
          path      => '/bin:/usr/bin:/sbin:/usr/sbin',
          onlyif    => "test -d ${pkgrepo_dir}",
          logoutput => 'on_failure',
          unless    => "pkgrepo list -p ${publisher} -s ${pkgrepo_dir} ${pkg_name}",
        }
        ~> exec { 'puppet_agent create repo':
          command     => "pkgrepo create ${pkgrepo_dir}",
          path        => '/bin:/usr/bin:/sbin:/usr/sbin',
          unless      => "test -f ${pkgrepo_dir}/pkg5.repository",
          logoutput   => 'on_failure',
          refreshonly => true,
        }
        ~> exec { 'puppet_agent set publisher':
          command     => "pkgrepo set -s ${pkgrepo_dir} publisher/prefix=${publisher}",
          path        => '/bin:/usr/bin:/sbin:/usr/sbin',
          logoutput   => 'on_failure',
          refreshonly => true,
        }
        ~> exec { 'puppet_agent ensure pkgrepo is up-to-date':
          command     => "pkgrepo refresh -s ${pkgrepo_dir}",
          path        => '/bin:/usr/bin:/sbin:/usr/sbin',
          logoutput   => 'on_failure',
          refreshonly => true,
        }
        ~> exec { 'puppet_agent copy packages':
          command     => "pkgrecv -s file:///opt/puppetlabs/packages/${package_file_name} -d ${pkgrepo_dir} '*'",
          path        => '/bin:/usr/bin:/sbin:/usr/sbin',
          logoutput   => 'on_failure',
          refreshonly => true,
        }
        # Make sure the pkg publishers are all available.  Broken
        # publisher entries will stop the installation process.
        # This must happen before removing any packages.
        # We rely on the puppetlabs.com publisher previously being
        # setup (during the initial install).
        ~> exec { 'puppet_agent ensure pkg publishers are available':
          command     => "pkg refresh ${publisher}",
          path        => '/bin:/usr/bin:/sbin:/usr/sbin',
          logoutput   => 'on_failure',
          refreshonly => true,
        }
      }

      if versioncmp("${::clientversion}", '4.0.0') < 0 {
        # Backup user configuration because solaris 11 will blow away
        # /etc/puppetlabs/ when uninstalling the pe-* modules.
        file { '/tmp/puppet_agent/':
          ensure => directory,
        }
        -> exec { 'puppet_agent backup /etc/puppetlabs/':
          command => 'cp -r /etc/puppetlabs/ /tmp/puppet_agent/',
          require => Exec['puppet_agent copy packages'],
          path    => '/bin:/usr/bin:/sbin:/usr/sbin',
        }
      }

    }
    default: {
      fail("${::operatingsystem} ${::operatingsystemmajrelease} not supported")
    }
  }
}