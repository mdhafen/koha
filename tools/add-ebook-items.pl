#!/usr/bin/perl

# Script for Adding item records to biblios using an imported Staged File Batch.

# Koha library project  www.koha-community.org

# Licensed under the GPL

# Copyright 2013 Michael Hafen for Washington County School District
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
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use strict;
use warnings;

# standard or CPAN modules used
use CGI;

# Koha modules used
use C4::Context;
use C4::Auth;
use C4::Output;
use C4::Koha qw/GetItemTypes/;
use C4::Items qw/AddItem DelItem/;
use C4::Biblio qw/GetMarcBiblio GetMarcUrls ModBiblio/;
use C4::ImportBatch qw/GetImportBatchRangeDesc GetImportBibliosRange GetImportBatch GetImportRecordMatches/;
use C4::Branch qw/GetBranchesLoop onlymine mybranch/;

my $input = new CGI;

my $op = $input->param('op') || '';
my $reverse = $input->param('reverse') || '';
my $batch_id = $input->param('batch_id') || 0;
my $handle_url = $input->param('handle_url') || '';
my $itype = $input->param('itype') || '';
my $entered_url = $input->param('entered_url') || '';
my @biblios = $input->param('biblios');

my ($template, $loggedinuser, $cookie)
	= get_template_and_user({template_name => "tools/add-ebook-items.tmpl",
					query => $input,
					type => "intranet",
					authnotrequired => 0,
					flagsrequired => {tools => 'manage_staged_marc'},
					debug => 0,
					});

my $url_action = "";
for ( $handle_url ) {
    if    ( $_ eq 'nothing' ) { $url_action = 'nothing' }
    elsif ( $_ eq 'copy' )    { $url_action = 'copy' }
    elsif ( $_ eq 'move' )    { $url_action = 'move' }
    elsif ( $_ eq 'enter' )    { $url_action = 'enter' }
}

my $branch = onlymine() ? mybranch() : $input->param('branchcode') || mybranch();

