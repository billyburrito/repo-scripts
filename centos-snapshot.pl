#!/usr/bin/perl

# $Id :$
# $URL :$
# created: 20080118 erinbritz@gmail.com
# purpose: Maintains snapshots of an actively mirrored centos distribution
#          with specified intervals set by the admin.  Also removed snapshots
#          older than the specified interval.
#
# format for serial number:  yyyymmddxx (xx is revision level in the day)
# modifications
#-<serial>------<name>----------<why>---------------------
# 2008011701    britz           initial revision
# 2008022601    britz           fixed mount check, looks at fs path now


use strict;
use Date::Calc "Add_Delta_Days";

use Data::Dumper;

main();

sub _init {

    # init globals here

    # paths
    my $repobase    = "/repo/centos/";
    my $centosbase  = $repobase . "5";     # live centos repo
    my $prodalias   = $repobase . "5prod";   # production snap location
    my $testalias   = $repobase . "5test";  

    # snapshot creation
    my $snap_size       = "4G";             # max diff size of the snap
    my $snap_vol        = "/dev/vg00/";     # volume group we are working in
    my $snap_source     = $snap_vol . "centos-5-live";
    my $snap_interval   = "7";              # interval in days snaps will be done, weekly is recommended 
    my $snap_max        = "3";              # max number of snaps to keep, minimum is 2
    my $snap_prefix     = "centos-5-";      # snaps will have the yyyymmdd added to this

    # binaries used
    my $find        = "/usr/bin/find";
    my $sed         = "/bin/sed";
    my $lvcreate    = "/usr/sbin/lvcreate";
    my $lvremove    = "/usr/sbin/lvremove";
    my $mount       = "/bin/mount";
    my $umount      = "/bin/umount";

    # mounts file
    my $mounts = "/proc/mounts";

    # set to 1 to ignore weekday
    my $skip_check    = 0;

    # END USER CONFIGURABLE OPTIONS

    # call in the date hash
    my $date        = get_date();

    return {
        'repobase'      =>  $repobase,
        'centosbase'    =>  $centosbase,
        'prodalias'     =>  $prodalias,
        'testalias'     =>  $testalias,

        'snap_size'     =>  $snap_size,
        'snap_vol'      =>  $snap_vol,
        'snap_source'   =>  $snap_source,
        'snap_interval' =>  $snap_interval,
        'snap_max'      =>  $snap_max,
        'snap_prefix'   =>  $snap_prefix,

        'find'          =>  $find,
        'sed'           =>  $sed,
        'lvcreate'      =>  $lvcreate,
        'lvremove'      =>  $lvremove,
        'mount'         =>  $mount,
        'umount'        =>  $umount,

        'mounts'        =>  $mounts,

        'date'          =>  $date,
        'skip_check'    =>  $skip_check,
    };

}


sub main {
    
    # start the global object
    my $g = _init();

    # check that we are operating on a sunday 
    # change the 0 to the corresponding day if you cron this for a day other
    # than sunday, set day_lock to 0 above to disable 
    if ( ($g->{date}->{wday} == 0 ) || ( $g->{skip_check} ) ) {

        # create, mount snap
        create_snapshot($g);
        mount_snapshot($g);

        # symlink up aliases 
        symlink_alias($g);
        
        # unmount and remove old snaps
        # by design there should only ever be 1 snapshot to remove
        clean_snapshots($g);
    
        # run changelog for interval

    } else {
        print "I only run on Sundays\n";
    }
}

sub create_snapshot {
    my $g = shift;

    # build our command
    my $lvcreate            = $g->{lvcreate};
    my $lvcreate_options    = "--size " . $g->{snap_size} . " " .   # size of the snap
                              "--snapshot " .                       # tell lvcreate this is a snapshot
                              "--name " . $g->{snap_prefix} .  $g->{date}->{yyyymmdd} . " " .
                                                                    # name the snap
                              $g->{snap_source};                    # our snap source

    # check that it doesnt already exist
    if ( lv_exists($g, $g->{date}->{yyyymmdd}) ) {
        warn ( "warning: logical volume $g->{snap_prefix}$g->{date}->{yyyymmdd} exists, continuing to mount"); 
    } else {
        # create the snapshot
        system ( "$lvcreate $lvcreate_options" );
    }
}

sub mount_snapshot {
    my $g = shift;

    my $mount       = $g->{mount};
    my $mount_args  = $g->{snap_vol} .  $g->{snap_prefix} . $g->{date}->{yyyymmdd} . " " .
                      $g->{repobase} . $g->{snap_prefix} . $g->{date}->{yyyymmdd}; 
   
    # check if the mountpoint exists
    if ( -d $g->{repobase} . $g->{snap_prefix} . $g->{date}->{yyyymmdd} ) {
        warn ("warning: mount point already exists");
    } else {
        # make the mount point and die if it cant create
        mkdir ( $g->{repobase} . $g->{snap_prefix} . $g->{date}->{yyyymmdd}, 755) 
            || die("FATAL: failed to create mount point");
    }

    # check if its mounted, if not, mount it
    if ( lv_mounted($g, $g->{date}->{yyyymmdd}) ) {
        warn ("warning: logical volume $g->{snap_prefix}$g->{date}->{yyyymmdd} is already mounted");
    } else {
        # mount our new snap
        system ( "$mount $mount_args" );

        if ( lv_mounted($g, $g->{date}->{yyyymmdd}) == 0 ) {
            die("FATAL: logical volume $g->{snap_prefix}$g->{date}->{yyyymmdd} was not mounted");
        }
    }
}

