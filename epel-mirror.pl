#!/usr/bin/perl

use strict;

my $http_proxy = "http://proxy.gateway.biz.com:80/";
my $proxy_user = 'proxyuser';
my $proxy_pass = 'password';

#my $mirror_host = "http://www.gtlib.gatech.edu";
my $mirror_host = "http://download.fedora.redhat.com";
my $mirror_path = "/pub/epel/5/";
my $key_path    = "/pub/epel/RPM-GPG-KEY-EPEL";

my $local_path  = "/repo/epel/";
my $release     = "5";

my $wget         = "/usr/bin/wget";
my $wget_options = "--proxy=on " .                           # tells wget to use the proxy  
                   "--proxy-user=" . $proxy_user . " " .     # proxy username
                   "--proxy-password='" . $proxy_pass . "' " . # proxy password
                   "-m " .                                   # operate in mirror mode
                   "-x " .                                   # force creation of directories
                   '-np ' .
                   '--exclude-directories / ' .                  # extensions to ignore
                   "--include-directories " . $mirror_path . "i386," .  $mirror_path. "x86_64 " .                  # extensions to ignore
                   "--no-host-directories " .                # we dont want the hostname directory
                   "--cut-dirs=2 " .                         # levels of path to remove off the front
                   $mirror_host . $mirror_path;              # the host and path we are mirroring

my $proxy_options = "--proxy=on " .                           # tells wget to use the proxy  
                   "--proxy-user=" . $proxy_user . " " .     # proxy username
                   "--proxy-password='" . $proxy_pass . "' ";  # proxy password

my @arch_types = ('i386', 'x86_64');
my @repo_files = ('repomd.xml', 'other.xml.gz', 'other.sqlite.bz2', 'filelists.xml.gz', 'filelists.sqlite.bz2',
	'primary.xml.gz', 'primary.sqlite.bz2', 'comps.xml');

# End variables

# set the http_proxy env variable
$ENV{'http_proxy'} = $http_proxy;


# process the main archive
print "Mirroring: $mirror_host$mirror_path \nlocally to: $local_path\n";
system("cd $local_path; $wget $wget_options");

# grab the EPEL PGP key..
system("cd $local_path; $wget -N $proxy_options $mirror_host$key_path");

# grab the repodata/* files so we dont have to generate our own
for my $arch (@arch_types) {
     for my $file (@repo_files) {
           system("cd $local_path/$release/$arch/repodata; $wget -N $proxy_options $mirror_host$mirror_path$arch/repodata/$file");
     }
#     system("cd $local_path/$release/$arch/repodata; $wget -N $proxy_options $mirror_host$mirror_path$arch/repodata/repomd.xml");
#     system("cd $local_path/$release/$arch/repodata; $wget -N $proxy_options $mirror_host$mirror_path$arch/repodata/other.xml.gz");
#     system("cd $local_path/$release/$arch/repodata; $wget -N $proxy_options $mirror_host$mirror_path$arch/repodata/other.sqlite.bz2");
#     system("cd $local_path/$release/$arch/repodata; $wget -N $proxy_options $mirror_host$mirror_path$arch/repodata/filelists.xml.gz");
#     system("cd $local_path/$release/$arch/repodata; $wget -N $proxy_options $mirror_host$mirror_path$arch/repodata/filelists.sqlite.bz2");
#     system("cd $local_path/$release/$arch/repodata; $wget -N $proxy_options $mirror_host$mirror_path$arch/repodata/primary.xml.gz");
#     system("cd $local_path/$release/$arch/repodata; $wget -N $proxy_options $mirror_host$mirror_path$arch/repodata/primary.sqlite.bz2");
#     system("cd $local_path/$release/$arch/repodata; $wget -N $proxy_options $mirror_host$mirror_path$arch/repodata/comps.xml");
}
