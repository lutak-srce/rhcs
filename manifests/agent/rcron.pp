# Class: rhcs::agent::rcron
class rhcs::agent::rcron {
  # brings Package['rgmanager'] used for dependencies
  include ::rhcs

  File {
    owner   => root,
    group   => root,
    require => Package['rgmanager'],
  }

  file { '/usr/share/cluster/rcron.metadata':
    mode    => '0644',
    source  => 'puppet:///modules/rhcs/agents/rcron.metadata',
  }
  file { '/usr/share/cluster/rcron.sh':
    mode   => '0755',
    source => 'puppet:///modules/rhcs/agents/rcron.sh',
  }

}
