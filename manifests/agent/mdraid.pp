# Class: rhcs::agent::mdraid
class rhcs::agent::mdraid {
  # brings Package['rgmanager'] used for dependencies
  include ::rhcs

  File {
    owner   => root,
    group   => root,
    require => Package['rgmanager'],
  }

  file { '/usr/share/cluster/mdraid.metadata':
    mode    => '0644',
    source  => 'puppet:///modules/rhcs/agents/mdraid.metadata',
  }
  file { '/usr/share/cluster/mdraid.sh':
    mode   => '0755',
    source => 'puppet:///modules/rhcs/agents/mdraid.sh',
  }

}