if ($op eq 'submit') {
    my $num_bibs = 0;
    my $num_items_added = 0;
    my $num_items_deleted = 0;

    if ( $batch_id && $branch && ( $url_action || $reverse ) ) {
        my %biblios_only;
        if ( @biblios ) {
            %biblios_only = map { $_ => 1 } @biblios;
        }

        # this sql query is my best guess as to how an existing ebook item looks
        my $dbh = C4::Context->dbh;
        my $sth = $dbh->prepare("SELECT * FROM items WHERE biblionumber = ? AND homebranch = ? AND ( barcode = '' OR barcode IS NULL )") || die $dbh->errstr;

        # check if we should backport the item type to the biblio
        my $sth_itemtype = $dbh->prepare("SELECT itemtype,GROUP_CONCAT(DISTINCT itype) as itypes FROM items CROSS JOIN biblioitems USING (biblioitemnumber) WHERE items.biblionumber = ? AND (itemtype = '' OR itemtype IS NULL) GROUP BY biblioitemnumber")

        my $batch = GetImportBatch( $batch_id );
        @biblios = @{ GetImportBibliosRange( $batch_id ) };

        foreach my $biblio ( @biblios ) {
            unless ( $biblio->{matched_biblionumber} ) {
                my $match = GetImportRecordMatches( $biblio->{'import_record_id'}, 1);
                $biblio->{matched_biblionumber} = @$match ? $match->[0]->{'biblionumber'} : 0;
            }    

            next if ( %biblios_only && ! $biblios_only{ $biblio->{matched_biblionumber} } );

            $num_bibs++;
            if ( $biblio->{matched_biblionumber} && ( $biblio->{status} eq 'imported' || $biblio->{status} eq 'ignored' ) ) {
                # Make sure there isn't already an item record
                $sth->execute( $biblio->{matched_biblionumber}, $branch );
                my $data = $sth->fetchrow_hashref || {};
                if ( $reverse ) {
                    do { 
                        if ( $data->{'uri'} ) {
                            DelItem( $dbh, $data->{'biblionumber'}, $data->{'itemnumber'} );
                            $num_items_deleted++;
                        }
                    } while ( $data = $sth->fetchrow_hashref );
                    next;
                }
                else {
                    next if ( %$data && $data->{itemnumber} );
                }

                $num_items_added++;

                my $bib = GetMarcBiblio($biblio->{matched_biblionumber});

                my $item;
                $item->{homebranch} = $branch;
                $item->{holdingbranch} = $branch;
                $item->{itype} = $itype;

                if ( $url_action ne 'nothing' ) {
                    my $uri;
                    if ( $url_action eq 'enter' ) {
                        $uri = $entered_url;
                    }
                    else {
                        my $marc_urls = GetMarcUrls( $bib, C4::Context->preference("marcflavour") );
                        if ( scalar @$marc_urls == 1 ) {
                            $uri = $marc_urls->[0];
                        }
                        else {
                            foreach my $field ( $bib->field('856') ) {
                                my $marcurl = $field->subfield('u');
                                my $s3 = $field->subfield('3');
                                # FIXME this is a big assumtion
                                next if ( $s3 );
                                unless ( $marcurl =~ /^\w+:/ ) {
                                    if ( $field->indicator(1) eq '7' ) {
                                        $marcurl = $field->subfield('2') . "://" . $marcurl;
                                    } elsif ( $field->indicator(1) eq '1' ) {
                                        $marcurl = 'ftp://' . $marcurl;
                                    } elsif ( $field->indicator(1) eq '4' ) {
                                        $marcurl = 'http://' . $marcurl;
                                    }
                                }
                                $uri = $marcurl || '';
                            }
                        }

                        if ( $url_action eq 'move' ) {
                            my $mod = 0;
                            for my $field ( $bib->field('856') ) {
                                if ( $uri eq $field->subfield('u') ) {
                                    $bib->delete_field( $field );
                                    $mod = 1;
                                }
                            }
                            ModBiblio( $bib, $biblio->{matched_biblionumber} ) if ( $mod );
                        }
                    }
                    $item->{uri} = $uri;
                }


                AddItem( $item, $biblio->{matched_biblionumber} );

                $sth_itemtype->execute( $biblio->{matched_biblionumber} );
                my $data = $sth->fetchrow_hashref || {};
                if( %$data && index( $data->{'itypes'}, ',' ) == -1 ) {
                    # only 1 itype
                    my $framework = GetFrameworkCode( $biblio->{matched_biblionumber} );
                    $framework = '' unless ( $framework );
                    my ( $itypetag, $itypefield ) = GetMarcFromKohaField( "biblioitems.itemtype", $framework );

                    if ( my $koha_field = $bib->field( $itypetag ) ) {
                        $koha_field->update( $itypefield => $itype );
                    } else {
                        my $new_field = new MARC::Field( $itypetag, '0', '0',
                                                         $itypefield => $itype );
                        $bib->add_fields( $new_field );
                    }
                    &ModBiblio( $bib, $biblio->{matched_biblionumber}, $framework );
                }
            }
        }

        $template->param(
            'RESULTS' => 1,  # process stage
            num_bibs => $num_bibs,
            num_items_added => $num_items_added,
            num_items_deleted => $num_items_deleted,
            );
    }
    else {
        $template->param(
            error => 1,
            'NO_BATCH' => !$batch_id,
            'NO_BRANCH' => !$branch,
            'NO_URI_ACTION' => !$url_action,
            'INIT' => 1,
            );
    }
} elsif ( $op eq 'select' ) {
    # list staged batches with imported status
    my $batches = GetImportBatchRangeDesc() || [];
    my @list = grep { $_->{'import_status'} eq 'imported' } @$batches;
    @list = sort { $b->{'upload_timestamp'} cmp $a->{'upload_timestamp'} } @list;
    $template->param(
        'LIST' => 1,  # process stage
        batch_list => \@list
        );
} elsif ( $op eq 'details' ) {
    # get details of a staged batch
    if ( $batch_id ) {
        my $batch = GetImportBatch( $batch_id );
        my $biblios = GetImportBibliosRange( $batch_id );

        foreach my $biblio ( @$biblios ) {
            $biblio->{citation} = join ' ', ( $biblio->{title}, $biblio->{author} );
            $biblio->{citation} .= ' ('. join( ',', ($biblio->{isbn},$biblio->{issn}) ) .')' if ( $biblio->{isbn} || $biblio->{issn} );
            unless ( $biblio->{matched_biblionumber} ) {
                my $match = GetImportRecordMatches( $biblio->{'import_record_id'}, 1);
                $biblio->{matched_biblionumber} = @$match ? $match->[0]->{'biblionumber'} : 0;
            }    
            $biblio->{can_add} = $biblio->{matched_biblionumber} &&
                ( $biblio->{status} eq 'imported' || $biblio->{status} eq 'ignored' )
        }

        $template->param(
            'DETAIL' => 1,  # process stage
            'records_list' => $biblios,
            %$batch,
            );
    }
    else {
        $template->param(
            'error' => 1,
            'NO_BATCH' => 1,
            'INIT' => 1,  # process stage
            );
    }
} else {
    # initial form

    # custom default item type
    $itype ||= 'OM';
    my $itemtypes = GetItemTypes();
    my @itemtypes_loop;
    foreach my $it ( sort keys %$itemtypes ) {
        my $selected = ( $it eq $itype ) ? 1 : 0;
        my $row = {
            value => $it,
            selected => $selected,
            description => $itemtypes->{ $it }->{'description'},
        };
        push @itemtypes_loop, $row;
    }

    $template->param(
        'INIT' => 1,  # process stage
        branch_list => GetBranchesLoop($branch),
        itype_list => \@itemtypes_loop,
        );
}

$template->param(
    batch_id => $batch_id,
    reverse => $reverse,
    "handle_url_$url_action" => 1,
    branchcode => $branch,
    entered_url => $entered_url,
    itype => $itype,
    biblios => [ map { { value => $_ } } @biblios ],
    );

output_html_with_http_headers $input, $cookie, $template->output;
