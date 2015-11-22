# Class: rhcs::agent::rsyslog
class rhcs::agent::rsyslog {
  # brings Package['rgmanager'] used for dependencies
  include ::rhcs

  File {
    owner   => root,
    group   => root,
    require => Package['rgmanager'],
  }

  file { '/usr/share/cluster/rsyslog.metadata':
    mode    => '0644',
    source  => 'puppet:///modules/rhcs/agents/rsyslog.metadata',
  }
  file { '/usr/share/cluster/rsyslog.sh':
    mode   => '0755',
    source => 'puppet:///modules/rhcs/agents/rsyslog.sh',
  }

}
