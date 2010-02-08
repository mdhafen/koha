#!/usr/bin/perl

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
#
#   Written by Michael Hafen mdhafen@tech.washk12.org on Mar. 2008


=head1 members_via_external.pl

Page to configure the MembersViaExternal feature.  This is for working with the
database table, borrowers_external_structure, which controls which columns for
which patron categories are syncronized with the external database.

=cut

use strict;
use warnings;
use CGI;
use C4::Auth;
use C4::Output;
use C4::Members;  # GetBorrowercategoryList
use C4::MembersExternal;  # GetExternalMappedCategories
# GetExternalMappingsForCategory GetExternalNumCategoryMappings
# GetExternalMapping ModExternalMapping AddExternalMapping DelExternalMapping

my $cgi = new CGI;

# getting the template
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "admin/members_via_external.tmpl",
        query           => $cgi,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { parameters => 1 },
    }
);

my $dbh = C4::Context->dbh;
my $op     = $cgi->param( 'op' ) || '';
my $category = $cgi->param('categorycode') || '';
my @categories = GetExternalMappedCategories();
my ( $numdeleted, $numadded, $numchanged, @errors );
my $nummappings = GetExternalNumCategoryMappings();

if ( $op ) {
    unless ( @categories || $op eq 'Add' ) {
	push @errors, {
	    NO_MAPPINGS => 1,
	};
    } else {
	if ( $op eq 'Change' ) {
	    my $externalid = $cgi->param( 'externalid' );
	    if ( my $mapping = GetExternalMapping( $externalid ) ) {
		my $new_map = {};
		$$new_map{ externalid } = $externalid;
		$$new_map{ categorycode } = $category || $$mapping{ categorycode };
		$$new_map{ liblibrarian } = $cgi->param( 'liblibrarian' );  # this can be empty
		$$new_map{ kohafield } = $cgi->param( 'kohafield' ) || $$mapping{ kohafield };
		$$new_map{ attrib } = $cgi->param( 'attrib' ) || $$mapping{ attrib };
		$$new_map{ filter } = $cgi->param( 'filter' );  # this can be empty
		$$new_map{ dblink } = $cgi->param( 'dblink' ) || $$mapping{ dblink };
		ModExternalMapping( $new_map );
		$numchanged++;
	    }
	} elsif ( $op eq 'Add' ) {
	    my $new_map = {};
	    $$new_map{ categorycode } = $category;
	    $$new_map{ liblibrarian } = $cgi->param( 'liblibrarian' );
	    $$new_map{ kohafield } = $cgi->param( 'kohafield' );
	    $$new_map{ attrib } = $cgi->param( 'attrib' );
	    $$new_map{ filter } = $cgi->param( 'filter' );
	    $$new_map{ dblink } = $cgi->param( 'dblink' );
	    if ( my $mapping = GetExternalMapping( undef, $category, $$new_map{kohafield} ) ) {
		push @errors, {
		    MAPPING_EXISTS => 1,
		};
	    } else {
		AddExternalMapping( $new_map );
		$numadded++;
	    }
	} elsif ( $op eq 'Delete' ) {
	    my $externalid = $cgi->param( 'externalid' );
	    DelExternalMapping( $externalid );
	    $numdeleted++;
	} elsif ( $op eq 'Delete All' ) {
	    my $mappings = GetExternalMappingsForCategory( $category );
	    foreach my $map ( @$mappings ) {
		DelExternalMapping( $map->{externalid} );
		$numdeleted++;
	    }
	} else {
	    push @errors, {
		INVALID_OP => 1,
	    };
	}
	@categories = GetExternalMappedCategories();  # rebuild after changes.
    }
}

my $allcategories = GetBorrowercategoryList();
my @categoryloop;
foreach my $this_category ( @$allcategories ) {
    my $cat = $$this_category{ categorycode };
    my $mappings = [];
    if ( $$nummappings{ $cat } ) {
	$mappings = GetExternalMappingsForCategory( $cat );
    } else {
	$$nummappings{ $cat } = '0';
    }
    push @categoryloop, {
        categorycode => $cat,
        categoryname => $this_category->{description},
	num_mappings => $$nummappings{ $cat },
	mappingsloop => $mappings,
	categorycodeselected => ( $cat eq $category ),
    };
}

$template->param(
    categories => scalar @categories,
    categoryloop => \@categoryloop,
    op => $op,
    categorycode => $category,
    num_deleted => $numdeleted,
    num_added => $numadded,
    num_changed => $numchanged,
    errors => \@errors,
    );

#writing the template
output_html_with_http_headers $cgi, $cookie, $template->output;
