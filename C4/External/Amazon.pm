package C4::External::Amazon;
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
use C4::Koha;

use strict;
use warnings;

use vars qw($VERSION @ISA @EXPORT);

BEGIN {
    require Exporter;
    $VERSION = 0.03;
    @ISA = qw(Exporter);
    @EXPORT = qw(
        get_amazon_details
        get_amazon_tld
    );
}


sub get_amazon_tld {
    my %tld = (
        CA => '.ca',
        DE => '.de',
        FR => '.fr',
        JP => '.jp',
        UK => '.co.uk',
        US => '.com',
    );

    my $locale = C4::Context->preference('AmazonLocale');
    my $tld = $tld{ $locale } || '.com'; # default top level domain is .com
    return $tld;
}


=head1 NAME

C4::External::Amazon - Functions for retrieving Amazon.com content in Koha

=head2 FUNCTIONS

This module provides facilities for retrieving Amazon.com content in Koha

=over

=item get_amazon_detail( $isbn, $record, $marcflavour, $services )

Get editorial reviews, customer reviews, and similar products using Amazon Web Services.

Parameters:

=over

=item $isbn

Biblio record isbn

=item $record

Biblio MARC record

=item $marcflavour

MARC flavor, MARC21 or UNIMARC

=item $services

Requested Amazon services: A ref to an array. For example,
[ 'Similarities', 'EditorialReviews', 'Reviews' ].
No other service will be accepted. Services must be spelled exactly.
If no sercice is requested, AWS isn't called.

=back

=item get_amazon_tld()

Get Amazon Top Level Domain depending on Amazon local preference: AmazonLocal.
For example, if AmazonLocal is 'UK', returns '.co.uk'.

=back

=cut


sub get_amazon_details {
    my ( $isbn, $record, $marcflavour, $aws_ref ) = @_;

    return unless defined $aws_ref;
    my @aws = @$aws_ref;
    return if $#aws == -1;

    # Normalize the fields
    $isbn = GetNormalizedISBN($isbn);
    my $upc = GetNormalizedUPC($record,$marcflavour);
    my $ean = GetNormalizedEAN($record,$marcflavour);

    # warn "ISBN: $isbn | UPC: $upc | EAN: $ean";

    my ( $id_type, $item_id);
    if (defined($isbn) && length($isbn) == 13) { # if the isbn is 13-digit, search Amazon using EAN
	$id_type = 'EAN';
	$item_id = $isbn;
    }
    elsif ($isbn) {
	$id_type = 'ASIN';
	$item_id = $isbn;
    }
    elsif ($upc) {
	$id_type = 'UPC';
	$item_id = $upc;
    }
    elsif ($ean) {
	$id_type = 'EAN';
	$item_id = $upc;
    }
    else { # if no ISBN, UPC, or EAN exists, do not even attempt to query Amazon
	return undef;
    }

    # grab the item format to determine Amazon search index
    # FIXME: This is MARC21 specific
    my $format = substr $record->leader(), 6, 1; 
    my $formats;
    $formats->{'a'} = 'Books';
    $formats->{'g'} = 'Video';
    $formats->{'j'} = 'Music';

    my $search_index = $formats->{$format};

    # Determine which content to grab in the request

    # Determine correct locale
    my $tld = get_amazon_tld();

    # grab the AWSAccessKeyId: mine is '0V5RRRRJZ3HR2RQFNHR2'
    my $aws_access_key_id = C4::Context->preference('AWSAccessKeyID');

    #grab the associates tag: mine is 'kadabox-20'
    my $af_tag=C4::Context->preference('AmazonAssocTag');
    my $response_group = join( ',',  @aws );
    my $url = "http://ecs.amazonaws$tld/onca/xml?Service=AWSECommerceService&AWSAccessKeyId=$aws_access_key_id&Operation=ItemLookup&AssociateTag=$af_tag&Version=2007-01-15&ItemId=$item_id&IdType=$id_type&ResponseGroup=$response_group";
    if ($id_type ne 'ASIN') {
	$url .= "&SearchIndex=$search_index";
    }
    #warn $url;
    my $content = get($url);
    warn "could not retrieve $url" unless $content;
    my $xmlsimple = XML::Simple->new();
    my $response = $xmlsimple->XMLin(
        $content,
        forcearray => [ qw(SimilarProduct EditorialReview Review) ],
    ) unless !$content;
    return $response;
}

sub check_search_inside {
        my $isbn = shift;
        my $ua = LWP::UserAgent->new(
        agent => "Mozilla/4.76 [en] (Win98; U)",
        keep_alive => 1,
        env_proxy => 1,
        );
        my $available = 1;
        my $uri = "http://www.amazon.com/gp/reader/$isbn/ref=sib_dp_pt/002-7879865-0184864#reader-link";
        my $req = HTTP::Request->new(GET => $uri);
        $req->header (
                'Accept' => 'image/gif, image/x-xbitmap, image/jpeg, image/pjpeg, image/png, */*',
                'Accept-Charset' => 'iso-8859-1,*,utf-8',
                'Accept-Language' => 'en-US' );
        my $res = $ua->request($req);
        my $content = $res->content();
        if ($content =~ m/This book is temporarily unavailable/) {
            undef $available;
        }
        return $available;
}

1;
__END__

=head1 NOTES

=head1 AUTHOR

Joshua Ferraro <jmf@liblime.com>

=cut
