require 'beaker-rspec'
require 'tmpdir'
require 'simp/beaker_helpers'
include Simp::BeakerHelpers

unless ENV['BEAKER_provision'] == 'no'
  hosts.each do |host|
    # Install Puppet
    if host.is_pe?
      install_pe
    else
      install_puppet
    end
  end
end

# FIXME: move into simp-beaker-helpers after verified
def fix_more_errata_on( suts = hosts )
  unless ENV['BEAKER_fips'] == 'no'
    puts '== configuring FIPS mode on SUTs'
    puts '  -- (use BEAKER_fips=no to disable)'
    suts.each do |sut|
      # Set up for FIPS
      if fact_on(sut, 'osfamily') == 'RedHat'
        pp = <<-EOS
          package { ['grubby'] : ensure => 'latest' }
          ~>
          exec{ 'setup_fips':
            command     => '/bin/bash /root/setup_fips.sh',
            refreshonly => true,
          }

          file{ '/root/setup_fips.sh':
            ensure  => 'file',
            owner   => 'root',
            group   => 'root',
            mode    => '0700',
            content => "#!/bin/bash

# FIPS
if [ -e /sys/firmware/efi ]; then
  BOOTDEV=`df /boot/efi | tail -1 | cut -f1 -d' '`
else
  BOOTDEV=`df /boot | tail -1 | cut -f1 -d' '`
fi
# In case you need a working fallback
DEFAULT_KERNEL_INFO=`/sbin/grubby --default-kernel`
DEFAULT_INITRD=`/sbin/grubby --info=\\\${DEFAULT_KERNEL_INFO} | grep initrd | cut -f2 -d'='`
DEFAULT_KERNEL_TITLE=`/sbin/grubby --info=\\\${DEFAULT_KERNEL_INFO} | grep -m1 title | cut -f2 -d'='`
/sbin/grubby --copy-default --make-default --args=\\\"boot=\\\${BOOTDEV} fips=1\\\" --add-kernel=`/sbin/grubby --default-kernel` --initrd=\\\${DEFAULT_INITRD} --title=\\\"FIPS \\\${DEFAULT_KERNEL_TITLE}\\\"
",
            notify => Exec['setup_fips']
          }
        EOS
        apply_manifest_on(sut, pp, :catch_failures => false)
        on( sut, 'shutdown -r now', { :expect_connection_failure => true } )
      end
    end
  end
end

RSpec.configure do |c|
  # ensure that environment OS is ready on each host
  fix_errata_on hosts
  fix_more_errata_on hosts # FIXME: remove

  # Readable test descriptions
  c.formatter = :documentation

  # Configure all nodes in nodeset
  c.before :suite do
    begin
      # Install modules and dependencies from spec/fixtures/modules
      copy_fixture_modules_to( hosts )
      Dir.mktmpdir do |cert_dir|
        run_fake_pki_ca_on( default, hosts, cert_dir )
        hosts.each{ |host| copy_pki_to( host, cert_dir, '/etc/pki/simp-testing' )}
      end
    rescue StandardError, ScriptError => e
      require 'pry'; binding.pry if ENV['PRY']
    end
  end
end
