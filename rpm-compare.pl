#!/usr/bin/perl


use strict;
use Data::Dumper;
use Getopt::Long;
use Sys::Hostname;
use File::Glob;


main();

# init globals vars and objects 
sub _init {

    # binary locations
    my $rpm = '/bin/rpm';
    my $rpm_opts = q[ -qa --queryformat "%{name}\|%{version}\|%{release}\|%{arch}\|%{sigmd5}\|%{installtime}\|%{group}\|\|"];

    my $ssh = '/usr/bin/ssh';
    my $cat = '/bin/cat';
    
    my $hostname = hostname();
    #$hostname =~ s/^([\w]+)\..*/$1/g; # uncomment for shorter hostnames
    
    return {
        'rpm'      => $rpm,
        'rpm_opts' => $rpm_opts,
        'ssh'      => $ssh,
        'cat'      => $cat,
        'hostname' => $hostname,
    };
}


sub main {

    my $g = _init();

    # get options
    get_options($g);
    
    # process local if requested
    if ($g->{opts}->{local}) {
        process_local($g);
    }
    
    # process remote hosts from options
    if ($g->{opts}->{host}) {
        process_remote($g);
    }

    # process remote hosts from options
    if ($g->{opts}->{files}) {
        process_files($g);
    }

    print Dumper $g;
}

sub process_local {
    my $g     =  shift;

    my $output = qx/$g->{rpm} $g->{rpm_opts}/;

    process_rpm_data($g, $g->{hostname}, $output);
}

sub process_files {
    my $g     = shift;

    my $glob_expr = "$g->{opts}->{directory}/*.$g->{opts}->{extension}";

    my @files = glob($glob_expr);

    print Dumper @files;

    for my $file ( @files ) {

        print "Processing $file";

        my $output = qx/$g->{cat} $file/;

        # files should be named with the fqdn of the host 
        $file =~ s/$g->{opts}->{directory}\/(.*)\.$g->{opts}->{extension}/$1/g;
   
        process_rpm_data($g, $file, $output);
    }
}

sub process_remote {
    my $g     =  shift;
    my $hosts = $g->{opts}->{host};

    for my $address ( @{$hosts} ) {

        my ($user, $server) = split /\@/, $address;

        print "Logging into session $address\n";
        my $output = qx/$g->{ssh} $address $g->{rpm} $g->{rpm_opts}/;
   
        process_rpm_data($g, $server, $output);
    }
}

sub process_rpm_data {
    my $g = shift;
    my $server = shift;
    my $data = shift;

    # init the array at a higher scope than the if statements
    my @lines;

    # split on line terminators
    # check if we are seperated using || or \n
    if ($data =~ /\|\|$/) {
       @lines = split /\|\|/, $data;
    } else {
       @lines = split /\n/, $data;
    }

    for my $line (@lines) {
        my ($name, $version, $release, $arch, $sigmd5, $installtime, $group) = split /\|/, $line;

        $g->{rpm_data}->{$server}->{$group}->{$name}->{version} = $version; 
        $g->{rpm_data}->{$server}->{$group}->{$name}->{release} = $release; 
        $g->{rpm_data}->{$server}->{$group}->{$name}->{arch}    = $arch; 
        $g->{rpm_data}->{$server}->{$group}->{$name}->{sigmd5}  = $sigmd5; 
        $g->{rpm_data}->{$server}->{$group}->{$name}->{installtime} = $installtime; 
    } 
}

sub get_options {
    my $g = shift;
    my $hosts;

    my @options =    ( 'host=s@',
                       'local',
                       'help',
                       'files',
                       'directory=s',
                       'extension=s',
                     );  
    
    # anon hash for options
    my $opts;

    GetOptions( \%$opts, @options );

    # set defaults for file search if not specified
    if (!( $opts->{directory} )) {
        $opts->{directory} = '.';
    }
    
    if (!( $opts->{extension} )) {
        $opts->{extension} = 'rpmout';
    }

    # help/usage
    if ($opts->{help}) {
        print_usage($g);
        exit();
    }

    # put the options hash into the global
    $g->{opts} = $opts;
}
