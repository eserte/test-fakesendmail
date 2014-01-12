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

package Test::FakeSendmail::Mail;

use strict;
use vars qw($VERSION);
$VERSION = '0.01';

sub new {
    my($class, %opts) = @_;
    my $file = delete $opts{file} || die "file option is missing";
    die "Unhandled options: " . join(" ", %opts) if %opts;
    my $self = bless { file => $file }, $class;
    $self;
}

sub _get_info {
    my($self, $key) = @_;
    if (!exists $self->{info}) {
	my %info;
	my $info_file = $self->{file} . ".info";
	open my $fh, $info_file
	    or die "Can't open $info_file: $!";
	while(<$fh>) {
	    chomp;
	    my($k,$v) = split /=/, $_, 2;
	    $info{$k} = $v;
	}
	$self->{info} = \%info;
    }
    $self->{info}->{$key};
}

sub received {
    my $self = shift;
    $self->_get_info('received');
}

sub content {
    my $self = shift;
    my $content_file = $self->content_file;
    open my $fh, $content_file
	or die "Can't open $content_file: $!";
    return do {
	local $/;
	<$fh>;
    };
}

sub content_file {
    my $self = shift;
    return $self->{file} . ".content";
}

1;

__END__
