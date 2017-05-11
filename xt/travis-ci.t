#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use Test::More 'no_plan';

use Test::FakeSendmail;
use MIME::Parser;

die "This test script should only be run on travis-ci systems.\n"
    if !$ENV{TRAVIS};

system("sudo", $^X, "-Mblib", "-MTest::FakeSendmail", "-e", "Test::FakeSendmail->install");
die "Cannot install fake sendmail" if $? != 0;

# Require late, because MIME::Lite checks for a sendmail binary in the
# compile phase.
require MIME::Lite;

my $tfsm = Test::FakeSendmail->new;

my $sender = 'MIME::Lite';
my $msg = MIME::Lite->new
    (
     From => 'me',
     To => 'somebody',
     Subject => 'Hello',
     Data => "Body\n",
    );
$msg->send('sendmail');

my @mails = $tfsm->mails;
is @mails, 1, "Got one mail through sender '$sender'";

like $mails[0]->received, qr{^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$}, 'received info field looks like an ISO date';

my $parser = MIME::Parser->new;
$parser->output_to_core(1);
my $mail = $parser->parse_open($mails[0]->content_file);
isa_ok $mail, 'MIME::Entity';
is _get_header($mail, 'From'), 'me';
is _get_header($mail, 'To'), 'somebody';
is _get_header($mail, 'Subject'), 'Hello';
is $mail->body_as_string, "Body\n";

$tfsm->clean;

sub _get_header {
    my($mail, $key) = @_;
    chomp(my $val = $mail->head->get($key));
    $val;
}

__END__
