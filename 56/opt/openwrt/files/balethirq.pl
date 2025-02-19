#!/usr/bin/perl

use strict;
our %irq_map;
our %cpu_map;
our $all_cpu_mask = 0;

&read_config();
&read_irq_data();
&update_smp_affinity();
&tunning_eth_params();
exit(0);

############################## sub functions #########################
sub read_config {
    my $cpu_count = &get_cpu_count();
    my $fh;
    my $config_file = "/etc/config/balance_irq";
    if( -f $config_file) {
    	open $fh, "<", $config_file or die $!;
    	while(<$fh>) {
		chomp;
		my($name, $value) = split;
		my @cpus = split(',', $value);

		foreach my $cpu (@cpus) {
		    if($cpu > $cpu_count) {
			$cpu = $cpu_count;	
		    } elsif($cpu < 1) {
			$cpu = 1;
		    }
		}

		$cpu_map{$name} = \@cpus;
	}	
    	close $fh;
    } 
}

sub get_cpu_count {
    my $fh;
    open $fh, "<", "/proc/cpuinfo" or die $!;
    my $count=0;
    while(<$fh>) {
	    chomp;
	    my @ary = split;
	    if($ary[0] eq "processor") {
		    $count++;
		    $all_cpu_mask += 1<<($count-1);
	    }
    }
    close $fh;
    $all_cpu_mask = sprintf("%0x", $all_cpu_mask);
    return $count;
}

sub read_irq_data {
    my $fh;
    open $fh, "<", "/proc/interrupts" or die $!;
    while(<$fh>) {
	    chomp;
	    my @raw = split;
	    my $irq = $raw[0];
  	    $irq =~ s/://;
	    my $name = $raw[-1];

	    if(exists $cpu_map{$name}) {
		$irq_map{$name} = $irq;
	    }
    }
    close $fh;
}

sub update_smp_affinity {
    for my $key (sort keys %irq_map) {
    	my $fh;
	my $irq = $irq_map{$key};
	my $cpus_ref = $cpu_map{$key};
	my $mask = 0;
	foreach my $cpu (@$cpus_ref) {
	    $mask += 1 << ($cpu-1);
	}
	my $smp_affinity = sprintf("%0x", $mask);
    	open $fh, ">", "/proc/irq/$irq/smp_affinity" or die $!;
	print "irq name:$key, irq:$irq, affinity: $smp_affinity\n";
	print $fh "$smp_affinity\n";
    	close $fh;
    }
}

sub tunning_eth_params {
    my $rps_sock_flow_entries = 0;
    for my $eth ("eth0","eth1") {
	my $cur_rx;
        if(-d "/sys/class/net/${eth}/queues/rx-0") {
	    system "/usr/sbin/ethtool -g ${eth} >/dev/null 2>&1";
	    if($? == 0) {
	        my $max_rx  = `/usr/sbin/ethtool -g ${eth} | grep -A4 'Pre-set maximums:' | awk '\$1~/RX:/ {print \$2}'`;
	        my $max_tx  = `/usr/sbin/ethtool -g ${eth} | grep -A4 'Pre-set maximums:' | awk '\$1~/TX:/ {print \$2}'`;
                system "ethtool -G ${eth} rx ${max_rx} >/dev/null 2>&1";
                system "ethtool -G ${eth} tx ${max_tx} >/dev/null 2>&1";
                $rps_sock_flow_entries += $max_rx;
		$cur_rx = $max_rx;
	    } else {
                $rps_sock_flow_entries += 4096;
		$cur_rx = 4096;
	    }
	    open my $fh, ">", "/sys/class/net/${eth}/queues/rx-0/rps_cpus" or die;
	    print $fh $all_cpu_mask;
	    close $fh;
	    open my $fh, ">", "/sys/class/net/${eth}/queues/tx-0/xps_cpus" or die;
	    print $fh $all_cpu_mask;
	    close $fh;
	    open $fh, ">", "/sys/class/net/${eth}/queues/rx-0/rps_flow_cnt" or die;
	    print $fh $cur_rx;
	    close $fh;
        }
    }
    open my $fh, ">", "/proc/sys/net/core/rps_sock_flow_entries" or die;
    print $fh $rps_sock_flow_entries;
    close $fh;
}

