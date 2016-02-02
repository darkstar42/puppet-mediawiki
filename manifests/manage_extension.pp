# Class: mediawiki::manage_extension
#
define mediawiki::manage_extension(
  $ensure,
  $instance,
  $source,
  $doc_root,
  $wiki_name
){
  $extension = $name
  $line = "require_once( \"${doc_root}/${instance}/extensions/ConfirmAccount/ConfirmAccount.php\" );"
  $path = "${doc_root}/${instance}/LocalSettings.php"

  mediawiki_extension { $extension:
    ensure   =>  present,
    instance =>  $wiki_name,
    source   =>  $source,
    doc_root =>  $doc_root,
    notify   =>  Exec["set_${extension}_perms"],
  }

  file_line{"${extension}_include":
    ensure  =>  $ensure,
    line    =>  $line,
    path    =>  $path,
    require =>  Mediawiki_extension['ConfirmAccount'],
    notify  =>  Exec["set_${extension}_perms"],
  }
  File_line["${extension}_include"] ~> Service<| title == 'httpd' |>
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
    command     =>  "/bin/chown -R ${mediawiki::params::apache_user}:${mediawiki::params::apache_user} /var/www/html/mediawiki*",
    refreshonly =>  true,
  }
}
