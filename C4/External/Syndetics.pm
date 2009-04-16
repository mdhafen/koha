package C4::External::Syndetics;
# Copyright (C) 2006 LibLime
# <jmf at liblime dot com>
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# Koha; if not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307 USA

use XML::Simple;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common;

use strict;
use warnings;

use vars qw($VERSION @ISA @EXPORT);

BEGIN {
    require Exporter;
    $VERSION = 0.03;
    @ISA = qw(Exporter);
    @EXPORT = qw(
        &get_syndetics_summary
        &get_syndetics_toc
    );
}

=head1 NAME

C4::External::Syndetics - Functions for retrieving Syndetics content in Koha

=head1 FUNCTIONS

This module provides facilities for retrieving Syndetics.com content in Koha

=head2 get_syndetics_summary

=over 4

my $syndetics_summary= &get_syndetics_summary( $xisbn );

=back

Get Summary data from Syndetics

=cut

sub get_syndetics_summary {
    my ( $isbn ) = @_;

    #normalize the ISBN
    $isbn = _normalize_match_point ($isbn);

    # grab the AWSAccessKeyId: mine is '0V5RRRRJZ3HR2RQFNHR2'
    my $syndetics_client_code = C4::Context->preference('SyndeticsClientCode');

    my $url = "http://syndetics.com/index.aspx?isbn=$isbn/SUMMARY.XML&client=$syndetics_client_code&type=xw10";
    warn $url;
    my $content = get($url);
    warn "could not retrieve $url" unless $content;
    my $xmlsimple = XML::Simple->new();
    my $response = $xmlsimple->XMLin(
        $content,
        forcearray => [ qw(Fld520) ],
    ) unless !$content;
	# manipulate response USMARC VarFlds VarDFlds Notes Fld520 a
	my $summary = \@{$response->{VarFlds}->{VarDFlds}->{Notes}->{Fld520}} if $response;
    return $summary if $summary;
}

sub get_syndetics_toc {
    my ( $isbn ) = @_;

    #normalize the ISBN
    $isbn = _normalize_match_point ($isbn);

    # grab the AWSAccessKeyId: mine is '0V5RRRRJZ3HR2RQFNHR2'
    my $syndetics_client_code = C4::Context->preference('SyndeticsClientCode');

    my $url = "http://syndetics.com/index.aspx?isbn=$isbn/TOC.XML&client=$syndetics_client_code&type=xw10";
    warn $url;
    my $content = get($url);
    warn "could not retrieve $url" unless $content;
    my $xmlsimple = XML::Simple->new();
    my $response = $xmlsimple->XMLin(
        $content,
        forcearray => [ qw(Fld970) ],
    ) unless !$content;
    # manipulate response USMARC VarFlds VarDFlds Notes Fld520 a
    my $toc = \@{$response->{VarFlds}->{VarDFlds}->{SSIFlds}->{Fld970}} if $response;
    return $toc if $toc;
}

sub _normalize_match_point {
	my $match_point = shift;
	(my $normalized_match_point) = $match_point =~ /([\d-]*[X]*)/;
	$normalized_match_point =~ s/-//g;

	return $normalized_match_point;
}

1;
__END__

=head1 NOTES

=head1 AUTHOR

Joshua Ferraro <jmf@liblime.com>

=cut
