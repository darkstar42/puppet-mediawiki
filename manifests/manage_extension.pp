# Class: mediawiki::manage_extension
#
define mediawiki::manage_extension(
  $ensure,
  $instance,
  $source,
  $doc_root,
){
  $extension = $name
  $path = "${doc_root}/${instance}/LocalSettings.php"

  mediawiki_extension { $extension:
    ensure   =>  present,
    instance =>  $instance,
    source   =>  $source,
    doc_root =>  $doc_root,
    notify   =>  Exec["set_${extension}_perms"],
  }

  exec{"set_${extension}_perms":
    command     =>  "/bin/chown -R ${mediawiki::params::apache_user}:${mediawiki::params::apache_user} ${doc_root}/${instance}",
    refreshonly =>  true,
    notify      =>  Exec["set_${extension}_perms_two"],
  }
  exec{"set_${extension}_perms_two":
    command     =>  "/bin/chown -R ${mediawiki::params::apache_user}:${mediawiki::params::apache_user} /etc/mediawiki/${instance}",
    refreshonly =>  true,
    notify      =>  Exec["set_${extension}_perms_three"],
  }
  exec{"set_${extension}_perms_three":
    command     =>  "/bin/chown -R ${mediawiki::params::apache_user}:${mediawiki::params::apache_user} ${mediawiki::params::web_dir}/mediawiki*",
    refreshonly =>  true,
  }
}