sub symlink_alias {
    my $g = shift;

    my @valid_snaps = calc_dates($g);

    # check and unlink current links
    foreach my $alias ($g->{testalias}, $g->{prodalias}) {
        if ( -e $alias) {
            if ( -l $alias ) {
                if ( unlink $alias ) {
                    print "notice: unlinking $alias\n";
                } else {
                    warn ("warning: can not unlink current aliases");
                }
            } else {
                warn ("warning: $alias is not a symlink");
            }
        } else {
            warn ("warning: $alias doesnt exist");
        }

        # link our aliases back up
        my $date = shift @valid_snaps;
        my $source = $g->{repobase} . $g->{snap_prefix} . $date;

        if ( lv_mounted($g, $date) ) {
            if ( symlink ( $source, $alias ) ) {
                print "$alias linked to $source\n";
            } else {
                warn ("warning: failed to symlink $source to $alias");
            }
        } else {
            warn ("warning $source is not mounted, cannot symlink $alias");
        }
    }
}

sub clean_snapshots {
    my $g = shift;

    my $umount   = $g->{umount};
    my $lvremove = $g->{lvremove};

    # get the current intervals
    my @intervals = calc_dates($g);
   
    # calculate the intervals against the max snaps
    my $extra_snaps = ( scalar @intervals ) - $g->{snap_max};

    if ( $extra_snaps ) {
        for my $n (1..$extra_snaps) {
            my $date = pop (@intervals);
            if ( lv_mounted($g, $date) ) {
                my $mount = $g->{repobase} . $g->{snap_prefix} . $date;
                
                # unmount filesystem reference
                system ( "$umount $mount");
                print "notice: unmounted $mount\n";

                if ( lv_mounted($g, $date) ) {
                    warn ("warning: could not unmount $mount");
                } else {
                    # delete snapshot now
                    my $lv = $g->{snap_vol} . $g->{snap_prefix} . $date;
                    system ( "$lvremove -f $lv");
                    
                    if ( lv_exists($g, $date) ) {
                        warn ("warning: lv $lv not removed!!");
                    } else {
                        print "notice: removed LV $lv\n";
                    }

                    # remove mount point directory
                    if ( rmdir $mount ) {
                        print "notice: removed directory $mount\n";
                    } else {
                        warn ("warning: couldnt remove directory $mount");
                    }
                }
            }
        }
    }

}

sub lv_exists {
    # takes the global and a yyyymmdd as arguments
    my $g       = shift;
    my $lv_name = shift;

    if ( -e $g->{snap_vol} . $g->{snap_prefix} . $lv_name ) {
        return 1;
    } else {
        return 0;
    }
}

sub lv_mounted {
    # takes the global and a yyyymmdd as arguments
    my $g       = shift;
    my $lv_name = shift;

    open(MOUNTS, $g->{mounts});
    my @mounts = <MOUNTS>;
    close(MOUNTS);

    my $found = 0;
    my $check = $g->{repobase} . $g->{snap_prefix} . $lv_name;

    foreach my $line (@mounts) {
        if ($line =~ /\ $check\ /) {
            $found++;
        }
    }

    return $found;
}

sub calc_dates{
    # this returns valid dates for today, # of max snaps and 5 more intervals
    # so essentially max_snaps + 6 with today as the first element
    my $g = shift;

    # array to hold valid snaps 
    my @valid_snaps;

    # push the current day on the array first
    push ( @valid_snaps, $g->{date}->{yyyymmdd} );

    # use our snap_interval * snap_max to calc valid snapshots
    for my $n (1..($g->{snap_max} + 5)) {
        my $total_interval = $g->{snap_interval} * $n * (-1);

        my ($year, $month, $day) = Add_Delta_Days( $g->{date}->{year},
                                                   $g->{date}->{mon},
                                                   $g->{date}->{mday},
                                                   $total_interval );
        
        # format dates and push onto array
        push ( @valid_snaps, $year . sprintf("%02d",$month) .  sprintf("%02d",$day) );
    }
    return @valid_snaps;
}


sub get_date {

    my ($sec,   $min,   $hour,
        $mday,  $mon,   $year,
        $wday,  $yday,  $isdst) = localtime(time);

    # return our basic date values into an href
    return {
        'sec'      => sprintf("%02d",$sec),
        'min'      => sprintf("%02d",$min),
        'hour'     => sprintf("%02d",$hour),
        'mday'     => sprintf("%02d",$mday),
        'wday'     => $wday, 
        'mon'      => sprintf("%02d",$mon + 1),
        'year'     => sprintf("%4d",$year + 1900),
        'yyyymmdd' => sprintf("%4d%02d%02d",$year + 1900, $mon + 1, $mday), 
    };
}


