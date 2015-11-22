# Class: rhcs::agent::pgsql91
class rhcs::agent::pgsql91 {
  # brings Package['rgmanager'] used for dependencies
  include ::rhcs

  File {
    owner   => root,
    group   => root,
    require => Package['rgmanager'],
  }

  file { '/usr/share/cluster/pgsql91.metadata':
    mode    => '0644',
    source  => 'puppet:///modules/rhcs/agents/pgsql91.metadata',
  }
  file { '/usr/share/cluster/pgsql91.sh':
    mode   => '0755',
    source => 'puppet:///modules/rhcs/agents/pgsql91.sh',
  }

}
