#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More;

use File::Temp qw(tempdir);
use Test::FakeSendmail;

my $tests_per_sender = 11;
my @senders = ('direct_sendmail', 'MIME::Lite', 'Email::Sender');

plan tests => 2 * (3 + $tests_per_sender*@senders);

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

    for my $sender (@senders) {
    SKIP: {
	    skip "$sender not available", $tests_per_sender
		if ($sender =~ m{^(MIME::Lite|Email::Sender)$} && !eval qq{ require $sender; 1 });
	    skip "Email::Simple not available", $tests_per_sender
		if ($sender eq 'Email::Sender' && !eval q{ require Email::Simple; 1 }); # actually this is a dep of Email::Sender, so usually installed
	    skip "list form of pipe open not implemented for perl < 5.22.0 on Windows", $tests_per_sender
		if ($sender eq 'direct_sendmail' && $^O eq 'MSWin32' && $] < 5.022);

	    my $tfsm = Test::FakeSendmail->new(defined $maildirectory ? (maildirectory => $maildirectory) : ());
	    if ($mode eq 'env') {
		ok $ENV{PERL_TEST_FAKESENDMAIL_DIRECTORY}, 'PERL_TEST_FAKESENDMAIL_DIRECTORY env var is set';
		ok -d $ENV{PERL_TEST_FAKESENDMAIL_DIRECTORY}, '... and points to a directory';
	    } else {
		ok !$ENV{PERL_TEST_FAKESENDMAIL_DIRECTORY}, 'PERL_TEST_FAKESENDMAIL_DIRECTORY env var is not set';
		pass '... and no point in checking non-existing contents';
	    }
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
	    } elsif ($sender eq 'Email::Sender') {
		my $message = Email::Simple->create
		    (
		     header => [
				From => 'me',
				To => 'somebody',
				Subject => 'Hello',
			       ],
		     body => "Body\n",
		    );
		require Email::Sender::Simple;
		require Email::Sender::Transport::Sendmail;
		Email::Sender::Simple->send
			(
			 $message,
			 {
			  transport => Email::Sender::Transport::Sendmail->new({ sendmail => $fake_sendmail_path }),
			  to        => scalar $message->header('to'), # XXX automatic get does not work
			  from      => scalar $message->header('from'), # XXX automatic get does not work
			 }
			);
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
	    if ($sender eq 'Email::Sender') {
		like $mails[0]->argv, qr{^-i -f me (-- )?somebody$};
	    } else {
		is $mails[0]->argv, '-t -oi -oem -fme';
	    }

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
