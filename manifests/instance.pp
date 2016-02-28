# == Define: mediawiki::instance
#
# This defined type allows the user to create a mediawiki instance.
#
# === Parameters
#
# [*db_name*]        - name of the mediawiki instance mysql database
# [*db_user*]        - name of the mysql database user
# [*db_password*]    - password for the mysql database user
# [*ip*]             - ip address of the mediawiki web server
# [*port*]           - port on mediawiki web server
# [*server_aliases*] - an array of mediawiki web server aliases
# [*ensure*]         - the current status of the wiki instance
#                    - options: present, absent, deleted
#
# === Examples
#
# class { 'mediawiki':
#   admin_email      => 'admin@puppetlabs.com',
#   db_root_password => 'really_really_long_password',
#   max_memory       => '1024'
# }
#
# mediawiki::instance { 'my_wiki1':
#   db_password => 'really_long_password',
#   db_name     => 'wiki1',
#   db_user     => 'wiki1_user',
#   port        => '80',
#   ensure      => 'present'
# }
#
# === Authors
#
# Martin Dluhos <martin@gnu.org>
#
# === Copyright
#
# Copyright 2012 Martin Dluhos
#
define mediawiki::instance (
  $db_password,
  $db_name                = $name,
  $db_user                = "${name}_user",
  $db_prefix              = 'wk',
  $ip                     = '*',
  $port                   = '80',
  $sslport                = '443',
  $redirect_to_ssl        = false,
  $server_aliases         = undef,
  $ensure                 = 'present',
  $allow_html_email       = false,
  $additional_mail_params = 'null',
  $logo_url               = false,
  $external_smtp          = false,
  $smtp_idhost            = undef,
  $smtp_host              = undef,
  $smtp_port              = undef,
  $smtp_auth              = undef,
  $smtp_username          = undef,
  $smtp_password          = undef,
  $apache_user            = $mediawiki::params::apache_user,
) {

  validate_re($ensure, '^(present|absent|deleted)$',
  "${ensure} is not supported for ensure.
  Allowed values are 'present', 'absent', and 'deleted'.")

  include ::mediawiki::params

  # MediaWiki needs to be installed before a particular instance is created
  Class['mediawiki'] -> Mediawiki::Instance[$name]

  # Make the configuration file more readable
  $admin_email             = $mediawiki::admin_email
  $db_root_password        = $mediawiki::db_root_password
  $server_name             = $mediawiki::server_name
  $doc_root                = $mediawiki::doc_root
  $mediawiki_install_path  = $mediawiki::mediawiki_install_path
  $mediawiki_conf_dir      = $mediawiki::params::conf_dir
  $mediawiki_install_files = $mediawiki::params::installation_files

  if $external_smtp {
    if ! $smtp_idhost   { fail("'smtp_idhost' required when 'external_smtp' is true.") }
    if ! $smtp_host     { fail("'smtp_host' required when 'external_smtp' is true.") }
    if ! $smtp_port     { fail("'smtp_port' required when 'external_smtp' is true.") }
    if ! $smtp_auth     { fail("'smtp_auth' required when 'external_smtp' is true.") }
    if ! $smtp_username { fail("'smtp_username' required when 'external_smtp' is true.") }
    if ! $smtp_password { fail("'smtp_password' required when 'external_smtp' is true.") }
    $wgsmtp = "array('host' => '${smtp_host}', 'idhost' => '${smtp_idhost}', 'port' => '${smtp_port}', 'auth' => '${smtp_auth}', 'username' => '${smtp_username}', 'password' => '${smtp_password}')"
  } else {
    $wgsmtp = false
  }

  # Figure out how to improve db security (manually done by
  # mysql_secure_installation)
  case $ensure {
    'present', 'absent': {
      exec { "${name}-install_script":
        cwd       => "${mediawiki_install_path}/maintenance",
        command   => "/usr/bin/php install.php                   \
                        --pass puppet05                          \
                        --server http://${server_name}           \
                        --scriptpath /${name}                    \
                        --dbtype mysql                           \
                        --dbserver localhost                     \
                        --installdbuser root                     \
                        --installdbpass ${db_root_password}      \
                        --dbname ${db_name}                      \
                        --dbuser ${db_user}                      \
                        --dbpass ${db_password}                  \
                        --dbprefix ${db_prefix}                  \
                        --confpath ${mediawiki_conf_dir}/${name} \
                        --lang en                                \
                        ${name} admin",
        creates   => "${mediawiki_conf_dir}/${name}/LocalSettings.php",
        subscribe => File["${mediawiki_conf_dir}/${name}/images"],
      }

      # Ensure resource attributes common to all resources
      File {
        ensure => directory,
        owner  => $apache_user,
        group  => $apache_user,
        mode   => '0755',
      }

      $settings = "${mediawiki_conf_dir}/${name}/LocalSettings.php"

      file { 'mediawiki_extension_conf_dir':
        ensure => 'directory',
        path   => "${mediawiki_conf_dir}/${name}/conf.d",
        require => File['mediawiki_conf_dir'],
      }

      # MediaWIki Custom Logo
      if $logo_url {
        file_line { "${name}_logo_url":
          path => "${mediawiki_conf_dir}/${name}/LocalSettings.php",
          line => "\$wgLogo = '${logo_url}';",
        }
      }

      file_line { "${name}_extensions":
        path => "${mediawiki_conf_dir}/${name}/LocalSettings.php",
        line => "foreach (glob('${mediawiki_conf_dir}/${name}/conf.d/*.php') as \$filename) { require_once \$filename; }",
      }

      # MediaWiki instance directory
      file { "${mediawiki_conf_dir}/${name}":
        ensure => directory,
      }

      # MediaWiki DefaultSettings
      file { "${mediawiki_conf_dir}/${name}/includes/DefaultSettings.php":
        ensure  => present,
        content => template('mediawiki/DefaultSettings.php.erb'),
      }

      # Each instance needs a separate folder to upload images
      file { "${mediawiki_conf_dir}/${name}/images":
        ensure => directory,
        group  => $apache_user,
      }

      # Ensure that mediawiki configuration files are included in each instance.
      mediawiki::symlinks { $name:
        conf_dir      => $mediawiki_conf_dir,
        install_files => $mediawiki_install_files,
        target_dir    => $mediawiki_install_path,
      }

      # Symlink for the mediawiki instance directory
      file { "${doc_root}/${name}":
        ensure  => link,
        target  => "${mediawiki_conf_dir}/${name}",
        require => File["${mediawiki_conf_dir}/${name}"],
      }

      # Each instance has a separate vhost configuration

      if $port {
        if $redirect_to_ssl {
          apache::vhost { $name:
            ensure          => $ensure,
            port            => $port,
            docroot         => $doc_root,
            serveradmin     => $admin_email,
            servername      => $server_name,
            vhost_name      => $ip,
            serveraliases   => $server_aliases,
            redirect_status => 'permanent',
            redirect_dest   => "https://${servername}/",
          }
        } else {
          apache::vhost { $name:
            ensure        => $ensure,
            port          => $port,
            docroot       => $doc_root,
            serveradmin   => $admin_email,
            servername    => $server_name,
            vhost_name    => $ip,
            serveraliases => $server_aliases,
          }
        }
      }

      if $sslport {
        apache::vhost { "${name}-ssl":
          ensure        => $ensure,
          port          => $sslport,
          docroot       => $doc_root,
          serveradmin   => $admin_email,
          servername    => $server_name,
          vhost_name    => $ip,
          serveraliases => $server_aliases,
          ssl           => true,
        }
      }
    }
    'deleted': {

      # Remove the MediaWiki instance directory if it is present
      file { "${mediawiki_conf_dir}/${name}":
        ensure  => absent,
        recurse => true,
        purge   => true,
        force   => true,
      }

      # Remove the symlink for the mediawiki instance directory
      file { "${doc_root}/${name}":
        ensure  => absent,
        recurse => true,
      }

      mysql::db { $db_name:
        user     => $db_user,
        password => $db_password,
        host     => 'localhost',
        grant    => ['all'],
        ensure   => 'absent',
      }

      apache::vhost { $name:
        port    => $port,
        docroot => $doc_root,
        ensure  => 'absent',
      }
    }
  }
}
