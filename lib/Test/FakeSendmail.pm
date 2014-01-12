# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2014 Slaven Rezic. All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

package Test::FakeSendmail;

use strict;
use vars qw($VERSION);
$VERSION = '0.01';

use File::Spec qw();
use File::Temp qw(tempdir tempfile);

for my $member (qw(maildirectory)) {
    my $sub = sub {
	my $self = shift;
	if (@_) { $self->{$member} = $_[0] }
	$self->{$member};
    };
    no strict 'refs';
    *{$member} = $sub;
}

sub new {
    my($class, %opts) = @_;
    my $maildirectory = delete $opts{maildirectory};
    die "Unhandled options: " . join(" ", %opts) if %opts;

    my $self = bless {}, $class;
    if (defined $maildirectory) {
	$self->maildirectory($maildirectory);
    } else {
	my($tempdir) = tempdir(TMPDIR => 1, CLEANUP => 1)
	    or die "Can't create temporary directory: $!";
	$self->maildirectory($tempdir);
	$ENV{PERL_TEST_FAKESENDMAIL_DIRECTORY} = $tempdir;
    }
    $self;
}

sub _iterate_over_mails {
    my($self, $cb, %opts) = @_;

    my $maildirectory = $opts{maildirectory};
    if (!defined $maildirectory) {
	if (!ref $self) {
	    die "Please provide maildirectory option";
	}
	$maildirectory = $self->maildirectory;
    }

    opendir my $dirh, $maildirectory
	or die "Can't open directory <$maildirectory>: $!";
    while(my $entry = readdir($dirh)) {
	next if $entry eq '.' || $entry eq '..';
	my $file = File::Spec->catfile($maildirectory, $entry);
	if ($file =~ m{(.*)\.info$}) {
	    $cb->(file => $1);
	}
    }
    closedir $dirh;
}

sub mails {
    my($self, %opts) = @_;
    require Test::FakeSendmail::Mail;
    my @mails;
    $self->_iterate_over_mails
	(sub {
	     my(%cb_opts) = @_;
	     push @mails, Test::FakeSendmail::Mail->new(file => $cb_opts{file});
	 }, %opts); 
    @mails;
}

sub clean {
    my($self, %opts) = @_;
    $self->_iterate_over_mails
	(sub {
	     my(%cb_opts) = @_;
	     for my $file ("$cb_opts{file}.info", "$cb_opts{file}.content") {
		 unlink $file
		     or warn "Unlinking $file failed: $!";
	     }
	 }, %opts);
}

sub install {
    my(undef, %opts) = @_;

    my $destination = "/usr/sbin/sendmail"; # XXX get best destination per OS, could be /usr/lib/sendmail
    if ($opts{path}) {
	$destination = delete $opts{path};
    } elsif (delete $opts{tmp}) {
	my($tmpfh,$tmpfile) = tempfile(SUFFIX => "_test_fake_sendmail", UNLINK => 1)
	    or die "Can't create temporary file: $!";
	close $tmpfh; # to prevent "text file busy" errors
	$destination = $tmpfile;
    }
    my $maildirectory = delete $opts{maildirectory};

    die "Unhandled options: " . join(" ", %opts) if %opts;

    my $test_fake_sendmail_script;
    # Are we in test (blib) mode?
    if ($INC{"Test/FakeSendmail.pm"} =~ m{(.*/blib)/lib/}) { # XXX use file::spec?
	$test_fake_sendmail_script = "$1/script/test-fake-sendmail";
	if (!-x $test_fake_sendmail_script) { # XXX is this also valid for MSWin32?
	    undef $test_fake_sendmail_script;
	}
    }
    if (!$test_fake_sendmail_script) {
	require Config;
	$test_fake_sendmail_script = File::Spec->catfile($Config::Config{sitebin}, 'test-fake-sendmail');
    }
    if (!-x $test_fake_sendmail_script) {
	die "Cannot find executable $test_fake_sendmail_script";
	# XXX what on Windows?
    }

    if (defined $maildirectory) {
	open my $fh, "<", $test_fake_sendmail_script
	    or die "Can't open $test_fake_sendmail_script: $!";
	my $tmp_destination = "$destination.$$";
	open my $ofh, ">", $tmp_destination
	    or die "Can't write to $tmp_destination: $!";
	my $replaced = 0;
	while(<$fh>) {
	    if (m{^my \$mail_directory;}) {
		if ($replaced) {
		    die "Should not happen: \$mail_directory was already replaced. Please check $test_fake_sendmail_script";
		}
		s{^(my \$mail_directory)}{$1 = '$maildirectory'}; # XXX escaping?
		$replaced = 1;
	    }
	    print $ofh $_;
	}
	if (!$replaced) {
	    die "Should not happen: line for replacing \$mail_directory could not be found. Please check $test_fake_sendmail_script";
	}
	close $ofh
	    or die "Failure while writing to $tmp_destination: $!";
	rename $tmp_destination, $destination
	    or die "Cannot rename $tmp_destination to $destination: $!";
    } else {
	require File::Copy;
	File::Copy::cp($test_fake_sendmail_script, $destination);
    }
    chmod 0755, $destination;

    $destination;
}


1;

__END__
