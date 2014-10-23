#!/usr/bin/env perl

use strict;
use warnings;

=head1 NAME

iprtbl.pl

=head1 ABSTRACT

A script to get the MIB-2 ipCidrRouteTable information from devices supporting the MIBs.

=head1 SYNOPSIS

 ip_cidr_rtbl.pl OPTIONS agent agent ...

 ip_cidr_rtbl.pl OPTIONS -i <agents.txt

=head2 OPTIONS

  -c snmp_community
  -v snmp_version
  -t snmp_timeout
  -r snmp_retries

  -d			Net::SNMP debug on
  -i			read agents from stdin, one agent per line
  -B			nonblocking

=cut

use blib;
use Net::SNMP qw(:debug :snmp);
use Net::SNMP::Mixin;

use Getopt::Std;

my %opts;
getopts( 'iBdt:r:c:v:', \%opts ) or usage();

my $debug       = $opts{d} || undef;
my $community   = $opts{c} || 'public';
my $version     = $opts{v} || '2';
my $nonblocking = $opts{B} || 0;
my $timeout     = $opts{t} || 5;
my $retries     = $opts{t} || 0;

my $from_stdin = $opts{i} || undef;

my @agents = @ARGV;
push @agents, <STDIN> if $from_stdin;
chomp @agents;
usage('missing agents') unless @agents;

my @sessions;
foreach my $agent ( sort @agents ) {
    my ( $session, $error ) = Net::SNMP->session(
        -community   => $community,
        -hostname    => $agent,
        -version     => $version,
        -nonblocking => $nonblocking,
        -timeout     => $timeout,
        -retries     => $retries,
        -debug       => $debug ? DEBUG_ALL : 0,
    );

    if ($error) {
        warn $error;
        next;
    }

    $session->mixer(qw/ Net::SNMP::Mixin::IpCidrRouteTable /);

    $session->init_mixins;
    push @sessions, $session;

}
snmp_dispatcher();

# warn on errors during initialization
foreach my $session (@sessions) {
    if ( $session->errors ) {
        foreach my $error ( $session->errors ) {
            warn $session->hostname . ": $error\n";
        }
    }
}

# remove sessions with errors from the sessions list
@sessions = grep { not $_->errors(1) } @sessions;

foreach my $session ( sort { $a->hostname cmp $b->hostname } @sessions ) {
    print_ip_cidr_rtbl($session);
}

exit 0;

###################### end of main ######################

sub print_ip_cidr_rtbl {
    my $session = shift;

    print "\n";
    printf "Hostname: %-15.15s\n", $session->hostname;

    print '-' x 66, "\n";
    printf "%-18s => %-15s %8s %10s %8s\n", 'Route', 'NextHop',
      'Proto', 'Type', 'Metric1';
    print '-' x 66, "\n";

    my @routes = $session->get_ip_cidr_route_table();

    foreach my $route (@routes) {
        my $dest      = $route->{ipCidrRouteDest};
        my $mask      = $route->{ipCidrRouteMask};
        my $bits      = mk_bits($mask);
        my $nhop      = $route->{ipCidrRouteNextHop};
        my $proto_str = $route->{ipCidrRouteProtoString};
        my $type_str  = $route->{ipCidrRouteTypeString};
        my $metric1   = $route->{ipCidrRouteMetric1};

        printf "%-18s => %-15s %8s %10s %8s\n", "$dest/$bits", $nhop,
          $proto_str, $type_str, $metric1;
    }
}

# convert IPv4 netmasks into cidr notation, eg: '255.255.255.0' => 24
sub mk_bits {

    # sorry, highly condensed code, write once read never
    return unpack( '%B*', pack( 'C4', split( /\./, shift ) ) );
}

sub usage {
    my @msg = @_;
    die <<EOT;
>>>>>> @msg
    Usage: $0 [options] hostname
   
    	-c community
  	-v version
  	-t timeout
  	-r retries
  	-d		Net::SNMP debug on
	-i		read agents from stdin
  	-B		nonblocking
EOT
}

=head1 AUTHOR

Karl Gaissmaier, karl.gaissmaier (at) uni-ulm.de

=head1 COPYRIGHT

Copyright (C) 2011 by Karl Gaissmaier

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

# vim: sw=2
