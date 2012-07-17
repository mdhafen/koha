#!/usr/bin/perl

# Copyright 2000-2002 Katipo Communications
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

use CGI;

use C4::Auth;
use C4::Output;
use C4::Branch;
use C4::Members;
use C4::Category;
use C4::Debug;

my $cgi = CGI->new;

my $batch_id = $cgi->param('batch_id') || 0;
my $quicksearch = $cgi->param('quicksearch');
my $startfrom = $cgi->param('startfrom')||1;
my $resultsperpage = $cgi->param('resultsperpage')||C4::Context->preference("PatronsPerPage")||20;
my $category = $cgi->param('category') || undef;
my $member = $cgi->param('member') || undef;
my $sort1 = $cgi->param('sort1') || undef;
my $sort2 = $cgi->param('sort2') || undef;
my $orderby = $cgi->param('orderby') || undef;

my ($template, $loggedinuser, $cookie) = get_template_and_user({
                template_name => "patroncards/members-search.tmpl",
                query => $cgi,
                type => "intranet",
                authnotrequired => 0,
                flagsrequired => {borrowers => 1},
                debug => 1,});

$orderby = "surname,firstname" unless $orderby;
$member =~ s/,//g;   #remove any commas from search string
$member =~ s/\*/%/g;

my @categories=C4::Category->all;
my %categories_dislay;

foreach my $category (@categories){
	my $hash={
			category_description=>$$category{description},
			category_type=>$$category{category_type}
			 };
	$categories_dislay{$$category{categorycode}} = $hash;
}

my ( $sort1_values, $sort2_values ) = GetMemberSortValues();
my ( @sort1_loop, @sort2_loop );
foreach ( sort @$sort1_values ) {
    push @sort1_loop, { value => $_, label => $_ } if ( $_ );
}
foreach ( sort @$sort2_values ) {
    push @sort2_loop, { value => $_, label => $_ } if ( $_ );
}

$template->param(
    categories=>\@categories,
    sort1_loop=>\@sort1_loop,
    sort2_loop=>\@sort2_loop,
    );

if ($member || $category || $sort1 || $sort2) {
    my ($count,$results) = 0,0;
    my $patron = {};
    my $all;

    $patron->{'categorycode'} = $category if ($category);
    $patron->{'sort1'} = $sort1 if ($sort1);
    $patron->{'sort2'} = $sort2 if ($sort2);

    if ( C4::Context->preference('IndependantBranches') ) {
	$all = $cgi->param('showallbranches');
	my $mybranch = C4::Branch::mybranch();
	unless ( $patron->{branchcode} || $all ) {
	    $patron->{branchcode} = $mybranch;
	}
    }

    my $orderbyparams=$cgi->param('orderby');
    my @orderby;
    for ( $orderbyparams ) {
	if    ( /cardnumber/ ) { @orderby = ({cardnumber=>0}); }
	elsif ( /categorycode/ ) { @orderby = ({categorycode=>0}); }
	elsif ( /branchcode/ ) { @orderby = ({branchcode=>0}); }
	else         { @orderby = ({surname=>0},{firstname=>0}); }
    }

    my @searchpatron;
    push @searchpatron, $member if ($member);
    push @searchpatron, $patron if ( keys %$patron );

    my $search_scope=($quicksearch?"field_start_with":"contain");
    ($results)=Search(\@searchpatron,\@orderby,undef,undef,["firstname","surname","email","othernames","cardnumber","userid"],$search_scope  ) if (@searchpatron);
    if ($results){
	$count =scalar(@$results);
    }

    my @resultsdata = ();
    my $to = ($count>($startfrom * $resultsperpage)?$startfrom * $resultsperpage:$count);
    for (my $i = ($startfrom-1) * $resultsperpage; $i < $to; $i++){
        #find out stats
        my ($od,$issue,$fines) = GetMemberIssuesAndFines($results->[$i]{'borrowernumber'});
        my %row = (
            count               => $i + 1,
	    %{$categories_dislay{$results->[$i]{'categorycode'}}},
	    %{$results->[$i]},
            overdues            => $od,
            issues              => $issue,
            odissue             => "$od/$issue",
            fines               => ($fines ? sprintf("%.2f",$fines) : ''),
            dateexpiry          => C4::Dates->new($results->[$i]{'dateexpiry'},'iso')->output('syspref'),
        );
        push(@resultsdata, \%row);
    }
    my $base_url = '?' . join('&amp;', map { $_->{term} . '=' . $_->{val} } (
                                            { term => 'member',         val => $member         },
                                            { term => 'category',       val => $category       },
                                            { term => 'sort1',          val => $sort1 },
                                            { term => 'sort2',          val => $sort2 },
                                            { term => 'orderby',        val => $orderby        },
                                            { term => 'resultsperpage', val => $resultsperpage },
                                            { term => 'batch_id',       val => $batch_id       },)
                                        );
    $template->param(
        paginationbar   => pagination_bar(
                                            $base_url,  int( $count / $resultsperpage ) + 1,
                                            $startfrom, 'startfrom'
                                         ),
        startfrom       => $startfrom,
        from            => ($startfrom-1) * $resultsperpage + 1,
        to              => $to,
        multipage       => ($count != $to || $startfrom != 1),
        searching       => "1",
        member          => $member,
        category        => $category,
	sort1           => $sort1,
        sort2           => $sort2,
        numresults      => $count,
        resultsloop     => \@resultsdata,
        batch_id        => $batch_id,
    );
}
else {
    $template->param( batch_id => $batch_id);
}

output_html_with_http_headers $cgi, $cookie, $template->output;

__END__

#script to do a borrower enquiry/bring up borrower details etc
#written 20/12/99 by chris@katipo.co.nz


