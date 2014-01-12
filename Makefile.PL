use strict;
use ExtUtils::MakeMaker;

my $is_devel_host = defined $ENV{USER} && $ENV{USER} eq 'eserte' && $^O =~ /bsd/i && -f "../../perl.release.mk";
my $eumm_recent_enough = $ExtUtils::MakeMaker::VERSION >= 6.54;

if (!$eumm_recent_enough) {
    *MY::dist_core = sub {
	<<'EOF';
dist :
	$(NOECHO) $(ECHO) "Sorry, use a newer EUMM!"

EOF
    };
}

WriteMakefile(
    NAME         => 'Test::FakeSendmail',
    VERSION_FROM => 'lib/Test/FakeSendmail.pm',
    EXE_FILES    => ['scripts/test-fake-sendmail'],
    AUTHOR       => 'Slaven Rezic <srezic@cpan.org>',
    ABSTRACT_FROM       => 'lib/Test/FakeSendmail.pm',
    ($eumm_recent_enough ?
	(META_ADD => { resources => { repository => 'git://github.com/eserte/test-fakesendmail.git' } }) : ()),
);

sub MY::postamble {
    my $postamble = '';

    if ($is_devel_host) {
	$postamble .= <<'EOF';

.include "../../perl.release.mk"
.include "../../perl.git.mk"

EOF
    }

    $postamble;
}
