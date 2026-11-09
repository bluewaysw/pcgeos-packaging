#!/usr/bin/env perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;

# Run with: perl Tests/version.pl
my $root = "$FindBin::Bin/..";
my $tmp = tempdir(CLEANUP => 1);
open my $source, '<', "$root/pack-ensemble.sh" or die $!;
my $script = do { local $/; <$source> };
close $source;
# Run the real packaging stage without downloads or archive creation.
my $entry = 'STAGED_ENSEMBLE_DIR="$1"' . "\n" .
    'DETECTED_BASEBOX_BUILD_NAME="$2"' . "\nadd_basebox_version\n";
$script =~ s/\nmain "\$\@"\n\z/\n$entry/ or die "Cannot find entry point\n";
open my $runner, '>', "$tmp/check.sh" or die $!;
print $runner $script;
close $runner;
local $ENV{PACK_ENSEMBLE_CONFIG} = "$root/pack-ensemble.conf";

for my $case ('normal', 'missing', 'ambiguous', 'bad-build') {
    my $stage = "$tmp/$case with spaces/ENSEMBLE";
    my $payload = "$stage/FREEGEOS/BLD1614/SETUP/ACTIVATE";
    make_path($payload);
    my $original = "PC/GEOS Ensemble\r\nPC/GEOS Build 1614\r\n";
    if ($case ne 'missing') {
        open my $file, '>:raw', "$payload/VERSION.TXT" or die $!;
        print $file $original;
        close $file;
    }
    if ($case eq 'ambiguous') {
        my $other = "$stage/FREEGEOS/BLD1615/SETUP/ACTIVATE";
        make_path($other);
        open my $file, '>:raw', "$other/VERSION.TXT" or die $!;
        print $file $original;
        close $file;
    }
    my $build = $case eq 'bad-build' ? 'BLDinvalid' : 'BLD285';
    open my $pipe, '-|', 'bash', "$tmp/check.sh", $stage, $build or die $!;
    my $log = do { local $/; <$pipe> };
    my $ok = close $pipe;
    if ($case eq 'normal') {
        $ok or die $log;
    } else {
        !$ok or die "Accepted $case payload\n";
    }
    if ($case ne 'missing') {
        open my $file, '<:raw', "$payload/VERSION.TXT" or die $!;
        my $version = do { local $/; <$file> };
        close $file;
        my $expected = $original;
        $expected .= "Basebox Build 285\r\n" if $case eq 'normal';
        $version eq $expected or die "Wrong $case version text: $version\n";
    }
    print "PASS: $case packaging payload\n";
}
