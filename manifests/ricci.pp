# Class: rhcs::ricci
#
# This module configures ricci (cluster & storage
# configuration daemon)
#
class rhcs::ricci (
  $cluster_name       = $rhcs::cluster_name,
  $client_cert_source = "puppet:///modules/srce/rhcs/${cluster_name}/client_cert_${::hostname}",
  $source             = 'puppet:///private/ricci/ca',
) inherits rhcs {
  # defaults
  File {
    ensure  => file,
    owner   => ricci,
    group   => ricci,
    mode    => '0640',
    require => Package['ricci'],
  }

  # package
  package { 'ricci': ensure => present, }

  # CA files
  file { '/var/lib/ricci/certs/cacert.pem':
    source => "${source}/cacert.pem",
    mode   => '0644',
  }
  file { '/var/lib/ricci/certs/server.p12':
    source => "${source}/server.p12",
    mode   => '0644',
  }
  file { '/var/lib/ricci/certs/cacert.config':
    source => "${source}/cacert.config",
    mode   => '0644',
  }
  file { '/var/lib/ricci/certs/cert8.db':    source => "${source}/cert8.db", }
  file { '/var/lib/ricci/certs/key3.db':     source => "${source}/key3.db", }
  file { '/var/lib/ricci/certs/privkey.pem': source => "${source}/privkey.pem", }
  file { '/var/lib/ricci/certs/secmod.db':   source => "${source}/secmod.db", }

  # service
  service { 'ricci':
    ensure    => running,
    enable    => true,
    provider  => redhat,
    subscribe => [
      File['/var/lib/ricci/certs/cacert.pem'],
      File['/var/lib/ricci/certs/server.p12'],
      File['/var/lib/ricci/certs/cert8.db'],
      File['/var/lib/ricci/certs/key3.db'],
      File['/var/lib/ricci/certs/privkey.pem'],
      File['/var/lib/ricci/certs/secmod.db'], ],
  }

  # export cacert, because ccs_sync uses it as client cert
  @@file { "/var/lib/ricci/certs/clients/client_cert_${::hostname}":
    source => $client_cert_source,
    notify => Service['ricci'],
    tag    => "ricci_client_${cluster_name}",
  }

  # collect client certificates for this cluster
  File <<| tag == "ricci_client_${cluster_name}" |>>
}
