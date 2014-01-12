#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

use File::Temp qw(tempdir);
use Test::FakeSendmail;

my $tests_per_sender = 9;

plan tests => 2 * (3 + $tests_per_sender*2);

for my $mode ('env', 'fixed_dir') {
    delete $ENV{PERL_TEST_FAKESENDMAIL_DIRECTORY};
    my $fake_sendmail_path;
    my $maildirectory;
    my $info;
    my $get_info = sub {
	chomp($info = `$fake_sendmail_path --tfsm-info`);
    };
    if ($mode eq 'env') {
	$fake_sendmail_path = Test::FakeSendmail->install(tmp => 1);
	$get_info->();
	like $info, qr{mail_directory: <undef>}, 'environment variable mode, no fixed mail directory';
    } elsif ($mode eq 'fixed_dir') {
	$maildirectory = tempdir(CLEANUP => 1, TMPDIR => 1)
	    or die $!;
	$fake_sendmail_path = Test::FakeSendmail->install(tmp => 1, maildirectory => $maildirectory);
	$get_info->();
	like $info, qr{mail_directory: \Q$maildirectory}, 'fixed mail directory';
    } else {
	die "Unknown mode '$mode'";
    }
    cmp_ok -s $fake_sendmail_path, ">", 0;
    like $info, qr{test-fake-sendmail\s+\d+\.\d+}, 'seen version';

    for my $sender ('direct_sendmail', 'MIME::Lite') {
    SKIP: {
	    skip "MIME::Lite not available", $tests_per_sender
		if ($sender eq 'MIME::Lite' && !eval { require MIME::Lite; 1 });
	    skip "list form of pipe open not implemented", $tests_per_sender
		if ($sender eq 'direct_sendmail' && $^O eq 'MSWin32');

	    my $tfsm = Test::FakeSendmail->new(defined $maildirectory ? (maildirectory => $maildirectory) : ());
	    isa_ok $tfsm, 'Test::FakeSendmail';


	    if ($sender eq 'direct_sendmail') {
		open my $fh, "|-", $fake_sendmail_path, "-t", "-oi", "-oem", "-fme" or die $!;
		print $fh <<EOF;
From: me
To: somebody
Subject: Hello

Body
EOF
		close $fh or die $!;
	    } elsif ($sender eq 'MIME::Lite') {
		my $msg = MIME::Lite->new
		    (
		     From => 'me',
		     To => 'somebody',
		     Subject => 'Hello',
		     Data => "Body\n",
		    );
		$msg->send('sendmail', "$fake_sendmail_path -t -oi -oem -fme");
	    } else {
		die "No support for sender '$sender'";
	    }

	    my @mails = $tfsm->mails;
	    is @mails, 1, "Got one mail through sender '$sender'"
		or do {
		    my $content = `"$fake_sendmail_path" --tfsm-queue`;
		    diag $content;
		};

	    like $mails[0]->received, qr{^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$}, 'received info field looks like an ISO date';
	    is $mails[0]->argv, '-t -oi -oem -fme';

	SKIP: {
		skip "No MIME::Parser available", 5
		    if !eval { require MIME::Parser; 1 };
		my $parser = MIME::Parser->new;
		$parser->output_to_core(1);
		my $mail = $parser->parse_open($mails[0]->content_file);
		isa_ok $mail, 'MIME::Entity';
		is _get_header($mail, 'From'), 'me';
		is _get_header($mail, 'To'), 'somebody';
		is _get_header($mail, 'Subject'), 'Hello';
		is $mail->body_as_string, "Body\n";
	    }

	    $tfsm->clean;
	}
    }
}

sub _get_header {
    my($mail, $key) = @_;
    chomp(my $val = $mail->head->get($key));
    $val;
}

__END__
